import SwiftUI

/// App root: a horizontally paged container over the active Profile's Pages
/// (mock data — `MockConfig`, no networking/pairing this slice).
struct ContentView: View {
    private let profile = MockConfig.config.profiles[0]

    @State private var currentPageId: String
    @State private var isFolderOpen = false

    init() {
        _currentPageId = State(initialValue: MockConfig.config.profiles[0].pages.first?.id ?? "")
    }

    /// Swiping between Pages is locked while any Page's folder is open, per
    /// the spec's Navigation diagram. Feeding `TabView` only the current
    /// Page — rather than gesture suppression — is the fix: a SwiftUI
    /// `.gesture`/`.highPriorityGesture` cannot reliably out-prioritize
    /// `TabView(.page)`'s own internal (UIKit) swipe recognizer, so a short
    /// swipe still paged through even at `minimumDistance: 20`. With one
    /// element, the pager has nowhere else to go — no gesture race at all.
    private var visiblePages: [Page] {
        guard isFolderOpen,
              let current = profile.pages.first(where: { $0.id == currentPageId })
        else {
            return profile.pages
        }
        return [current]
    }

    var body: some View {
        TabView(selection: $currentPageId) {
            ForEach(visiblePages) { page in
                PageGrid(page: page, isFolderOpen: $isFolderOpen)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page)
        // Default page-indicator dots are unselected-gray on a transparent
        // background — invisible against this screen's white ground.
        // `.always` forces the system's translucent backdrop behind them.
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}

#Preview {
    ContentView()
}
