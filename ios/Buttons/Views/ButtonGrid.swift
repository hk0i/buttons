import SwiftUI

/// A scrollable grid of `DeckButton` cells for one navigation context's
/// buttons (a Page's top level, or a folder's contents). Fixed column
/// count — 4 in portrait, 8 in landscape — mirroring the desktop preview
/// (slice 4 density note); mobile does not invent its own density rules.
/// Tapping a cell calls `onTap` with its model; the caller dispatches on
/// `content` (run actions / enter folder / go back).
struct ButtonGrid: View {
    let buttons: [ButtonModel]
    var onTap: (ButtonModel) -> Void

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
                        DeckButton(button: button)
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
        buttons: [
            ButtonModel(id: "1", label: "Go Live", icon: "🔴", content: .actions([])),
            ButtonModel(id: "2", label: "Scenes", icon: "🎬", content: .folder([])),
            ButtonModel(id: "3", label: nil, icon: nil, content: .back),
            ButtonModel(id: "4", label: "Mute", icon: "🔇", content: .actions([])),
        ],
        onTap: { print("tapped \($0.id)") },
    )
}
