import SwiftUI

@main
struct OpendeskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ODFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .preferredColorScheme(env.appearance.colorScheme)
                .tint(Theme.fg)
                .onOpenURL { url in env.router.handle(url: url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { env.router.handle(url: url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: env.foregrounded()
            case .background: env.backgrounded()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch env.session.phase {
                case .launching:
                    LaunchView()
                case .signedOut:
                    AuthFlowView(flow: env.session.signInFlow)
                case let .unreachable(message):
                    UnreachableView(message: message)
                case .needsWorkspace:
                    WorkspacePickerView()
                case .ready:
                    // Nothing of one account's screens survives into another's.
                    MainTabView().id(env.session.activeAccountID)
                }
            }
            .transition(.opacity)

            if let toast = env.toasts.current {
                ToastView(toast: toast) { env.toasts.dismiss() }
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(Motion.fade, value: env.session.phase)
        .animation(Motion.snappy, value: env.toasts.current)
        .task {
            if env.session.phase == .launching { await env.session.bootstrap() }
        }
    }
}

/// While the saved session is checked: the mark, breathing, on the launch colour.
struct LaunchView: View {
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()
            ODLogoMark()
                .fill(Theme.fg)
                .frame(width: 44, height: 44)
                .scaleEffect(breathe ? 1.04 : 0.98)
                .opacity(breathe ? 1 : 0.8)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever()) { breathe = true }
        }
        .accessibilityLabel("Loading opendesk")
    }
}

/// The server didn't answer at launch: try again, or pick another server.
struct UnreachableView: View {
    @Environment(AppEnvironment.self) private var env
    let message: String
    @State private var retrying = false

    var body: some View {
        ZStack {
            Theme.chrome.ignoresSafeArea()
            VStack(spacing: 18) {
                EmptyState(symbol: "wifi.exclamationmark", title: "Can't reach \(env.session.instance.displayHost)", message: message)
                Button {
                    retrying = true
                    Task {
                        await env.session.retryLaunch()
                        retrying = false
                    }
                } label: {
                    ButtonLabel(title: "Try again", busy: retrying)
                }
                .buttonStyle(InkButtonStyle())
                .padding(.horizontal, 32)
                if let other = env.session.accounts.first(where: { $0.id != env.session.activeAccountID }) {
                    Button("Use \(other.email) instead") {
                        env.switchAccount(to: other.id)
                    }
                    .font(ODFont.sans(14, weight: .medium))
                    .foregroundStyle(Theme.fg2)
                }
                Button(env.session.accounts.count > 1 ? "Sign out of this account" : "Sign out of this server") {
                    Task { await env.session.signOut() }
                }
                .font(ODFont.sans(14, weight: .medium))
                .foregroundStyle(Theme.fg3)
            }
        }
    }
}
