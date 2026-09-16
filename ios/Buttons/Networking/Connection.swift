import Foundation
import Network

/// Result of a pairing attempt: the `auth_token` to persist on success, or
/// a human-readable reason on failure. Not `Result<String, String>` —
/// `String` doesn't conform to `Error`, and defining a throwaway `Error`
/// wrapper just to satisfy that is more ceremony than this needs.
enum PairResult {
    case success(String)
    case failure(String)
}

/// Wraps an incoming `ActionResult` with a `sequence` that always
/// advances, even when two consecutive results are otherwise identical
/// (same button, same outcome) — `Buttons_ActionResult` is `Equatable`,
/// and a bare `Buttons_ActionResult?` would fail to notify observers
/// (`.onChange(of:)`) on a repeat, since a value-identical result isn't
/// a change. See slice 08 spec, § Interface / Data Contract.
struct ActionResultEvent: Equatable {
    let result: Buttons_ActionResult
    let sequence: Int
}

/// One WebSocket connection to a paired desktop — sends/receives
/// `Buttons_Envelope` as JSON text frames, not the spike's binary frames
/// (wire-format decision, EDD §5.2). Adapted from
/// `spikes/network-poc/ios/NetworkPOC/DesktopConnection.swift`.
///
/// `@Observable` from the start, not extracted later — this owns a live
/// `URLSessionWebSocketTask`/`NetService` resolution, shared across the
/// pairing and main app views. See CLAUDE.md's "layer that owns a live
/// connection" rule.
@Observable
final class DesktopConnection: NSObject {
    private(set) var isConnected = false
    private(set) var configSync: Buttons_Config?
    private(set) var pairError: String?
    private(set) var lastActionResult: ActionResultEvent?

    /// button_id -> is "on" showing, for every Switch button. Rebuilt from
    /// scratch (not merged) on every configSync, flipped optimistically by
    /// `PageGrid` on tap, flipped again (not "reverted to X") on failure —
    /// see slice 09 spec, § Interface Note 1.
    private(set) var isActiveByButtonId: [String: Bool] = [:]

    private var netService: NetService?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pendingToken: String?
    private let session = URLSession(configuration: .default)
    private var actionResultSequence = 0

    /// A blocked Local Network permission doesn't fail the socket open —
    /// it just never delivers anything, so `receiveLoop()`'s `.failure`
    /// case never fires and `pairCompletion` never runs. Without this, a
    /// QR scan attempted with the permission off leaves `PairingView`
    /// stuck on "Connecting…" forever (DoD 4's gap, concretely). 10s is
    /// generous for a real LAN round trip and short enough that a blocked
    /// permission surfaces before the user assumes the app is frozen.
    private var pairTimeout: DispatchWorkItem?

    /// Fires once, exactly when a `PairResponse` arrives — success carries
    /// the `auth_token` to persist, failure the server's `error` string.
    /// `Pairing.swift` uses this (not polling `isConnected`/`pairError`) to
    /// know precisely when it's safe to write Keychain: only a resolved
    /// `PairResponse` means a real `auth_token` exists to store.
    private var pairCompletion: ((PairResult) -> Void)?

    /// True while a connection already exists, or an attempt to establish
    /// one hasn't resolved yet — the single gate both `connect(...)`
    /// overloads check before starting a second one. See slice 09b spec,
    /// § Scope → In #1.
    private var isConnectingOrConnected: Bool { isConnected || pairCompletion != nil }

    /// Reconnect path: a Bonjour endpoint already resolved by
    /// `DesktopDiscovery` (matched by stored `device_id`). Resolution goes
    /// through the classic `NetService` API, not `NWConnection` — the
    /// spike found `NWConnection` never surfaces a concrete host:port for
    /// a `.service` endpoint on this runtime; `NetService.resolve` does.
    func connect(
        toBonjourEndpoint endpoint: NWEndpoint,
        token: String,
        onPairResult: ((PairResult) -> Void)? = nil
    ) {
        // At most one socket exists at a time — a second concurrent
        // request (e.g. two reconnect triggers landing close together) is
        // dropped, not queued or superseded.
        guard !isConnectingOrConnected else { return }
        guard case let .service(name, type, domain, _) = endpoint else {
            pairError = "not a Bonjour service endpoint"
            onPairResult?(.failure("not a Bonjour service endpoint"))
            return
        }
        pendingToken = token
        pairCompletion = onPairResult
        scheduleTimeout()
        let fullType = type.hasSuffix(".") ? type : "\(type)."
        let service = NetService(domain: domain, type: fullType, name: name)
        service.delegate = self
        netService = service
        service.resolve(withTimeout: 5)
    }

    /// Fresh-pair path: host/port come straight from the scanned QR
    /// payload, not from mDNS resolution — see `wire.proto`'s Interface
    /// section for why the QR carries them directly.
    func connect(
        host: String,
        port: UInt16,
        token: String,
        onPairResult: ((PairResult) -> Void)? = nil
    ) {
        // See the other connect(...) overload's identical guard.
        guard !isConnectingOrConnected else { return }
        pendingToken = token
        pairCompletion = onPairResult
        guard let url = URL(string: "ws://\(host):\(port)") else {
            pairError = "invalid host/port in QR payload"
            onPairResult?(.failure("invalid host/port in QR payload"))
            return
        }
        scheduleTimeout()
        connectWebSocket(to: url)
    }

    /// Flips a Switch button's tracked state — a toggle, not a setter,
    /// since with exactly two states "the user tapped it" and "the press
    /// failed, undo" are the identical operation. See slice 09 spec, §
    /// Interface Note 2.
    func applyOptimisticFlip(buttonId: String) {
        isActiveByButtonId[buttonId, default: false].toggle()
    }

    func disconnect() {
        pairTimeout?.cancel()
        pairTimeout = nil
        netService?.stop()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        // Without this, a caller invoking disconnect() while an attempt is
        // still unresolved would leave pairCompletion set with nothing
        // left running to ever clear it, wedging connect(...)'s in-flight
        // guard permanently. See slice 09b spec, § Scope → In #2.
        pairCompletion = nil
        pendingToken = nil
    }

    /// Actively confirms the socket is still alive.
    ///
    /// - Returns: `true` if a ping round-trips; `false` if there's nothing
    ///   to ping, or the ping fails.
    // `isConnected` alone can be stale after the app was backgrounded —
    // iOS may suspend the task without ever delivering a receive failure.
    // No timeout here: NSURLSession.h documents `sendPingWithPongReceiveHandler:`
    // as invoking its handler with an error on a lost connection, not just
    // on a pong, so a dead socket is expected to resolve this on its own.
    // If the on-device foreground test (07d spec, DoD item 2) shows that
    // doesn't hold for an iOS-suspended socket specifically, add a timeout
    // then — see 07d spec, § Implementation Notes, for why one isn't
    // included preemptively.
    func isConnectionAlive() async -> Bool {
        guard isConnected, let task = webSocketTask else { return false }
        let isAlive = await withCheckedContinuation { continuation in
            task.sendPing { error in continuation.resume(returning: error == nil) }
        }
        if !isAlive { isConnected = false }
        return isAlive
    }

    /// Fails the in-flight pairing attempt if nothing has resolved it within `seconds`.
    ///
    /// - Parameter seconds: How long to wait before giving up. Defaults to 10.
    // A blocked Local Network permission doesn't fail the socket open —
    // it just delivers nothing (no pre-check API for this permission;
    // denial makes traffic vanish silently) — so this is the only thing
    // that ends a hung attempt. A real success/failure always cancels
    // this first, so it can never override one.
    private func scheduleTimeout(after seconds: TimeInterval = 10) {
        pairTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let message =
                "Couldn't reach Buttons desktop — check it's on the same network, and that Local Network access is allowed for this app in Settings"
            self.pairError = message
            self.pairCompletion?(.failure(message))
            self.pairCompletion = nil
            self.disconnect()
        }
        pairTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func connectWebSocket(to url: URL) {
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveLoop()
        sendPairRequest()
    }

    private func sendPairRequest() {
        guard let token = pendingToken else { return }
        var envelope = Buttons_Envelope()
        envelope.protocolVersion = "1"
        var pairRequest = Buttons_PairRequest()
        pairRequest.token = token
        envelope.message = .pairRequest(pairRequest)
        send(envelope)
    }

    /// Sends a `ButtonPress` for the tapped button's id. Fire-and-forget —
    /// the result arrives asynchronously via `lastActionResult`, matched
    /// by `button_id` on the caller's side (`PageGrid`).
    func pressButton(_ buttonId: String) {
        var envelope = Buttons_Envelope()
        envelope.protocolVersion = "1"
        var buttonPress = Buttons_ButtonPress()
        buttonPress.buttonID = buttonId
        envelope.message = .buttonPress(buttonPress)
        send(envelope)
    }

    private func send(_ envelope: Buttons_Envelope) {
        do {
            let json = try envelope.jsonString()
            webSocketTask?.send(.string(json)) { [weak self] error in
                guard let self, let error else { return }
                print("DesktopConnection: failed to send Envelope: \(error)")
                DispatchQueue.main.async {
                    // Same in-flight-attempt guard as receiveLoop()'s
                    // failure branch — whichever of the two callbacks
                    // fires first resolves pairCompletion; the other is a
                    // no-op via the guard.
                    guard self.pairCompletion != nil else { return }
                    self.pairTimeout?.cancel()
                    self.pairTimeout = nil
                    let message = Self.pairingFailureMessage(for: error)
                    self.pairError = message
                    self.pairCompletion?(.failure(message))
                    self.pairCompletion = nil
                }
            }
        } catch {
            print("DesktopConnection: failed to encode Envelope: \(error)")
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handle(message)
                self.receiveLoop()
            case .failure(let error):
                print("DesktopConnection: receive error: \(error)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    // A pairing attempt still in flight (pairCompletion
                    // non-nil) means this is a connect-time failure, not a
                    // later drop of an already-paired session — surface it
                    // now instead of waiting out the full pairTimeout.
                    guard self.pairCompletion != nil else { return }
                    self.pairTimeout?.cancel()
                    self.pairTimeout = nil
                    let message = Self.pairingFailureMessage(for: error)
                    self.pairError = message
                    self.pairCompletion?(.failure(message))
                    self.pairCompletion = nil
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case let .string(text) = message else {
            print("DesktopConnection: ignoring non-text frame: \(message)")
            return
        }
        do {
            let envelope = try Buttons_Envelope(jsonString: text)
            DispatchQueue.main.async { [weak self] in
                self?.handle(envelope)
            }
        } catch {
            print("DesktopConnection: failed to decode Envelope: \(error)")
        }
    }

    private func handle(_ envelope: Buttons_Envelope) {
        switch envelope.message {
        case .pairResponse(let response):
            pairTimeout?.cancel()
            pairTimeout = nil
            // wire.proto: auth_token is "present iff ok" — checked, not
            // trusted, same reasoning as protocol_version (Implementation
            // Notes #2). A desktop bug/protocol drift sending ok:true with
            // no auth_token must not write an empty-string token to
            // Keychain — that bricks every future reconnect with no
            // recovery short of deleting the app.
            if response.ok, response.hasAuthToken {
                isConnected = true
                pairError = nil
                pairCompletion?(.success(response.authToken))
            } else {
                isConnected = false
                let message =
                    response.hasError
                    ? response.error
                    : (response.ok
                        ? "server reported success with no auth token" : "pairing failed")
                pairError = message
                pairCompletion?(.failure(message))
            }
            pairCompletion = nil
        case .configSync(let sync):
            configSync = sync.config
            isActiveByButtonId = Self.collectSwitchStates(from: sync.config)
        case .actionResult(let result):
            actionResultSequence += 1
            lastActionResult = ActionResultEvent(result: result, sequence: actionResultSequence)
        case .statePush(let push):
            // Overwrite, not toggle — this is authoritative correction, not
            // another optimistic guess. Same precedence rule as configSync:
            // no "is my own optimistic flip newer" check. See slice 09a
            // spec, § Interface, "Mobile-side."
            for change in push.changes {
                isActiveByButtonId[change.buttonID] = change.isActive
            }
        case .pairRequest, .buttonPress, .none:
            break  // desktop never sends these to mobile
        }
    }

    /// Turns a connect-time `URLError` into copy that names the likely cause.
    ///
    /// - Parameter error: The error `receiveLoop()` got from a failed connect.
    // `NSURLErrorNotConnectedToInternet` (-1009) fires for a denied Local
    // Network permission, but also for desktop-off, wrong subnet, or
    // Wi-Fi dropping mid-handshake — `URLSession` collapses all of these
    // into one code, unlike `NWBrowser`'s `.waiting(PolicyDenied)`
    // (`Discovery.swift`'s `isLocalNetworkDenied`, the actual diagnostic
    // signal). Treated the same as -1004/-1001 here, not singled out — a
    // caller wanting the definite permission case consults
    // `isLocalNetworkDenied` directly instead. See slice 07 spec, §
    // Implementation Notes, "Local Network (mDNS/`NWBrowser`)," amended
    // 2026-09-13.
    private static func pairingFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotConnectToHost,
            NSURLErrorTimedOut:
            return
                "Couldn't reach the desktop — check that it's running, on the same network, and that Local Network access is allowed for this app in Settings."
        default:
            return error.localizedDescription
        }
    }

    /// Full rebuild of `isActiveByButtonId` from a fresh `Config` — every
    /// Switch button (at any folder depth) gets an entry, everything else
    /// is absent. Never a merge: a `MultiSwitch` later would need its own
    /// `Int`-keyed map, not a reshape of this one. See slice 09 spec, §
    /// Interface Note 1.
    private static func collectSwitchStates(from config: Buttons_Config?) -> [String: Bool] {
        guard let config else { return [:] }
        var result: [String: Bool] = [:]
        for profile in config.profiles {
            for page in profile.pages {
                collectSwitchStates(from: page.buttons, into: &result)
            }
        }
        return result
    }

    private static func collectSwitchStates(
        from buttons: [Buttons_Button], into result: inout [String: Bool]
    ) {
        for button in buttons {
            if case .switchContent? = button.content {
                result[button.id] = button.isActive
            }
            if case .folder(let folderContent)? = button.content {
                collectSwitchStates(from: folderContent.buttons, into: &result)
            }
        }
    }

    /// Parses a `sockaddr`/`sockaddr_in`/`sockaddr_in6` blob (as handed
    /// back by `NetService.addresses`) into a host string and port.
    private static func parseSocketAddress(_ data: Data) -> (
        host: String, port: UInt16, isIPv4: Bool
    )? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> (String, UInt16, Bool)? in
            let family = raw.loadUnaligned(as: sockaddr.self).sa_family
            switch Int32(family) {
            case AF_INET:
                let sin = raw.loadUnaligned(as: sockaddr_in.self)
                var addr = sin.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                return (String(cString: buffer), UInt16(bigEndian: sin.sin_port), true)
            case AF_INET6:
                let sin6 = raw.loadUnaligned(as: sockaddr_in6.self)
                var addr = sin6.sin6_addr
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                return (String(cString: buffer), UInt16(bigEndian: sin6.sin6_port), false)
            default:
                return nil
            }
        }
    }
}

extension DesktopConnection: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let parsed = (sender.addresses ?? []).compactMap(Self.parseSocketAddress)
        // Prefer IPv4, matching the desktop's own IPv4 pairing/QR payload.
        guard let resolved = parsed.first(where: { $0.isIPv4 }) ?? parsed.first else {
            let message = "resolved service has no usable addresses"
            pairTimeout?.cancel()
            pairTimeout = nil
            pairError = message
            pairCompletion?(.failure(message))
            pairCompletion = nil
            return
        }
        guard let url = URL(string: "ws://\(resolved.host):\(resolved.port)") else {
            let message = "invalid resolved address"
            pairTimeout?.cancel()
            pairTimeout = nil
            pairError = message
            pairCompletion?(.failure(message))
            pairCompletion = nil
            return
        }
        connectWebSocket(to: url)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let message = "failed to resolve desktop: \(errorDict)"
        pairTimeout?.cancel()
        pairTimeout = nil
        pairError = message
        pairCompletion?(.failure(message))
        pairCompletion = nil
    }
}
