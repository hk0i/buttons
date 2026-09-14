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

/// Launch sequence: Keychain check → reconnect attempt → `PairingView`
/// fallback → `ContentView` once paired.
private struct RootView: View {
    let connection: DesktopConnection
    let discovery: DesktopDiscovery
    let session: PairingSession

    @State private var hasAttemptedReconnect = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded = false

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
                PairingView(session: session, discovery: discovery)
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
                Task { await session.attemptAutoReconnect(discovery: discovery) }
            }
        }
        // `didBecomeActiveNotification` can't distinguish "returned from
        // background" from a transient interruption (Control Center, a
        // dismissed banner) — both fire it identically. `scenePhase`
        // exposes `.background` as a distinguishable case, but a bare
        // `.background → .active` match on `(old, new)` isn't reliable
        // alone (a Control Center pull produces `.active → .inactive →
        // .active`, and iOS may route the real background return through
        // `.inactive` too) — the latch is the mechanism, not a fallback.
        // See 07d spec, § Implementation Notes, for the on-device check
        // this still needs.
        .onChange(of: scenePhase) { old, new in
            if new == .background { wasBackgrounded = true }
            guard new == .active, wasBackgrounded else { return }
            wasBackgrounded = false
            Task {
                if !(await connection.isConnectionAlive()) {
                    await session.attemptAutoReconnect(discovery: discovery)
                }
            }
        }
    }

    // `configSync` is never cleared once set (Connection.swift) — checking
    // `isConnected` too is what makes a dropped connection actually fall
    // back to `PairingView` instead of showing stale `DeckView` forever.
    private var activeProfile: Buttons_Profile? {
        guard connection.isConnected, let config = connection.configSync else { return nil }
        return config.profiles.first(where: { $0.id == config.activeProfileID })
            ?? config.profiles.first
    }

    /// Starts `PairingSession`'s silent mDNS reconnect, once per launch.
    private func attemptReconnectIfPaired() {
        guard !hasAttemptedReconnect else { return }
        hasAttemptedReconnect = true
        Task { await session.attemptAutoReconnect(discovery: discovery) }
    }
}
