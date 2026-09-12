import Foundation
import Network
import Security

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

/// The persisted pairing credential — `device_id` + `auth_token` — read on
/// launch to attempt a silent reconnect (Files to Touch #17), written once
/// a fresh pair's `PairResponse` confirms it.
struct StoredPairing: Equatable {
    let deviceId: String
    let authToken: String
}

/// Keychain-backed, not Keychain-only by convention — a secret like
/// `auth_token` belongs there, not `UserDefaults`/a plist, the mobile-side
/// analog of desktop's `device.json` getting real file permissions instead
/// of `localStorage`.
enum PairingStore {
    private static let service = "gg.pekk.buttons.pairing"
    private static let deviceIdAccount = "device_id"
    private static let authTokenAccount = "auth_token"

    static func load() -> StoredPairing? {
        guard let deviceId = readString(account: deviceIdAccount),
              let authToken = readString(account: authTokenAccount)
        else { return nil }
        return StoredPairing(deviceId: deviceId, authToken: authToken)
    }

    static func save(_ pairing: StoredPairing) {
        writeString(pairing.deviceId, account: deviceIdAccount)
        writeString(pairing.authToken, account: authTokenAccount)
    }

    static func clear() {
        delete(account: deviceIdAccount)
        delete(account: authTokenAccount)
    }

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readString(account: String) -> String? {
        var lookup = query(account: account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeString(_ value: String, account: String) {
        let base = query(account: account)
        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]

        let status = SecItemCopyMatching(base as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        } else {
            var newItem = base
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }
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
/// reconnect — and the Keychain write on success.
///
/// QR scanning itself (`DataScannerViewController`) lives in
/// `Views/PairingView.swift`; this only takes the decoded string.
@Observable
final class PairingSession {
    private(set) var lastError: String?
    private(set) var autoReconnectState: AutoReconnectState = .idle

    private let connection: DesktopConnection

    init(connection: DesktopConnection) {
        self.connection = connection
    }

    func pair(scannedQR: String) {
        guard let payload = PairingPayload(qrString: scannedQR) else {
            lastError = "unrecognized QR code"
            return
        }
        lastError = nil
        connection.connect(host: payload.host, port: payload.port, token: payload.token) { [weak self] (result: PairResult) in
            switch result {
            case .success(let authToken):
                PairingStore.save(StoredPairing(deviceId: payload.deviceId, authToken: authToken))
            case .failure(let message):
                self?.lastError = message
            }
        }
    }

    /// Pairs using a `device_id` already resolved by `DesktopDiscovery`, with no QR.
    ///
    /// - Parameters:
    ///   - stored: The Keychain-backed credential to reconnect with.
    ///   - endpoint: The desktop's resolved Bonjour endpoint.
    // `auth_token` doesn't rotate on reconnect (v1), so nothing new needs
    // writing to Keychain here.
    func reconnect(stored: StoredPairing, endpoint: NWEndpoint) {
        lastError = nil
        connection.connect(toBonjourEndpoint: endpoint, token: stored.authToken) { [weak self] (result: PairResult) in
            if case .failure(let message) = result {
                self?.lastError = message
            }
        }
    }

    /// Starts a silent mDNS reconnect using the stored pairing, if there is one.
    ///
    /// Does nothing when the Keychain holds no pairing; `autoReconnectState`
    /// stays `.idle` so the landing screen shows first-pair copy rather
    /// than a false "searching" state.
    ///
    /// - Parameter discovery: Browser to start and poll; left running on return.
    func attemptAutoReconnect(discovery: DesktopDiscovery) {
        guard let stored = PairingStore.load() else { return }
        autoReconnectState = .searching
        discovery.start()
        Task {
            // ~5s of polling at 250ms — generous for LAN mDNS, not a
            // network round trip to wait indefinitely on.
            for _ in 0..<20 {
                if let endpoint = discovery.endpoint(forDeviceId: stored.deviceId) {
                    autoReconnectState = .idle
                    reconnect(stored: stored, endpoint: endpoint)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            // Not found within the window — landing state shows this and
            // still offers "Scan QR Code" as the recovery path (Scope →
            // Out item 7: mDNS-only reconnect, QR rescan is the fallback).
            autoReconnectState = .notFound
        }
    }
}
