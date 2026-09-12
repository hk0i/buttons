import SwiftUI

/// A `Buttons_Page` has no `Identifiable` conformance from protobuf codegen
/// on its own — its `id: String` already satisfies the requirement, so
/// this is a declaration, not new logic.
extension Buttons_Page: Identifiable {}

/// App root once paired: a horizontally paged container over the active
/// Profile's Pages. Takes real data (`Buttons_Profile`, from `ConfigSync`)
/// as of slice 07 — no more `MockConfig`/`ButtonModel`.
struct DeckView: View {
    let profile: Buttons_Profile

    @State private var currentPageId: String
    @State private var isFolderOpen = false

    init(profile: Buttons_Profile) {
        self.profile = profile
        _currentPageId = State(initialValue: profile.pages.first?.id ?? "")
    }

    /// Swiping between Pages is locked while any Page's folder is open, per
    /// the spec's Navigation diagram. Feeding `TabView` only the current
    /// Page — rather than gesture suppression — is the fix: a SwiftUI
    /// `.gesture`/`.highPriorityGesture` cannot reliably out-prioritize
    /// `TabView(.page)`'s own internal (UIKit) swipe recognizer, so a short
    /// swipe still paged through even at `minimumDistance: 20`. With one
    /// element, the pager has nowhere else to go — no gesture race at all.
    private var visiblePages: [Buttons_Page] {
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
    DeckView(profile: PreviewFixtures.config.profiles[0])
}
