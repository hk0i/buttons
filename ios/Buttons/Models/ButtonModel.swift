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
    var buttons: [ButtonModel]
}

// `button.ts`'s `Button`, suffixed: `Button` is a SwiftUI view, and an
// unqualified `Button` in a file that imports SwiftUI would resolve to this
// model and shadow it. It's the one model type that collides, so it's the
// one that takes a suffix. The SwiftUI cell view is `DeckButton`, no suffix.
// Both names are moot at step 6 → generated `Buttons_Button`.
struct ButtonModel: Identifiable {
    let id: String
    var label: String? // nil-vs-empty is load-bearing: the .back
    var icon: String? // fallback (⬅ / "Back") fires on nil
    var content: ButtonContent
}

enum ButtonContent {
    case actions([Action])
    case folder([ButtonModel]) // buttons[0] is always .back
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
