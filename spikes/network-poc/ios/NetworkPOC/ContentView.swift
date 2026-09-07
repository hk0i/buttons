import SwiftUI

struct ContentView: View {
    @StateObject private var discovery = DesktopDiscovery()
    @StateObject private var connection = DesktopConnection()

    var body: some View {
        VStack(spacing: 16) {
            if let ping = connection.receivedPing {
                Text(ping.text)
            } else if connection.isConnected {
                Text("Connected — waiting for message…")
            } else if discovery.discoveredEndpoint != nil {
                Text("Discovered — connecting…")
            } else {
                Text("Searching for desktop…")
            }

            Button("Reply") {
                // Wired up in the next step.
            }
            .disabled(connection.receivedPing == nil)
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
