import Network
import Foundation

/// Browses for the desktop POC's mDNS service. No manual IP entry.
final class DesktopDiscovery: ObservableObject {
    @Published var discoveredEndpoint: NWEndpoint?

    private var browser: NWBrowser?

    func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_buttonspoc._tcp", domain: nil), using: parameters)
        browser.stateUpdateHandler = { state in
            print("DesktopDiscovery browser state: \(state)")
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            print("DesktopDiscovery found endpoint: \(first.endpoint)")
            DispatchQueue.main.async {
                self?.discoveredEndpoint = first.endpoint
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
