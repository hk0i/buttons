import SwiftUI

@main
struct ButtonsApp: App {
    private let connection: DesktopConnection
    private let session: PairingSession

    init() {
        let connection = DesktopConnection()
        self.connection = connection
        session = PairingSession(connection: connection, discovery: DesktopDiscovery(), pairingStore: PairingStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView(connection: connection, session: session)
        }
    }
}

/// Launch sequence: Keychain check → reconnect attempt → `PairingView`
/// fallback → `ContentView` once paired.
private struct RootView: View {
    let connection: DesktopConnection
    let session: PairingSession

    @State private var hasAttemptedReconnect = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded = false

    var body: some View {
        Group {
            if let activeProfile {
                DeckView(profile: activeProfile, connection: connection)
            } else if connection.isConnected {
                // Paired, but `ConfigSync` hasn't arrived yet — a brief
                // gap between `PairResponse` and the next message, not a
                // failure state.
                ProgressView("Loading…")
            } else {
                PairingView(session: session)
            }
        }
        // safeAreaInset, not overlay — reserves real layout space above
        // DeckView's grid instead of stacking on top of it, so the top
        // row's buttons stay tappable underneath. Gated on isConnected —
        // zero height over PairingView, where this has nothing to show.
        .safeAreaInset(edge: .top) {
            if connection.isConnected {
                HStack {
                    Spacer()
                    if let config = connection.configSync, config.profiles.count > 1 {
                        ProfileSwitcherMenu(config: config, connection: connection)
                    }
                    Button("Switch Device", action: connection.disconnectToSwitchDevices)
                        .padding()
                }
            }
        }
        .onAppear(perform: attemptReconnectIfPaired)
        // A live connection can die mid-session — phone locks, iOS
        // suspends the socket, the OS eventually delivers a reset — with
        // no user action to hang a retry off of. Re-running the same
        // silent mDNS reconnect used at launch is what actually recovers
        // without requiring a force-quit. Skipped when the drop was the
        // user tapping "Switch Device" — that's not a failure to recover.
        .onChange(of: connection.isConnected) { wasConnected, isConnected in
            guard wasConnected, !isConnected else { return }
            if connection.wasDisconnectedIntentionally {
                connection.acknowledgeIntentionalDisconnect()
                return
            }
            Task { await session.attemptAutoReconnect() }
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
                    await session.attemptAutoReconnect()
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
        Task { await session.attemptAutoReconnect() }
    }
}

/// Manual Profile switching, mobile-initiated — slice 10. Round-trip, not
/// optimistic: the tap only requests; `activeProfile` updates once the
/// next `config_sync` lands. See slice 10 spec, Scope → Out #3.
private struct ProfileSwitcherMenu: View {
    let config: Buttons_Config
    let connection: DesktopConnection

    private var activeProfileName: String {
        config.profiles.first(where: { $0.id == config.activeProfileID })?.name
            ?? config.profiles.first?.name ?? ""
    }

    var body: some View {
        Menu {
            ForEach(config.profiles, id: \.id) { profile in
                Button {
                    connection.requestProfileSwitch(to: profile.id)
                } label: {
                    if profile.id == config.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        } label: {
            // Name-as-trigger — just discoverability for this slice's own
            // feature. Real top-bar chrome (centering, consistent header
            // styling) waits for the 11a polish gate.
            Label(activeProfileName, systemImage: "chevron.up.chevron.down")
                .labelStyle(.titleAndIcon)
                .padding()
        }
    }
}
