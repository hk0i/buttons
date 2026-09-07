import Foundation
import Network

/// Resolves a discovered Bonjour endpoint to a concrete host:port, then
/// connects over WebSocket via URLSessionWebSocketTask (matching the real
/// EDD design's transport choice).
///
/// Resolution uses the classic `NetService` API rather than NWConnection:
/// on this OS/runtime, an NWConnection made `to:` a Bonjour `.service`
/// endpoint never surfaces a concrete `.hostPort` via `currentPath`/
/// `pathUpdateHandler` — `remoteEndpoint` just echoes the unresolved service
/// value. `NetService.resolve` exists specifically to hand back real socket
/// addresses, so it's the reliable path here.
final class DesktopConnection: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var receivedPing: Ping?

    private var netService: NetService?
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    func connect(toBonjourEndpoint endpoint: NWEndpoint) {
        guard case let .service(name, type, domain, _) = endpoint else {
            print("DesktopConnection: endpoint is not a Bonjour service: \(endpoint)")
            return
        }
        let fullType = type.hasSuffix(".") ? type : "\(type)."
        let service = NetService(domain: domain, type: fullType, name: name)
        service.delegate = self
        netService = service
        service.resolve(withTimeout: 5)
    }

    private func connectWebSocket(to url: URL) {
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        isConnected = true
        receiveLoop()
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handle(message)
                self?.receiveLoop()
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case let .data(data) = message else {
            print("Ignoring non-binary WebSocket message: \(message)")
            return
        }
        do {
            let ping = try Ping(serializedBytes: data)
            print("Decoded Ping: \(ping)")
            DispatchQueue.main.async {
                self.receivedPing = ping
            }
        } catch {
            print("Failed to decode Ping: \(error)")
        }
    }

    func disconnect() {
        netService?.stop()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }

    /// Parses a `sockaddr`/`sockaddr_in`/`sockaddr_in6` blob (as handed back
    /// by `NetService.addresses`) into a host string and port.
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
        // Prefer IPv4, matching the desktop's own IPv4 "ip:port" pairing/QR payload.
        guard let resolved = parsed.first(where: { $0.isIPv4 }) ?? parsed.first else {
            print("DesktopConnection: resolved service has no usable addresses")
            return
        }
        let url = URL(string: "ws://\(resolved.host):\(resolved.port)")!
        print("Resolved desktop to \(url) — connecting WebSocket")
        connectWebSocket(to: url)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("DesktopConnection: failed to resolve service: \(errorDict)")
    }
}
