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
            if let activeProfile {
                DeckView(profile: activeProfile)
            } else if connection.isConnected {
                // Paired, but `ConfigSync` hasn't arrived yet — a brief
                // gap between `PairResponse` and the next message, not a
                // failure state.
                ProgressView("Loading…")
            } else {
                PairingView(session: session)
            }
        }
        .onAppear(perform: attemptReconnectIfPaired)
    }

    private var activeProfile: Buttons_Profile? {
        guard let config = connection.configSync else { return nil }
        return config.profiles.first(where: { $0.id == config.activeProfileID }) ?? config.profiles.first
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
