import SwiftUI

/// A `Buttons_Button` has no `Identifiable` conformance from protobuf
/// codegen on its own — its `id: String` already satisfies the
/// requirement, so this is a declaration, not new logic.
extension Buttons_Button: Identifiable {}

/// A scrollable grid of `DeckButton` cells for one navigation context's
/// buttons (a Page's top level, or a folder's contents). Fixed column
/// count — 4 in portrait, 8 in landscape — mirroring the desktop preview
/// (slice 4 density note); mobile does not invent its own density rules.
/// Tapping a cell calls `onTap` with its model; the caller dispatches on
/// `content` (run actions / enter folder / go back).
struct ButtonGrid: View {
    let buttons: [Buttons_Button]
    var onTap: (Buttons_Button) -> Void
    /// `PageGrid`'s pending press-result flash, if any — passed through
    /// (not owned here) since `DeckButton` is built in this view's own
    /// `ForEach`. See slice 08 spec, § Interface / Data Contract.
    var pressFlash: (buttonId: String, flash: PressFlash)? = nil
    /// `Connection.isActiveByButtonId`, passed as a plain dict (not
    /// `Connection` itself) — same pass-through shape as `pressFlash`.
    /// Per-button resolution (`?? button.isActive`) happens in this
    /// view's own `ForEach` below. See slice 09 spec, § Mobile-side Note 3.
    var isActiveByButtonId: [String: Bool] = [:]

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // .compact vertical size class == landscape on every iPhone.
    private var columnCount: Int {
        verticalSizeClass == .compact ? 8 : 4
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(buttons) { button in
                    Button {
                        onTap(button)
                    } label: {
                        DeckButton(
                            button: button,
                            pressFlash: pressFlash?.buttonId == button.id ? pressFlash?.flash : nil,
                            isActive: isActiveByButtonId[button.id] ?? button.isActive
                        )
                    }
                    .buttonStyle(DeckButtonStyle())
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(8)
        }
    }
}

#Preview {
    ButtonGrid(
        buttons: PreviewFixtures.config.profiles[0].pages[0].buttons,
        onTap: { print("tapped \($0.id)") }
    )
}
