import SwiftUI

/// `optional` scalar fields in proto3 don't map to Swift `Optional` — see
/// the EDD's Mobile subsection for why (cross-language codegen
/// consistency + proto3's own presence history). Reading `.icon`/`.label`
/// directly is a silent footgun: absent reads back as `""`, not nil, so a
/// forgotten `hasIcon`/`hasLabel` check doesn't crash, it just renders
/// wrong (an empty glyph instead of the `.back` fallback). These give the
/// safe form a name to reach for instead of re-deriving the ternary at
/// every call site — named after the existing `String.nilIfEmpty`-style
/// convention, not invented here.
extension Buttons_Button {
    var iconOrNil: String? { hasIcon ? icon : nil }
    var labelOrNil: String? { hasLabel ? label : nil }
}

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
        button.iconOrNil ?? (isBack ? "⬅️" : nil)
    }

    private var caption: String? {
        button.labelOrNil ?? (isBack ? "Back" : nil)
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
        Button {
        } label: {
            DeckButton(button: .action("p1", "Go Live", "🔴"))
        }
        Button {
        } label: {
            DeckButton(button: .back("p2"))
        }
    }
    .buttonStyle(DeckButtonStyle())
    .frame(height: 96)
    .padding()
}
