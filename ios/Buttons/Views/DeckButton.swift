import SwiftUI

/// One cell in the deck grid: a rounded tile showing the button's icon glyph
/// over its label. Pure presentation — the grid owns tap handling and
/// dispatches on `content`. A `.back` button with no icon/label of its own
/// renders the ⬅ / "Back" fallback, matching desktop's `DeckButton.svelte`.
struct DeckButton: View {
    let button: ButtonModel
    var isPressed = false

    private var isBack: Bool {
        if case .back = button.content {
            return true
        }
        return false
    }

    private var glyph: String? {
        button.icon ?? (isBack ? "⬅" : nil)
    }

    private var caption: String? {
        button.label ?? (isBack ? "Back" : nil)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let glyph {
                Text(glyph)
                    .font(.system(size: 34))
            }
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isPressed ? 0.6 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}

#Preview {
    HStack {
        DeckButton(button: ButtonModel(
            id: "p1",
            label: "Go Live",
            icon: "🔴",
            content: .actions([]),
        ))
        DeckButton(button: ButtonModel(
            id: "p2",
            label: nil,
            icon: nil,
            content: .back,
        ), isPressed: true)
    }
    .frame(height: 96)
    .padding()
}
