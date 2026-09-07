import SwiftUI

struct ContentView: View {
    @StateObject private var discovery = DesktopDiscovery()
    @StateObject private var connection = DesktopConnection()

    var body: some View {
        VStack {
            if connection.isConnected {
                Text("Connected")
            } else if let endpoint = discovery.discoveredEndpoint {
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
            connection.disconnect()
        }
        .onChange(of: discovery.discoveredEndpoint) { _, endpoint in
            guard let endpoint, !connection.isConnected else { return }
            connection.connect(toBonjourEndpoint: endpoint)
        }
    }
}

#Preview {
    ContentView()
}
