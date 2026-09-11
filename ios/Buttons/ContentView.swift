import SwiftUI

/// App root: a horizontally paged container over the active Profile's Pages
/// (mock data — `MockConfig`, no networking/pairing this slice). Swiping
/// between Pages is locked while any Page's folder is open, per the spec's
/// Navigation diagram — `isFolderOpen` is written by whichever `PageGrid`
/// is currently visible.
struct ContentView: View {
    private let profile = MockConfig.config.profiles[0]

    @State private var currentPageId: String
    @State private var isFolderOpen = false

    init() {
        _currentPageId = State(initialValue: MockConfig.config.profiles[0].pages.first?.id ?? "")
    }

    var body: some View {
        if isFolderOpen {
            // Swallow drags past a small threshold so a folder-open swipe
            // can't also page the TabView, while leaving plain taps (near-
            // zero movement) free to reach the grid's buttons underneath.
            pager.highPriorityGesture(DragGesture(minimumDistance: 20))
        } else {
            pager
        }
    }

    private var pager: some View {
        TabView(selection: $currentPageId) {
            ForEach(profile.pages) { page in
                PageGrid(page: page, isFolderOpen: $isFolderOpen)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page)
    }
}

#Preview {
    ContentView()
}
