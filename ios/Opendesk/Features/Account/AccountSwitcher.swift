import SwiftUI

/// Every account signed in on this phone, under the profile card: tap one to
/// open it, its menu to sign out of it, or add another. With one account it is
/// just the way to add a second.
struct AccountSwitcherPanel: View {
    @Environment(AppEnvironment.self) private var env
    @State private var adding: SignInFlow?
    @State private var confirm: AccountConfirm?

    private var session: SessionStore { env.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.accounts.count > 1 {
                SectionLabel("Accounts").padding(.horizontal, 4)
            }
            Panel {
                if session.accounts.count > 1 {
                    ForEach(session.accounts) { account in
                        row(account)
                        AccountDivider(tiles: false)
                    }
                }
                addRow
            }
        }
        .sheet(item: $adding) { flow in
            AuthFlowView(flow: flow) { adding = nil }
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
        #if DEBUG
        .onAppear(perform: handleDemo)
        .onChange(of: env.router.demoAction) { _, _ in handleDemo() }
        #endif
    }

    private func row(_ account: DeviceAccount) -> some View {
        let active = account.id == session.activeAccountID
        return HStack(spacing: 0) {
            Button {
                guard !active else { return }
                env.switchAccount(to: account.id)
            } label: {
                HStack(spacing: 12) {
                    Avatar(name: account.displayName, url: account.avatarURL, seed: account.userID, size: 34)
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(ODFont.sans(15, weight: active ? .semibold : .regular))
                            .foregroundStyle(Theme.fg)
                            .lineLimit(1)
                        Text(Self.detail(account))
                            .font(ODFont.footnote)
                            .foregroundStyle(Theme.fg3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.fg)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("\(account.displayName), \(Self.detail(account))")
            .accessibilityValue(active ? "Open" : "")
            .accessibilityHint(active ? "" : "Switches to this account")
            .accessibilityAddTraits(active ? .isSelected : [])

            Menu {
                if !active {
                    Button {
                        env.switchAccount(to: account.id)
                    } label: {
                        Label("Switch to this account", systemImage: "arrow.left.arrow.right")
                    }
                }
                Button(role: .destructive) {
                    confirm = .signOut(account, session: session)
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.fg3)
                    .frame(width: 44, height: 56)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More for \(account.email)")
        }
    }

    private var addRow: some View {
        Button {
            Haptics.tap()
            adding = session.makeAddFlow()
        } label: {
            AccountRow(symbol: "plus", tone: .gray, title: "Add another account", subtitle: session.accounts.count > 1 ? nil : "Stay signed in to both and switch here")
        }
        .buttonStyle(RowPressStyle())
        .disabled(session.accounts.count >= AccountKeyring.maxAccounts)
        .opacity(session.accounts.count >= AccountKeyring.maxAccounts ? 0.5 : 1)
    }

    /// The address, and the server when it isn't Cloud.
    static func detail(_ account: DeviceAccount) -> String {
        account.instance.isCloud ? account.email : "\(account.email) · \(account.instance.displayHost)"
    }

    private func handleDemo() {
        if AccountDemo.take("add-account", from: env.router) { adding = session.makeAddFlow() }
    }
}

/// The switcher on its own, from a long press on the Account tab.
struct AccountSwitcherSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(title: "Accounts", subtitle: "Every account stays signed in. Switching opens its workspace and notifications.") { dismiss() }
                AccountSwitcherPanel()
            }
            .padding(22)
        }
        .background(Theme.chrome.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
    }
}

extension AccountConfirm {
    /// Signing out of one account: what happens to its notifications, and which account opens next.
    @MainActor
    static func signOut(_ account: DeviceAccount, session: SessionStore) -> AccountConfirm {
        let others = session.accounts.filter { $0.id != account.id }
        let isOpen = account.id == session.activeAccountID
        var message = "This \(AppInfo.device) stops getting notifications for \(account.email) until you sign in again."
        if isOpen, let index = session.accounts.firstIndex(where: { $0.id == account.id }), !others.isEmpty {
            let next = others[min(index, others.count - 1)]
            message += " \(next.email) opens next."
        }
        return AccountConfirm(
            title: others.isEmpty ? "Sign out of opendesk?" : "Sign out of \(account.email)?",
            message: message,
            confirmTitle: "Sign out"
        ) {
            await session.signOut(account)
        }
    }
}
