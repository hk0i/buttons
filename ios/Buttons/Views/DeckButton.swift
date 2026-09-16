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

    /// Resolves the state to render for a `.switchContent` button; `nil`
    /// for any other content, same as the existing `isBack`/glyph
    /// fallback chain below. See slice 09 spec, § Mobile-side signatures.
    func currentSwitchState(isActive: Bool) -> Buttons_SwitchState? {
        guard case .switchContent(let content) = self.content else { return nil }
        return isActive ? content.on : content.off
    }
}

/// Same presence footgun as `Buttons_Button` above — `SwitchState.label`/
/// `.icon` are proto3 `optional` too.
extension Buttons_SwitchState {
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
    /// Transient press-result icon overlay — `nil` shows nothing extra.
    /// Defaults `nil` so the existing `#Preview` below still compiles
    /// unchanged. See slice 08 spec, § Interface / Data Contract.
    var pressFlash: PressFlash? = nil
    /// Whether `button` (if it's a `.switchContent`) is currently showing
    /// its `on` state. Meaningless for any other content — defaults
    /// `false` so the existing `#Preview` below still compiles unchanged.
    /// Plain `Bool`, not `Connection` — stays pure/preview-friendly. See
    /// slice 09 spec, § Mobile-side Note 3.
    var isActive: Bool = false

    private var isBack: Bool {
        if case .back? = button.content {
            return true
        }
        return false
    }

    private var switchState: Buttons_SwitchState? {
        button.currentSwitchState(isActive: isActive)
    }

    private var glyph: String? {
        switchState?.iconOrNil ?? button.iconOrNil ?? (isBack ? "⬅️" : nil)
    }

    private var caption: String? {
        switchState?.labelOrNil ?? button.labelOrNil ?? (isBack ? "Back" : nil)
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
        // Icon overlay, not a background-color flash — deliberately, to
        // leave the background channel free for a future persistent
        // "active" indicator (state_push, step 9). See slice 08 spec,
        // § Implementation Notes.
        .overlay(alignment: .topTrailing) {
            switch pressFlash {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.actionSuccess)
                    .padding(4)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.actionFailure)
                    .padding(4)
            case nil:
                EmptyView()
            }
        }
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
