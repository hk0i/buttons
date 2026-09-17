import Foundation

/// Mirrors Rust's `pairing::PROTOCOL_VERSION` (`desktop/src-tauri/src/pairing.rs`).
/// Bump both by hand together.
private let currentProtocolVersion = "1"

/// Stamps `protocol_version` on every outgoing `Envelope` in one place.
private extension Buttons_Envelope {
    static func make(_ configure: (inout Buttons_Envelope) -> Void) -> Buttons_Envelope {
        .with { envelope in
            envelope.protocolVersion = currentProtocolVersion
            configure(&envelope)
        }
    }
}

/// One factory per message mobile sends — replaces var-then-assign
/// construction at each call site in `Connection.swift`.
extension Buttons_Envelope {
    static func pairRequest(token: String) -> Buttons_Envelope {
        .make { $0.message = .pairRequest(.with { $0.token = token }) }
    }

    static func buttonPress(_ buttonId: String) -> Buttons_Envelope {
        .make { $0.message = .buttonPress(.with { $0.buttonID = buttonId }) }
    }
}
