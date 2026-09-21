import Foundation
import Network

/// A scanned QR's decoded payload: `"<device_id> <lan_ip> <port>
/// <pairing_token>"`, four space-delimited fields — not `ip:port`
/// colon-joined. See `wire.proto`'s Interface section: `mdns-sd` can hand
/// back a link-local IPv6 address with a zone index (`fe80::1%en0`), which
/// would force bracket-aware parsing on this side for a purely cosmetic
/// gain. Don't "clean this up" without re-reading that note.
struct PairingPayload: Equatable {
    let deviceId: String
    let host: String
    let port: UInt16
    let token: String

    init?(qrString: String) {
        let parts = qrString.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 4, let port = UInt16(parts[2]) else { return nil }
        deviceId = String(parts[0])
        host = String(parts[1])
        self.port = port
        token = String(parts[3])
    }
}

/// A known desktop's persisted credential. `deviceName` is non-optional —
/// every real sender (desktop app, `websocat` fixture) populates it, so a
/// missing value is an anomaly absorbed into a fallback at the wire
/// boundary (`Connection.swift`), not threaded through as `Optional`
/// here. See docs/slices/11a. Pairing Flow Robustness.spec.md.
struct StoredPairing: Equatable {
    let deviceId: String
    let authToken: String
    let deviceName: String
}

/// `authToken`/`deviceName` packed into one Keychain value — `deviceId` is
/// the key, not repeated in the value. `deviceName` stays optional here
/// (decode-tolerant of an entry written before this field existed) even
/// though `StoredPairing.deviceName` isn't — `knownDevices()` is the
/// boundary that resolves the fallback.
private struct StoredCredential: Codable {
    let authToken: String
    let deviceName: String?
}

/// Pairing-specific logic layered on top of `SecretStore` — one Keychain
/// entry per known device, plus a separate pointer to which one is
/// active. Two namespaces, not one, so listing known devices never has to
/// filter out the active-pointer entry by name (it's physically in a
/// different namespace). See docs/slices/11a. Pairing Flow Robustness.spec.md.
final class PairingStore {
    private static let devicesNamespace = "gg.pekk.buttons.pairing.devices"
    private static let activeNamespace = "gg.pekk.buttons.pairing.active"
    private static let activeKey = "active"

    private let secrets: SecretStore

    /// Defaults to the real Keychain; tests inject a fake `SecretStore`.
    init(secrets: SecretStore = KeychainStore()) {
        self.secrets = secrets
    }

    func knownDevices() -> [StoredPairing] {
        secrets.keys(namespace: Self.devicesNamespace).compactMap { deviceId in
            guard let raw = secrets.read(namespace: Self.devicesNamespace, key: deviceId),
                let credential = try? JSONDecoder().decode(StoredCredential.self, from: Data(raw.utf8))
            else { return nil }
            return StoredPairing(
                deviceId: deviceId, authToken: credential.authToken,
                deviceName: credential.deviceName ?? "Unnamed Device"
            )
        }
    }

    func activeDeviceId() -> String? {
        secrets.read(namespace: Self.activeNamespace, key: Self.activeKey)
    }

    func save(_ pairing: StoredPairing, makeActive: Bool = true) {
        let credential = StoredCredential(authToken: pairing.authToken, deviceName: pairing.deviceName)
        guard let data = try? JSONEncoder().encode(credential), let json = String(data: data, encoding: .utf8) else { return }
        secrets.write(json, namespace: Self.devicesNamespace, key: pairing.deviceId)
        if makeActive { setActive(deviceId: pairing.deviceId) }
    }

    func setActive(deviceId: String) {
        secrets.write(deviceId, namespace: Self.activeNamespace, key: Self.activeKey)
    }

    func remove(deviceId: String) {
        secrets.delete(namespace: Self.devicesNamespace, key: deviceId)
    }
}

/// One row in the pairing picker — a known device, a freshly-discovered
/// one, or both.
enum PairedDeviceStatus {
    case connectable(endpoint: NWEndpoint)  // known + discovered
    case offline                            // known + not discovered
    case pairable(endpoint: NWEndpoint)     // discovered + unknown
}

struct PairedDeviceRow: Identifiable {
    var id: String { deviceId }
    let deviceId: String
    /// Never a raw UUID — users should never see one. Two distinct
    /// literal fallbacks, not `Optional`: "known but no name" and "never
    /// paired, no name to have" are different facts, not the same nil.
    let name: String
    let status: PairedDeviceStatus
}

/// Keyed by `deviceId`. `name` always comes from the *stored* credential,
/// never a live mDNS value — `07c`'s Out item 1 deliberately keeps the
/// device name off the (unauthenticated) Bonjour TXT record.
func mergedDeviceRows(
    known: [StoredPairing], discovered: [DiscoveredDesktop]
) -> [PairedDeviceRow] {
    let discoveredById = Dictionary(discovered.map { ($0.deviceId, $0) }, uniquingKeysWith: { first, _ in first })
    let knownIds = Set(known.map(\.deviceId))

    let knownRows = known.map { pairing in
        PairedDeviceRow(
            deviceId: pairing.deviceId,
            name: pairing.deviceName,
            status: discoveredById[pairing.deviceId].map { .connectable(endpoint: $0.endpoint) } ?? .offline
        )
    }
    let newRows = discovered
        .filter { !knownIds.contains($0.deviceId) }
        .map { PairedDeviceRow(deviceId: $0.deviceId, name: "New Device", status: .pairable(endpoint: $0.endpoint)) }

    return knownRows + newRows
}

/// The state of a silent mDNS reconnect attempt.
///
/// Kept separate from `PairingSession.lastError`, which is QR-scan-specific.
enum AutoReconnectState: Equatable {
    case idle
    case searching
    case notFound
}

/// Drives a pairing attempt — either a scanned QR or a silent mDNS
/// reconnect — and the Keychain write on success. Owns `DesktopDiscovery`
/// outright (not passed per-call) and exposes the merged known/discovered
/// list `PairingView` renders — see docs/slices/11a. Pairing Flow
/// Robustness.spec.md, Design decisions 7/10.
///
/// QR scanning itself (`DataScannerViewController`) lives in
/// `Views/PairingView.swift`; this only takes the decoded string.
@MainActor
@Observable
final class PairingSession {
    private(set) var lastError: String?
    private(set) var autoReconnectState: AutoReconnectState = .idle

    /// What `PairingView` renders — it never touches `DesktopDiscovery`
    /// or `PairingStore` directly. Refreshed explicitly, not computed: a
    /// Keychain write has no signal SwiftUI can observe on its own.
    private(set) var deviceRows: [PairedDeviceRow] = []

    /// Whether a silent reconnect is already in progress — derived from
    /// `autoReconnectState` rather than a separate stored flag, so
    /// `attemptAutoReconnect` has one source of truth for its own dedupe
    /// guard instead of two things to keep in sync.
    var isReconnectInFlight: Bool { autoReconnectState == .searching }

    /// Passthrough so `PairingView` doesn't need its own `DesktopDiscovery`
    /// reference just for this one flag.
    var isLocalNetworkDenied: Bool { discovery.isLocalNetworkDenied }

    private let connection: DesktopConnection
    private let discovery: DesktopDiscovery
    private let pairingStore: PairingStore

    /// No default on `pairingStore` — there's exactly one composition
    /// root (`ButtonsApp.swift`); a default here would hide where wiring
    /// actually happens for no benefit.
    init(connection: DesktopConnection, discovery: DesktopDiscovery, pairingStore: PairingStore) {
        self.connection = connection
        self.discovery = discovery
        self.pairingStore = pairingStore
        refreshDeviceRows()
    }

    private func refreshDeviceRows() {
        deviceRows = mergedDeviceRows(known: pairingStore.knownDevices(), discovered: discovery.discovered)
    }

    func pair(scannedQR: String) {
        guard let payload = PairingPayload(qrString: scannedQR) else {
            lastError = "unrecognized QR code"
            return
        }
        lastError = nil
        connection.connect(host: payload.host, port: payload.port, token: payload.token) {
            [weak self] (result: PairResult) in
            self?.handlePairResult(result, deviceId: payload.deviceId)
        }
    }

    /// Pairs using a `device_id` already resolved by `DesktopDiscovery`, with no QR.
    ///
    /// - Parameters:
    ///   - stored: The Keychain-backed credential to reconnect with.
    ///   - endpoint: The desktop's resolved Bonjour endpoint.
    func reconnect(stored: StoredPairing, endpoint: NWEndpoint) {
        lastError = nil
        connection.connect(toBonjourEndpoint: endpoint, token: stored.authToken) {
            [weak self] (result: PairResult) in
            self?.handlePairResult(result, deviceId: stored.deviceId)
        }
    }

    /// The picker's "Connect" action — looks up the matching stored
    /// credential and reconnects. Tapping a device while a *different*
    /// one is already live currently no-ops silently
    /// (`DesktopConnection`'s single-slot guard drops the attempt) —
    /// Design decision 12, still open, not resolved by this method.
    func connect(to row: PairedDeviceRow) {
        guard case .connectable(let endpoint) = row.status,
            let stored = pairingStore.knownDevices().first(where: { $0.deviceId == row.deviceId })
        else { return }
        reconnect(stored: stored, endpoint: endpoint)
    }

    /// A successful pair/reconnect always makes that device active (the
    /// auto-reconnect path already targeted the active device, so this is
    /// a no-op there; a manual "Connect" tap is exactly DoD item 6's
    /// "makes it active"). `deviceName` overwrites the stored value on
    /// every success, not just first pair — a desktop rename reaches the
    /// phone without a separate push mechanism.
    private func handlePairResult(_ result: PairResult, deviceId: String) {
        switch result {
        case .success(let authToken, let deviceName):
            pairingStore.save(
                StoredPairing(deviceId: deviceId, authToken: authToken, deviceName: deviceName),
                makeActive: true
            )
            refreshDeviceRows()
        case .failure(let message):
            lastError = message
        }
    }

    /// Starts the mDNS browse, and — if a known device is active — polls
    /// for a silent reconnect to specifically that one.
    ///
    /// The browse always starts, even with no active device: it's what
    /// lets a fresh install detect a denied Local Network permission
    /// before the user ever taps "Scan QR Code," not just on reconnect.
    /// With no active device, `autoReconnectState` itself stays `.idle` —
    /// the landing screen shows first-pair copy, not a false "searching"
    /// state.
    // `discovery.start()` runs before the in-flight guard, not after —
    // restarting the browse is what recovers from a Local-Network-denied-
    // then-granted permission change (07d spec, DoD item 6), and that has
    // to happen even when a reconnect poll is already running. Moving
    // `start()` below the guard would silently break that recovery path.
    func attemptAutoReconnect() async {
        discovery.start()
        guard !isReconnectInFlight, let deviceId = pairingStore.activeDeviceId(),
            let stored = pairingStore.knownDevices().first(where: { $0.deviceId == deviceId })
        else { return }
        autoReconnectState = .searching
        // ~5s of polling at 250ms — generous for LAN mDNS, not a
        // network round trip to wait indefinitely on. Also doubles as
        // the picker's periodic refresh while this runs.
        for _ in 0..<20 {
            refreshDeviceRows()
            if let endpoint = discovery.endpoint(forDeviceId: stored.deviceId) {
                autoReconnectState = .idle
                reconnect(stored: stored, endpoint: endpoint)
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        // Not found within the window — landing state shows this and
        // still offers "Scan QR Code" as the recovery path.
        autoReconnectState = .notFound
    }
}
