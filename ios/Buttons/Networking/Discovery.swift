import Network
import Foundation

/// One desktop found on the LAN — its connection endpoint and the
/// `device_id` from its mDNS TXT record. `device_id` is what makes
/// reconnect matching possible (Implementation Notes #3: it's generated
/// once on the desktop and never changes).
struct DiscoveredDesktop: Identifiable, Equatable {
    var id: String { deviceId }
    let deviceId: String
    let endpoint: NWEndpoint
}

/// Browses for `_buttons._tcp` on the LAN. No manual IP entry this slice
/// (Scope → Out item 7) — mDNS is the only discovery path. `@Observable`
/// from the start, not extracted later: this owns a live `NWBrowser`
/// subscription shared across the pairing and reconnect flows — see
/// CLAUDE.md's "layer that owns a live connection" rule.
@Observable
final class DesktopDiscovery {
    private(set) var discovered: [DiscoveredDesktop] = []

    private var browser: NWBrowser?

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        // .bonjour(type:domain:) never resolves the TXT record — metadata
        // stays .none, so device_id matching below always fails silently.
        // .bonjourWithTXTRecord is the descriptor that actually populates
        // result.metadata with .bonjour(txt).
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_buttons._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let devices = results.compactMap(Self.discoveredDesktop(from:))
            DispatchQueue.main.async {
                self?.discovered = devices
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Returns the endpoint advertising the given `device_id`, if mDNS has found it.
    ///
    /// - Parameter deviceId: The `device_id` stored in the Keychain at pairing time.
    /// - Returns: `nil` until a matching advertisement arrives — callers poll.
    // `device_id` is stable for the desktop's lifetime (Implementation
    // Notes #3), which is what makes this matching scheme work at all.
    func endpoint(forDeviceId deviceId: String) -> NWEndpoint? {
        discovered.first(where: { $0.deviceId == deviceId })?.endpoint
    }

    private static func discoveredDesktop(from result: NWBrowser.Result) -> DiscoveredDesktop? {
        guard case let .bonjour(txt) = result.metadata,
              let deviceId = txt["device_id"]
        else { return nil }
        return DiscoveredDesktop(deviceId: deviceId, endpoint: result.endpoint)
    }
}
