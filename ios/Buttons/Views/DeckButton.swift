import SwiftUI

/// One cell in the deck grid: a rounded tile showing the button's icon glyph
/// over its label. Pure presentation — the grid owns tap handling (wrapping
/// the cell in a `Button` styled with `DeckButtonStyle`) and dispatches on
/// `content`. A `.back` button with no icon/label of its own renders the
/// ⬅️ / "Back" fallback, matching desktop's `DeckButton.svelte`.
struct DeckButton: View {
    let button: Buttons_Button

    private var isBack: Bool {
        if case .back? = button.content {
            return true
        }
        return false
    }

    private var glyph: String? {
        button.hasIcon ? button.icon : (isBack ? "⬅️" : nil)
    }

    private var caption: String? {
        button.hasLabel ? button.label : (isBack ? "Back" : nil)
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
    }
}

/// Cell interaction feedback: dims the cell while the press is down. Kept
/// with the cell view since it owns that look; applied by whatever wraps a
/// `DeckButton` in a `Button` (the grid).
struct DeckButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    HStack {
        Button {} label: {
            DeckButton(button: .action("p1", "Go Live", "🔴"))
        }
        Button {} label: {
            DeckButton(button: .back("p2"))
        }
    }
    .buttonStyle(DeckButtonStyle())
    .frame(height: 96)
    .padding()
}
