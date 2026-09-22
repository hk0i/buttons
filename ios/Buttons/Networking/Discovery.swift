import Foundation
import Network

/// One desktop found on the LAN — its connection endpoint and the
/// `device_id` from its mDNS TXT record. `device_id` is generated once on
/// the desktop and never changes, which is what makes reconnect matching
/// possible.
struct DiscoveredDesktop: Identifiable, Equatable {
    var id: String { deviceId }
    let deviceId: String
    let endpoint: NWEndpoint
    /// The Bonjour instance name (RFC 6763 §4.1.1) — same mechanism AirPlay
    /// uses for a live-editable display name. Empty only if `endpoint`
    /// isn't a `.service` case, which shouldn't happen for a
    /// `_buttons._tcp` result.
    let name: String
}

/// Browses for `_buttons._tcp` on the LAN. No manual IP entry this slice —
/// mDNS is the only discovery path (slice 07 spec, § Scope → Out, "Manual
/// IP entry / QR redisplay-for-reconnect fallback"). `@Observable`
/// from the start, not extracted later: this owns a live `NWBrowser`
/// subscription shared across the pairing and reconnect flows — see
/// CLAUDE.md's "layer that owns a live connection" rule.
@Observable
final class DesktopDiscovery {
    private(set) var discovered: [DiscoveredDesktop] = []

    /// Whether the last browse attempt hit a denied Local Network
    /// permission specifically, distinct from any other reason no desktop
    /// has been found yet.
    // Reset at the top of `start()`, not just set on denial — a fresh
    // attempt after permission is re-granted should stop reporting the
    // stale denial. `start()` is re-invoked on app-foreground as of slice
    // 07d (`ButtonsApp.swift`'s `scenePhase` handler calls
    // `attemptAutoReconnect`, which calls `start()` unconditionally), so
    // a denied → Settings → granted → foreground round-trip now clears
    // this promptly (07d spec, DoD item 6) — this was untested before
    // that slice, since nothing called `start()` again until then.
    private(set) var isLocalNetworkDenied = false

    private var browser: NWBrowser?

    /// Starts (or restarts) the mDNS browse.
    // Cancels any existing browser first — this is now called on every
    // reconnect attempt, not just once at launch, so a caller starting it
    // twice must not leak the previous `NWBrowser`.
    func start() {
        stop()
        isLocalNetworkDenied = false
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        // .bonjour(type:domain:) never resolves the TXT record — metadata
        // stays .none, so device_id matching below always fails silently.
        // .bonjourWithTXTRecord is the descriptor that actually populates
        // result.metadata with .bonjour(txt).
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_buttons._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let devices = results.compactMap(Self.discoveredDesktop(from:))
            DispatchQueue.main.async {
                self?.discovered = devices
            }
        }
        // -65570 is DNS-SD's PolicyDenied — Local Network access revoked
        // for this app. `.waiting` alone isn't permission-exclusive (no
        // Wi-Fi hits it too), so gate on the specific code. See slice 07
        // spec, § Implementation Notes, "Local Network (mDNS/`NWBrowser`),"
        // amended 2026-09-13.
        browser.stateUpdateHandler = { [weak self] state in
            guard case .waiting(let error) = state, error.errorCode == -65570 else { return }
            DispatchQueue.main.async {
                self?.isLocalNetworkDenied = true
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
    // `device_id` is stable for the desktop's lifetime, which is what
    // makes this matching scheme work at all.
    func endpoint(forDeviceId deviceId: String) -> NWEndpoint? {
        discovered.first(where: { $0.deviceId == deviceId })?.endpoint
    }

    private static func discoveredDesktop(from result: NWBrowser.Result) -> DiscoveredDesktop? {
        guard case let .bonjour(txt) = result.metadata,
            let deviceId = txt["device_id"]
        else { return nil }
        let name: String = {
            guard case let .service(serviceName, _, _, _) = result.endpoint else { return "" }
            return serviceName
        }()
        return DiscoveredDesktop(deviceId: deviceId, endpoint: result.endpoint, name: name)
    }
}
