import SwiftUI

@main
struct ButtonsApp: App {
    private let connection: DesktopConnection
    private let discovery = DesktopDiscovery()
    private let session: PairingSession

    init() {
        let connection = DesktopConnection()
        self.connection = connection
        session = PairingSession(connection: connection)
    }

    var body: some Scene {
        WindowGroup {
            RootView(connection: connection, discovery: discovery, session: session)
        }
    }
}

/// Launch sequence (Files to Touch #17): Keychain check → reconnect
/// attempt → `PairingView` fallback → `ContentView` once paired.
private struct RootView: View {
    let connection: DesktopConnection
    let discovery: DesktopDiscovery
    let session: PairingSession

    @State private var hasAttemptedReconnect = false

    var body: some View {
        Group {
            if connection.isConnected {
                // TODO(slice 07, Files to Touch #19): bind real
                // `connection.configSync` once ContentView/PageGrid/
                // ButtonGrid/DeckButton accept `Buttons_Config` instead of
                // `MockConfig` — not done yet, so this still renders mock
                // data even once actually paired.
                ContentView()
            } else {
                PairingView(session: session)
            }
        }
        .onAppear(perform: attemptReconnectIfPaired)
    }

    /// Keychain has a stored pair → mDNS browse, match by `device_id`,
    /// connect — no QR, no camera permission prompt. Falls through to
    /// `PairingView`'s QR-rescan path (the only recovery, Scope → Out
    /// item 7) if mDNS never finds that `device_id`.
    private func attemptReconnectIfPaired() {
        guard !hasAttemptedReconnect, let stored = PairingStore.load() else { return }
        hasAttemptedReconnect = true
        discovery.start()

        Task {
            // ~5s of polling at 250ms — generous for LAN mDNS, not a
            // network round trip to wait indefinitely on.
            for _ in 0..<20 {
                if let endpoint = discovery.endpoint(forDeviceId: stored.deviceId) {
                    session.reconnect(stored: stored, endpoint: endpoint)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            // Not found within the window — PairingView is already
            // showing (connection.isConnected is still false), ready for
            // a rescan.
        }
    }
}
