import SwiftUI

/// The list column's width for a window `width` points wide, and whether it has room for two.
enum AppColumns {
    /// A regular width at least this wide shows a tab's list beside what it opened.
    static let minWidth: CGFloat = 640

    static func on(width: CGFloat, sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular && width >= minWidth
    }

    static func listWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.4, 300), 400)
    }
}

extension EnvironmentValues {
    /// True inside the column beside a list (`AdaptiveStack`): screens there leave the tab bar
    /// under the list alone.
    @Entry var inDetailColumn = false
}

/// A tab's navigation. Compact, it is one stack with the list at its root. In `Router.columns`
/// (a wide window, such as iPhone Duo open) the list stays on the leading side and the stack runs
/// beside it, starting from `placeholder` until a row opens something (`Router.pick`).
struct AdaptiveStack<Route: Hashable, Root: View, Destination: View, Placeholder: View>: View {
    @Binding var path: [Route]
    @ViewBuilder var root: () -> Root
    @ViewBuilder var destination: (Route) -> Destination
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if env.router.columns {
            HStack(spacing: 0) {
                NavigationStack { root() }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: ODTabBar.height) }
                    .frame(width: env.router.listWidth)
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1)
                    .ignoresSafeArea()
                NavigationStack(path: $path) {
                    placeholder()
                        .navigationDestination(for: Route.self) { destination($0) }
                }
                .environment(\.inDetailColumn, true)
            }
            .background(Theme.chrome.ignoresSafeArea())
        } else {
            NavigationStack(path: $path) {
                root()
                    .navigationDestination(for: Route.self) { destination($0) }
            }
        }
    }
}

/// The detail column before a row opens anything: what to pick, on the app's canvas.
struct ColumnPlaceholder: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        EmptyState(symbol: symbol, title: title, message: message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.chrome.ignoresSafeArea())
            .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
