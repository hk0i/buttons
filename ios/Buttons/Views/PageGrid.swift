import SwiftUI

/// One Page's folder-navigation stack: renders `ButtonGrid` for whichever
/// level is currently drilled into (the Page's own buttons, or a nested
/// folder's), and dispatches taps on `ButtonContent` — `.folder` pushes,
/// `.back` pops, `.actions` no-ops (execution is step 8; there's no desktop
/// to run it on yet). Navigation state (`folderStack`) is view-local, not
/// persisted — only whether it's *open* is shared upward, via `isFolderOpen`,
/// since the containing Page pager (step 5) needs that to disable
/// swipe-between-Pages per the spec's Navigation diagram. A plain computed
/// property can't do that: SwiftUI parents don't hold child view instances
/// to query, so this is a `@Binding` the parent owns and this view writes.
struct PageGrid: View {
    let page: Page
    @Binding var isFolderOpen: Bool

    @State private var folderStack: [ButtonModel] = []

    private var currentButtons: [ButtonModel] {
        guard let openFolder = folderStack.last,
              case let .folder(contents) = openFolder.content
        else {
            return page.buttons
        }
        return contents
    }

    var body: some View {
        ButtonGrid(buttons: currentButtons, onTap: handleTap)
    }

    private func handleTap(_ button: ButtonModel) {
        switch button.content {
        case .folder:
            folderStack.append(button)
        case .back:
            guard !folderStack.isEmpty else { return }
            folderStack.removeLast()
        case .actions:
            break // no-op this slice — see Scope
        }
        isFolderOpen = !folderStack.isEmpty
    }
}

#Preview {
    PageGridPreview()
}

/// Gives the preview a real `@State` to bind, so tapping into/out of a
/// folder in the canvas exercises the same binding step 5 will use.
private struct PageGridPreview: View {
    @State private var isFolderOpen = false

    var body: some View {
        PageGrid(
            page: Page(
                id: "preview.page",
                name: "Preview",
                buttons: [
                    ButtonModel(id: "1", label: "Go Live", icon: "🔴", content: .actions([])),
                    ButtonModel(
                        id: "2",
                        label: "Scenes",
                        icon: "🎬",
                        content: .folder([
                            ButtonModel(id: "2.back", label: nil, icon: nil, content: .back),
                            ButtonModel(id: "2.1", label: "Wide", icon: "↔️", content: .actions([])),
                        ]),
                    ),
                ],
            ),
            isFolderOpen: $isFolderOpen,
        )
    }
}
