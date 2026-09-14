import SwiftUI

/// The pressed cell's transient icon-overlay state — a checkmark or
/// x-mark shown for ~400ms after an `ActionResult` arrives, then
/// cleared. Derived lossily from `ActionResult.ok`; not haptic (that's
/// `PageGrid.pressTrigger`), not the wire message itself
/// (`Buttons_ActionResult`/`ActionResultEvent`, `Connection.swift`), and
/// not a future persistent "active" indicator (state_push, step 9) — see
/// slice 08 spec, § Interface / Data Contract, for the full naming
/// rationale.
enum PressFlash {
    case success
    case failure
}

/// One Page's folder-navigation stack: renders `ButtonGrid` for whichever
/// level is currently drilled into (the Page's own buttons, or a nested
/// folder's), and dispatches taps on `content` — `.folder` pushes,
/// `.back` pops, `.actions` sends a `ButtonPress` and fires haptic
/// feedback immediately, then flashes the result when it arrives (step 8).
/// Navigation state (`folderStack`) is view-local, not persisted — only
/// whether it's *open* is shared upward, via `isFolderOpen`, since the
/// containing Page pager (step 5) needs that to disable swipe-between-Pages
/// per the spec's Navigation diagram. A plain computed property can't do
/// that: SwiftUI parents don't hold child view instances to query, so this
/// is a `@Binding` the parent owns and this view writes.
struct PageGrid: View {
    let page: Buttons_Page
    @Binding var isFolderOpen: Bool
    let connection: DesktopConnection

    @State private var folderStack: [Buttons_Button] = []
    @State private var pressedButtonId: String?
    @State private var pressFlash: PressFlash?
    @State private var pressTrigger = false

    private var currentButtons: [Buttons_Button] {
        guard let openFolder = folderStack.last,
            case .folder(let folderContent)? = openFolder.content
        else {
            return page.buttons
        }
        return folderContent.buttons
    }

    private var currentPressFlash: (buttonId: String, flash: PressFlash)? {
        guard let pressedButtonId, let pressFlash else { return nil }
        return (pressedButtonId, pressFlash)
    }

    var body: some View {
        ButtonGrid(buttons: currentButtons, onTap: handleTap, pressFlash: currentPressFlash)
            .sensoryFeedback(.impact, trigger: pressTrigger)
            .onChange(of: connection.lastActionResult) { _, event in
                guard let event, event.result.buttonID == pressedButtonId else { return }
                pressFlash = event.result.ok ? .success : .failure
                // `error`'s string isn't surfaced in the UI this slice —
                // logged only. See slice 08 spec, § Implementation Notes.
                if !event.result.ok, event.result.hasError {
                    print("PageGrid: button \(event.result.buttonID) failed: \(event.result.error)")
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    pressedButtonId = nil
                    pressFlash = nil
                }
            }
    }

    private func handleTap(_ button: Buttons_Button) {
        switch button.content {
        case .folder?:
            folderStack.append(button)
        case .back?:
            guard !folderStack.isEmpty else { return }
            folderStack.removeLast()
        case .actions?:
            connection.pressButton(button.id)
            pressedButtonId = button.id
            pressTrigger.toggle()
        case .none:
            break
        }
        isFolderOpen = !folderStack.isEmpty
    }
}

#Preview {
    PageGridPreview()
}

/// Gives the preview a real `@State` to bind, so tapping into/out of a
/// folder in the canvas exercises the same binding step 5 will use. Reuses
/// `PreviewFixtures`' "Scenes" page — it already has a two-level folder to
/// drill into. `connection` is a bare `DesktopConnection()` (no pairing) —
/// only its `pressButton`/`lastActionResult` surface matters for the
/// preview, and both are no-ops/nil with nothing connected.
private struct PageGridPreview: View {
    @State private var isFolderOpen = false

    var body: some View {
        PageGrid(
            page: PreviewFixtures.config.profiles[0].pages[0],
            isFolderOpen: $isFolderOpen,
            connection: DesktopConnection()
        )
    }
}
