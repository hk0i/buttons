import SwiftUI

/// One Page's folder-navigation stack: renders `ButtonGrid` for whichever
/// level is currently drilled into (the Page's own buttons, or a nested
/// folder's), and dispatches taps on `content` — `.folder` pushes,
/// `.back` pops, `.actions` no-ops (execution is step 8; there's no desktop
/// to run it on yet). Navigation state (`folderStack`) is view-local, not
/// persisted — only whether it's *open* is shared upward, via `isFolderOpen`,
/// since the containing Page pager (step 5) needs that to disable
/// swipe-between-Pages per the spec's Navigation diagram. A plain computed
/// property can't do that: SwiftUI parents don't hold child view instances
/// to query, so this is a `@Binding` the parent owns and this view writes.
struct PageGrid: View {
    let page: Buttons_Page
    @Binding var isFolderOpen: Bool

    @State private var folderStack: [Buttons_Button] = []

    private var currentButtons: [Buttons_Button] {
        guard let openFolder = folderStack.last,
              case .folder(let folderContent)? = openFolder.content
        else {
            return page.buttons
        }
        return folderContent.buttons
    }

    var body: some View {
        ButtonGrid(buttons: currentButtons, onTap: handleTap)
    }

    private func handleTap(_ button: Buttons_Button) {
        switch button.content {
        case .folder?:
            folderStack.append(button)
        case .back?:
            guard !folderStack.isEmpty else { return }
            folderStack.removeLast()
        default:
            break // .actions or unset — no-op this slice, see Scope
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
/// drill into.
private struct PageGridPreview: View {
    @State private var isFolderOpen = false

    var body: some View {
        PageGrid(
            page: PreviewFixtures.config.profiles[0].pages[0],
            isFolderOpen: $isFolderOpen
        )
    }
}
