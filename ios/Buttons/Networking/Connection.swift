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

    private var netService: NetService?
    private var webSocketTask: URLSessionWebSocketTask?
    private var pendingToken: String?
    private let session = URLSession(configuration: .default)

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

    func disconnect() {
        pairTimeout?.cancel()
        pairTimeout = nil
        netService?.stop()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }

    /// Fails the in-flight pairing attempt if nothing has resolved it within `seconds`.
    ///
    /// - Parameter seconds: How long to wait before giving up. Defaults to 10.
    // A blocked Local Network permission doesn't fail the socket open —
    // it just delivers nothing (Implementation Notes #10.2: no pre-check
    // API, denial makes traffic vanish silently) — so this is the only
    // thing that ends a hung attempt. A real success/failure always
    // cancels this first, so it can never override one.
    private func scheduleTimeout(after seconds: TimeInterval = 10) {
        pairTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let message = "Couldn't reach Buttons desktop — check it's on the same network, and that Local Network access is allowed for this app in Settings"
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

    private func send(_ envelope: Buttons_Envelope) {
        do {
            let json = try envelope.jsonString()
            webSocketTask?.send(.string(json)) { error in
                if let error {
                    print("DesktopConnection: failed to send Envelope: \(error)")
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
                    let message = error.localizedDescription
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
                let message = response.hasError
                    ? response.error
                    : (response.ok ? "server reported success with no auth token" : "pairing failed")
                pairError = message
                pairCompletion?(.failure(message))
            }
            pairCompletion = nil
        case .configSync(let sync):
            configSync = sync.config
        case .pairRequest, .none:
            break // desktop never sends these to mobile
        }
    }

    /// Parses a `sockaddr`/`sockaddr_in`/`sockaddr_in6` blob (as handed
    /// back by `NetService.addresses`) into a host string and port.
    private static func parseSocketAddress(_ data: Data) -> (host: String, port: UInt16, isIPv4: Bool)? {
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
