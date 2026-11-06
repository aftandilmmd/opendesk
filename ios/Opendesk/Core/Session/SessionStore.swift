import Foundation
import Observation

/// What a sign-in step asks for next.
enum SignInOutcome: Sendable, Equatable {
    case signedIn
    case mfa(token: String)
    case link(token: String, email: String)
}

/// The accounts signed in on this phone, the open one (its person, server and
/// workspace), and moving between them.
///
/// Each account keeps its own session: a refresh token in the Keychain under its
/// own item (`DeviceAccount.tokenKey`) and one `APIClient` for the app's life, so
/// its refreshes never race. Accounts may be on different servers.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching
        case signedOut
        case unreachable(String)
        case needsWorkspace
        case ready
    }

    private(set) var phase: Phase = .launching
    /// The open account's server (the last one used while signed out).
    private(set) var instance: Instance
    private(set) var authConfig: AuthConfig?
    private(set) var user: User? {
        // Times of day follow the signed-in person's clock.
        didSet { ClockSetting.shared.format = TimeFormat(user?.timeFormat) }
    }
    private(set) var memberships: [Membership] = []
    private(set) var workspace: Membership?
    /// Every account on this phone, in the order they were added.
    private(set) var accounts: [DeviceAccount] = []
    private(set) var activeAccountID: String?
    /// The signed-out screen's sign-in.
    let signInFlow: SignInFlow

    @ObservationIgnored private(set) var api: APIClient
    @ObservationIgnored private(set) var attest: AppAttestClient
    @ObservationIgnored private var clients: [String: APIClient] = [:]
    @ObservationIgnored private var configs: [String: AuthConfig] = [:]
    @ObservationIgnored private var switching = false

    /// Set by the environment: start everything that belongs to a workspace.
    @ObservationIgnored var onReady: ((Membership) -> Void)?
    /// Set by the environment: stop everything that belongs to the open account.
    @ObservationIgnored var onLeave: (() -> Void)?
    /// Set by the environment: an account left this phone (signed out, expired or deleted).
    @ObservationIgnored var onAccountEnded: ((_ account: DeviceAccount, _ remaining: [DeviceAccount]) -> Void)?

    init() {
        let start = Self.launchInstance()
        instance = start
        api = APIClient(instance: start)
        attest = AppAttestClient(api: api)
        signInFlow = SignInFlow(instance: start, adding: false)
        signInFlow.onSignedIn = { [weak self] client, config in try await self?.signedIn(client, config: config) }
    }

    private static func launchInstance() -> Instance {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.instance }
        if let raw = AppInfo.debugValue("OPENDESK_DEBUG_SERVER") {
            if raw == "local" { return .localDev }
            if let origin = try? InstanceResolver.normalize(raw) {
                if origin == Instance.cloudAppOrigin { return .cloud }
                if let api = AppInfo.debugValue("OPENDESK_DEBUG_API").flatMap(URL.init(string:)) {
                    return Instance(appOrigin: origin, apiURL: api, gatewayURL: AppInfo.debugValue("OPENDESK_DEBUG_GATEWAY").flatMap(URL.init(string:)), selfHosted: true)
                }
                return Instance(appOrigin: origin, apiURL: origin, gatewayURL: nil, selfHosted: true)
            }
        }
        #endif
        return Preferences.instance ?? .cloud
    }

    // MARK: Roles

    var role: Role { workspace?.role ?? .viewer }
    var canWrite: Bool { role.canWrite }
    var isAdmin: Bool { role.isAdmin }
    var userRef: UserRef? { user.map { UserRef(id: $0.id, name: $0.name, email: $0.email, avatarURL: $0.avatarURL) } }

    // MARK: Launch

    func bootstrap() async {
        let saved = AccountKeyring.load()
        accounts = saved.accounts
        guard let target = accounts.first(where: { $0.id == saved.active }) ?? accounts.first else {
            // A version with one account kept its token under the server alone: it becomes the first account.
            let legacy = AccountKeyring.legacyTokenKey(for: signInFlow.instance)
            guard KeychainStore.get(legacy) != nil else {
                phase = .signedOut
                return
            }
            await open(makeClient(signInFlow.instance, tokenKey: legacy), account: nil)
            return
        }
        await open(client(for: target), account: target)
    }

    func retryLaunch() async {
        phase = .launching
        await bootstrap()
    }

    /// The open server's sign-in options (push mode, App Attest), cached per server.
    private func loadAuthConfig() async {
        let target = instance
        guard let config = try? await InstanceResolver().authConfig(for: target.apiURL) else { return }
        configs[target.storageKey] = config
        if target == instance { authConfig = config }
    }

    /// Another server's sign-in options (its push mode), cached per server.
    func authConfig(for instance: Instance) async -> AuthConfig? {
        if let config = configs[instance.storageKey] { return config }
        guard let config = try? await InstanceResolver().authConfig(for: instance.apiURL) else { return nil }
        configs[instance.storageKey] = config
        return config
    }

    // MARK: Accounts

    var activeAccount: DeviceAccount? { accounts.first { $0.id == activeAccountID } }

    /// The client for `account`: one for the app's life, so one refresh at a time rotates its token.
    func client(for account: DeviceAccount) -> APIClient {
        if let client = clients[account.id] { return client }
        let client = makeClient(account.instance, tokenKey: account.tokenKey)
        clients[account.id] = client
        return client
    }

    private func makeClient(_ instance: Instance, tokenKey: String?) -> APIClient {
        APIClient(instance: instance, tokenKey: tokenKey) { [weak self] client in
            await self?.sessionExpired(for: client)
        }
    }

    /// A sign-in for another account, starting on the open account's server.
    func makeAddFlow() -> SignInFlow {
        let flow = SignInFlow(instance: instance, config: authConfig, adding: true)
        flow.onSignedIn = { [weak self] client, config in try await self?.signedIn(client, config: config) }
        return flow
    }

    /// Opens another signed-in account: everything of the open one stops, and the next starts fresh.
    func switchAccount(to id: String) async {
        guard !switching, let account = accounts.first(where: { $0.id == id }) else { return }
        if id == activeAccountID, phase == .ready { return }
        switching = true
        defer { switching = false }
        onLeave?()
        await open(client(for: account), account: account)
    }

    /// Loads who `client` signs in as (refreshing its session first), files the account and enters its workspace.
    /// A server out of reach leaves the account chosen, on the unreachable screen, to try again.
    private func open(_ client: APIClient, account: DeviceAccount?) async {
        phase = .launching
        api = client
        instance = client.instance
        attest = AppAttestClient(api: client)
        authConfig = configs[client.instance.storageKey]
        user = nil
        memberships = []
        workspace = nil
        if let account {
            activeAccountID = account.id
            persist()
        }
        do {
            let me: Me = try await client.get("v1/me", workspace: .none)
            await adopt(client, me: me, config: nil)
        } catch let error as APIError where error.status == 401 || error.status == 403 {
            if let account {
                await remove(account, revoke: false)
            } else {
                await client.clearTokens()
                reset(endedOn: client.instance)
            }
        } catch {
            phase = .unreachable(error.userMessage)
        }
    }

    /// A sign-in finished: the new session becomes an account and opens. Signing in again to an
    /// account already here ends its earlier session, as a browser does.
    private func signedIn(_ client: APIClient, config: AuthConfig?) async throws {
        let me: Me
        do {
            me = try await client.get("v1/me", workspace: .none)
        } catch {
            await client.signOut()
            throw error
        }
        let id = DeviceAccount.id(instance: client.instance, userID: me.user.id)
        if accounts.contains(where: { $0.id == id }) {
            if let earlier = clients.removeValue(forKey: id), earlier !== client {
                if id == activeAccountID { onLeave?() }
                await earlier.signOut()
            }
        } else if accounts.count >= AccountKeyring.maxAccounts {
            await client.signOut()
            throw SignInError.tooManyAccounts
        }
        await client.setSignedOutHandler { [weak self] client in await self?.sessionExpired(for: client) }
        onLeave?()
        phase = .launching
        await adopt(client, me: me, config: config)
    }

    /// Files `client`'s account (token under its own item) without opening it.
    @discardableResult
    private func file(_ client: APIClient, me: Me) async -> DeviceAccount {
        let account = DeviceAccount(instance: client.instance, me: me)
        await client.bind(to: account.tokenKey)
        clients[account.id] = client
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        persist()
        return account
    }

    /// Makes `client`'s account the open one and enters its workspace.
    private func adopt(_ client: APIClient, me: Me, config: AuthConfig?) async {
        let account = await file(client, me: me)
        activeAccountID = account.id
        persist()
        api = client
        instance = client.instance
        attest = AppAttestClient(api: client)
        if let config { configs[instance.storageKey] = config }
        authConfig = configs[instance.storageKey]
        if authConfig == nil { Task { await loadAuthConfig() } }
        user = me.user
        memberships = me.memberships
        workspace = nil
        await client.setWorkspace(nil)
        enterWorkspace(preferred: Preferences.workspaceID(for: account) ?? Preferences.workspaceID(for: account.instance))
    }

    private func persist() {
        AccountKeyring.save(AccountKeyring.Saved(active: activeAccountID, accounts: accounts))
    }

    /// Keeps the open account's name, photo and workspaces current in the list.
    private func refreshRecord() {
        guard let user, let index = accounts.firstIndex(where: { $0.id == activeAccountID }) else { return }
        let fresh = DeviceAccount(instance: instance, me: Me(user: user, memberships: memberships))
        guard fresh != accounts[index] else { return }
        accounts[index] = fresh
        persist()
    }

    // MARK: Account and workspaces

    func loadMe() async throws {
        let me: Me = try await api.get("v1/me", workspace: .none)
        user = me.user
        memberships = me.memberships
        if let current = workspace, let fresh = me.memberships.first(where: { $0.id == current.id }) {
            workspace = fresh
        }
        refreshRecord()
    }

    /// Reloads the account after a membership event; leaves the workspace if access is gone.
    func membershipChanged() async {
        guard (try? await loadMe()) != nil else { return }
        if let workspace, !memberships.contains(where: { $0.id == workspace.id }) {
            self.workspace = nil
            enterWorkspace(preferred: nil)
        }
    }

    private func enterWorkspace(preferred: String?) {
        var preferred = AppInfo.debugValue("OPENDESK_DEBUG_WORKSPACE") ?? preferred
        #if DEBUG
        if DemoMode.isOn, preferred == nil { preferred = DemoSeed.marginID }
        #endif
        if let preferred,
           let match = memberships.first(where: { $0.id == preferred || $0.workspace.slug == preferred }) {
            select(match)
        } else if memberships.count == 1, let only = memberships.first {
            select(only)
        } else {
            workspace = nil
            phase = .needsWorkspace
        }
    }

    func select(_ membership: Membership) {
        workspace = membership
        if let account = activeAccount { Preferences.setWorkspaceID(membership.id, for: account) }
        Preferences.setWorkspaceID(membership.id, for: instance)
        let client = api
        Task {
            await client.setWorkspace(membership.id)
            // Another account opened meanwhile.
            guard client === self.api else { return }
            self.phase = .ready
            self.onReady?(membership)
        }
    }

    /// Back to the picker (switching workspaces).
    func chooseWorkspace() {
        phase = .needsWorkspace
    }

    func createWorkspace(name: String) async throws {
        struct Body: Encodable, Sendable { let name: String }
        let created: Workspace = try await api.post("v1/workspaces", body: Body(name: name), workspace: .none)
        try await loadMe()
        let membership = memberships.first(where: { $0.id == created.id }) ?? Membership(workspace: created, role: .owner)
        select(membership)
    }

    func updateName(_ name: String) async throws {
        struct Body: Encodable, Sendable { let name: String }
        let updated: User = try await api.patch("v1/me", body: Body(name: name), workspace: .none)
        user = updated
        refreshRecord()
    }

    /// The clock times are shown in, account-wide (`PATCH /v1/me {time_format}`).
    /// Shown at once; put back if the server refuses.
    func setTimeFormat(_ format: TimeFormat) async throws {
        struct Body: Encodable, Sendable { let time_format: String }
        let previous = user
        user?.timeFormat = format.rawValue
        do {
            user = try await api.patch("v1/me", body: Body(time_format: format.rawValue), workspace: .none)
        } catch {
            user = previous
            throw error
        }
    }

    func setAvailability(_ availability: Availability) async throws -> Member {
        struct Body: Encodable, Sendable { let availability: Availability }
        return try await api.patch("v1/members/me/availability", body: Body(availability: availability))
    }

    // MARK: Ending

    /// Signs out of the open account. The next account opens, or sign-in when none is left.
    func signOut() async {
        guard let account = activeAccount else {
            // Nothing filed yet: a launch that couldn't reach the server.
            onLeave?()
            await api.signOut()
            reset(endedOn: instance)
            return
        }
        await remove(account, revoke: true)
    }

    /// Signs out of one account, open or not.
    func signOut(_ account: DeviceAccount) async {
        await remove(account, revoke: true)
    }

    /// Signs out of every account on this phone.
    func signOutAll() async {
        for account in accounts where account.id != activeAccountID {
            await remove(account, revoke: true)
        }
        await signOut()
    }

    #if DEBUG
    /// Signs in to the demo's in-memory workspace (`DemoMode`), with nothing leaving the device.
    func enterDemo() async {
        DemoMode.enter()
        await DemoBackend.shared.restart()
        phase = .launching
        clients = [:]
        accounts = []
        activeAccountID = nil
        signInFlow.useInstance(DemoMode.instance, config: DemoMode.authConfig)
        await bootstrap()
    }

    /// The demo's second person signed in beside the open one, without opening it (for the switcher's screenshots).
    func addDemoAccount() async {
        guard DemoMode.isOn, accounts.count < 2 else { return }
        let client = makeClient(DemoMode.instance, tokenKey: nil)
        struct Body: Encodable, Sendable {
            let email: String
            let password: String
        }
        let login: AuthResult? = try? await client.post("v1/auth/login", body: Body(email: DemoPerson.theo.email, password: "demo"), workspace: .none, authorized: false)
        guard let login else { return }
        await client.adopt(login)
        let me: Me? = try? await client.get("v1/me", workspace: .none)
        guard let me else { return }
        await file(client, me: me)
    }

    /// Back to the server chosen before the demo, signed out.
    private func leaveDemo() {
        DemoMode.leave()
        clients = [:]
        let saved = AccountKeyring.load()
        accounts = saved.accounts
        signInFlow.useInstance(Preferences.instance ?? .cloud, config: nil)
        if let next = accounts.first(where: { $0.id == saved.active }) ?? accounts.first {
            Task { await open(client(for: next), account: next) }
        }
    }
    #endif

    func deleteAccount(password: String?, code: String?) async throws {
        struct Body: Encodable, Sendable {
            let password: String?
            let code: String?
        }
        try await api.delete("v1/me", body: Body(password: password?.isEmpty == true ? nil : password, code: code?.isEmpty == true ? nil : code), workspace: .none)
        if let account = activeAccount {
            await remove(account, revoke: false)
        } else {
            onLeave?()
            await api.clearTokens()
            reset(endedOn: instance)
        }
    }

    /// The server refused an account's session (revoked, expired or replayed).
    private func sessionExpired(for client: APIClient) async {
        if let account = accounts.first(where: { clients[$0.id] === client }) {
            await remove(account, revoke: false)
        } else if client === api, activeAccountID == nil, phase != .signedOut {
            onLeave?()
            reset(endedOn: client.instance)
        }
    }

    /// Takes an account off this phone: ends its session on the server when `revoke` (which also
    /// removes its push device), forgets its token, and opens the next account when it was the open one.
    private func remove(_ account: DeviceAccount, revoke: Bool) async {
        // The list changes before anything waits, so a second call for the same account finds nothing.
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let wasActive = account.id == activeAccountID
        accounts.remove(at: index)
        let client = clients.removeValue(forKey: account.id) ?? APIClient(instance: account.instance, tokenKey: account.tokenKey)
        let next = accounts.isEmpty ? nil : accounts[min(index, accounts.count - 1)]
        // Told while `activeAccountID` still names the account, when it was the open one.
        onAccountEnded?(account, accounts)
        if wasActive {
            activeAccountID = next?.id
            onLeave?()
            phase = .launching
        }
        persist()
        if revoke { await client.signOut() } else { await client.clearTokens() }
        guard wasActive else { return }
        if let next {
            await open(self.client(for: next), account: next)
        } else {
            reset(endedOn: account.instance)
        }
    }

    private func reset(endedOn ended: Instance) {
        user = nil
        memberships = []
        workspace = nil
        activeAccountID = nil
        authConfig = nil
        persist()
        let client = api
        Task { await client.setWorkspace(nil) }
        phase = .signedOut
        #if DEBUG
        if DemoMode.isOn, !DemoMode.launchedInDemo, accounts.isEmpty {
            leaveDemo()
            return
        }
        #endif
        // The sign-in screen offers the server just left.
        if signInFlow.instance != ended { signInFlow.useInstance(ended, config: configs[ended.storageKey]) }
    }
}
