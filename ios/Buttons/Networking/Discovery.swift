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

        let browser = NWBrowser(for: .bonjour(type: "_buttons._tcp", domain: nil), using: parameters)
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

    /// Looks up a specific desktop by its stored `device_id` — the
    /// reconnect path (Files to Touch #13/#17): Keychain has a pair, mDNS
    /// browse, match by `device_id`, connect. Returns nil until mDNS
    /// actually finds a matching advertisement.
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
