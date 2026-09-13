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
        // A live connection can die mid-session — phone locks, iOS
        // suspends the socket, the OS eventually delivers a reset — with
        // no user action to hang a retry off of. Re-running the same
        // silent mDNS reconnect used at launch is what actually recovers
        // without requiring a force-quit.
        .onChange(of: connection.isConnected) { wasConnected, isConnected in
            if wasConnected, !isConnected {
                session.attemptAutoReconnect(discovery: discovery)
            }
        }
    }

    // `configSync` is never cleared once set (Connection.swift) — checking
    // `isConnected` too is what makes a dropped connection actually fall
    // back to `PairingView` instead of showing stale `DeckView` forever.
    private var activeProfile: Buttons_Profile? {
        guard connection.isConnected, let config = connection.configSync else { return nil }
        return config.profiles.first(where: { $0.id == config.activeProfileID }) ?? config.profiles.first
    }

    /// Starts `PairingSession`'s silent mDNS reconnect, once per launch.
    private func attemptReconnectIfPaired() {
        guard !hasAttemptedReconnect else { return }
        hasAttemptedReconnect = true
        session.attemptAutoReconnect(discovery: discovery)
    }
}
