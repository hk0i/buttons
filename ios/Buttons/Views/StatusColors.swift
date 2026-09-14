import SwiftUI

/// Icon tints for `PressFlash` (`PageGrid.swift`) — placeholder values, not
/// a real design-token palette. Flagged for replacement once a real
/// palette lands; no other UI should adopt these in the meantime. See
/// slice 08 spec, Scope → Out.
extension Color {
    /// Tint for a succeeded press's checkmark overlay.
    static let actionSuccess = Color.green

    /// Tint for a failed press's warning-triangle overlay. Red, the plain
    /// choice for a two-case success/failure indicator — real Stream Deck
    /// hardware uses yellow, but only because it has a third state (in
    /// progress) that red would collide with; revisit if this app ever
    /// grows one.
    static let actionFailure = Color.red
}
