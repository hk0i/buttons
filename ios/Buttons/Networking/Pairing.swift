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

/// Glues a scanned QR string to a connection attempt and the Keychain
/// write on success — the fresh-pair path (Files to Touch #15/#16). QR
/// scanning itself (`DataScannerViewController`) lives in
/// `Views/PairingView.swift`; this only takes the decoded string.
///
/// Named `Session`, not `Coordinator` — "Coordinator" is a specific iOS
/// pattern (navigation-flow ownership) this isn't, and
/// `QRScannerRepresentable.Coordinator` in `PairingView.swift` is already
/// that pattern's real coordinator; reusing the word here would collide.
/// This is instance state for one pairing attempt (`lastError`) across an
/// async round trip — `Session` says that.
@Observable
final class PairingSession {
    private(set) var lastError: String?

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

    /// The reconnect path (Files to Touch #17): a stored pair plus mDNS
    /// finding that `device_id` on the LAN, no QR involved. `auth_token`
    /// doesn't change on a successful reconnect (no rotation, v1), so
    /// nothing new needs writing to Keychain here.
    func reconnect(stored: StoredPairing, endpoint: NWEndpoint) {
        lastError = nil
        connection.connect(toBonjourEndpoint: endpoint, token: stored.authToken) { [weak self] (result: PairResult) in
            if case .failure(let message) = result {
                self?.lastError = message
            }
        }
    }
}
