import SwiftUI

struct ContentView: View {
    @StateObject private var discovery = DesktopDiscovery()

    var body: some View {
        VStack {
            if let endpoint = discovery.discoveredEndpoint {
                Text("Discovered: \(String(describing: endpoint))")
            } else {
                Text("Searching for desktop…")
            }
        }
        .padding()
        .onAppear {
            discovery.start()
        }
        .onDisappear {
            discovery.stop()
        }
    }
}

#Preview {
    ContentView()
}
