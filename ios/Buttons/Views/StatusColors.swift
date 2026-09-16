import SwiftUI

/// Status tints — `PressFlash` icon overlays (`PageGrid.swift`) and a
/// Switch button's active-state background (`DeckButton.swift`).
/// Placeholder values, not a real design-token palette. Flagged for
/// replacement once a real palette lands; no other UI should adopt these
/// in the meantime. See slice 08 spec, Scope → Out, and slice 09a spec,
/// § Scope → In #5.
extension Color {
    /// Tint for a succeeded press's checkmark overlay.
    static let actionSuccess = Color.green

    /// Tint for a failed press's x-mark overlay. Red, the plain
    /// choice for a two-case success/failure indicator — real Stream Deck
    /// hardware uses yellow, but only because it has a third state (in
    /// progress) that red would collide with; revisit if this app ever
    /// grows one.
    static let actionFailure = Color.red

    /// Background tint for a `.switchContent` button's tile while its `on`
    /// state is showing. Same placeholder status as the two above — not a
    /// real design token yet. See slice 09a spec, § Scope → In #5.
    static let switchActive = Color.accentColor.opacity(0.3)
}
