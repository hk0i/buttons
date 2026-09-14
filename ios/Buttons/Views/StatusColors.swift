import SwiftUI

/// Icon tints for `PressFlash` (`PageGrid.swift`) — placeholder values, not
/// a real design-token palette. Flagged for replacement once a real
/// palette lands; no other UI should adopt these in the meantime. See
/// slice 08 spec, Scope → Out.
extension Color {
    /// Tint for a succeeded press's checkmark overlay.
    static let actionSuccess = Color.green

    /// Tint for a failed press's warning-triangle overlay — yellow, not
    /// red, matching real Stream Deck hardware's own convention for this
    /// indicator.
    static let actionFailure = Color.yellow
}
