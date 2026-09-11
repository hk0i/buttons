import SwiftUI

/// One Page's folder-navigation stack: renders `ButtonGrid` for whichever
/// level is currently drilled into (the Page's own buttons, or a nested
/// folder's), and dispatches taps on `ButtonContent` — `.folder` pushes,
/// `.back` pops, `.actions` no-ops (execution is step 8; there's no desktop
/// to run it on yet). Navigation state is view-local, not persisted.
struct PageGrid: View {
    let page: Page

    @State private var folderStack: [ButtonModel] = []

    /// True while any folder is open — the containing Page pager (step 5)
    /// uses this to disable swipe-between-Pages, per the Navigation
    /// diagram in the spec.
    var isFolderOpen: Bool {
        !folderStack.isEmpty
    }

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
    }
}

#Preview {
    PageGrid(page: Page(
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
    ))
}
