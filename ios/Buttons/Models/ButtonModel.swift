// Domain-shape mirror of desktop/src/lib/types/button.ts (slice 05).
//
// These types are scaffolding, not load-bearing: step 6 translates this
// validated shape into the .proto schema, and swift-protobuf's generated
// types replace this file outright at step 6/7. No SwiftUI, no Codable —
// see docs/slices/05. Mobile Grid UI Static.spec.md § Type lifecycle.

struct Config {
    var profiles: [Profile]
    var activeProfileId: String
}

struct Profile: Identifiable {
    let id: String
    var name: String
    var pages: [Page]
}

struct Page: Identifiable {
    let id: String
    var name: String?
    var buttons: [DeckButtonModel]
}

// Named DeckButtonModel, not Button: `Button` is a SwiftUI view type, and in
// a file that imports SwiftUI the unqualified name would resolve to this
// model and shadow it. This is the one model type that collides, so it's the
// one that carries the disambiguating suffix. The SwiftUI view that renders a
// cell is `DeckButton` (no suffix). Both go away at step 6 → `Buttons_Button`.
struct DeckButtonModel: Identifiable {
    let id: String
    var label: String? // nil-vs-empty is load-bearing: the .back
    var icon: String? // fallback (⬅ / "Back") fires on nil
    var content: ButtonContent
}

enum ButtonContent {
    case actions([Action])
    case folder([DeckButtonModel]) // buttons[0] is always .back
    case back // no payload; pops one nav level
}

enum Action {
    case launchApp(path: String)
    case hotkey(keys: [String])
    case mediaKey(key: MediaKeyKind)
}

enum MediaKeyKind {
    case playPause
    case mute
    case nextTrack
    case previousTrack
}
