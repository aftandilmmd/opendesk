import Foundation
import Observation

/// One run of signing in: the server it is for and every way in (password,
/// OAuth, passkey, 2FA, linking, registration). The signed-out screen has one
/// (`SessionStore.signInFlow`); "Add another account" makes its own, so the open
/// account keeps working underneath until the new one is in.
///
/// Its client holds the new session's refresh token in memory only; once the
/// server answers with a session, `onSignedIn` hands the client over to become an account.
@MainActor
@Observable
final class SignInFlow: Identifiable {
    let id = UUID()
    /// Adding to the accounts already signed in, in a sheet over the app.
    let adding: Bool
    private(set) var instance: Instance
    private(set) var authConfig: AuthConfig?
    private(set) var authConfigError: String?

    @ObservationIgnored private(set) var api: APIClient
    @ObservationIgnored private var attest: AppAttestClient
    /// Set by the session: files the signed-in client as an account and opens it.
    @ObservationIgnored var onSignedIn: (@MainActor (APIClient, AuthConfig?) async throws -> Void)?

    init(instance: Instance, config: AuthConfig? = nil, adding: Bool) {
        self.instance = instance
        self.adding = adding
        authConfig = config
        api = APIClient(instance: instance)
        attest = AppAttestClient(api: api)
    }

    func loadAuthConfig() async {
        let target = instance
        do {
            let config = try await InstanceResolver().authConfig(for: target.apiURL)
            guard target == instance else { return }
            authConfig = config
            authConfigError = nil
        } catch {
            guard target == instance else { return }
            authConfigError = error.userMessage
        }
    }

    /// Moves the sign-in to another server.
    func useInstance(_ next: Instance, config: AuthConfig?) {
        instance = next
        if !adding { Preferences.instance = next }
        authConfig = config
        authConfigError = nil
        api = APIClient(instance: next)
        attest = AppAttestClient(api: api)
        if config == nil { Task { await loadAuthConfig() } }
    }

    // MARK: Steps

    private func humanCheck(_ action: AppAttestClient.Action) async throws -> AppAttestProof? {
        let config: AuthConfig
        if let authConfig {
            config = authConfig
        } else {
            await loadAuthConfig()
            guard let authConfig else { throw APIError.transport(URLError(.cannotConnectToHost)) }
            config = authConfig
        }
        guard config.humanCheckRequired else { return nil }
        guard config.native.appAttest else { throw SignInError.humanCheckUnavailable }
        return try await attest.proof(for: action)
    }

    func signIn(email: String, password: String) async throws -> SignInOutcome {
        struct Body: Encodable, Sendable {
            let email: String
            let password: String
            let app_attest: AppAttestProof?
        }
        let proof = try await humanCheck(.login)
        let client = api
        let result: AuthResult = try await withAttestRetry {
            try await client.post("v1/auth/login", body: Body(email: email, password: password, app_attest: proof), workspace: .none, authorized: false)
        }
        return try await complete(result)
    }

    func verifyMFA(token: String, code: String) async throws {
        struct Body: Encodable, Sendable {
            let mfa_token: String
            let code: String
        }
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let result: AuthResult = try await api.post("v1/auth/mfa", body: Body(mfa_token: token, code: cleaned), workspace: .none, authorized: false)
        _ = try await complete(result)
    }

    func register(name: String, email: String, password: String) async throws -> SignInOutcome {
        struct Body: Encodable, Sendable {
            let name: String
            let email: String
            let password: String
            let app_attest: AppAttestProof?
        }
        let proof = try await humanCheck(.register)
        let client = api
        let result: AuthResult = try await withAttestRetry {
            try await client.post("v1/auth/register", body: Body(name: name, email: email, password: password, app_attest: proof), workspace: .none, authorized: false)
        }
        return try await complete(result)
    }

    func forgotPassword(email: String) async throws {
        struct Body: Encodable, Sendable {
            let email: String
            let app_attest: AppAttestProof?
        }
        let proof = try await humanCheck(.passwordForgot)
        let client = api
        let _: EmptyBody = try await withAttestRetry {
            try await client.post("v1/auth/password/forgot", body: Body(email: email, app_attest: proof), workspace: .none, authorized: false)
        }
    }

    /// A refused proof can mean the server lost this install's key: forget it so the next try registers a new one.
    private func withAttestRetry<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as APIError where error.code == "captcha_failed" {
            await attest.forgetKey()
            throw error
        }
    }

    /// `{apiUrl}/v1/auth/oauth/{provider}/start?client=native&code_challenge=…`
    func oauthStartURL(provider: String, challenge: String) -> URL? {
        var components = URLComponents(url: instance.apiURL.appending(path: "v1/auth/oauth/\(provider)/start"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client", value: "native"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "redirect_to", value: "/inbox"),
        ]
        return components?.url
    }

    func exchangeOAuth(code: String, verifier: String) async throws -> SignInOutcome {
        struct Body: Encodable, Sendable {
            let code: String
            let code_verifier: String
        }
        let result: AuthResult = try await api.post("v1/auth/oauth/exchange", body: Body(code: code, code_verifier: verifier), workspace: .none, authorized: false)
        return try await complete(result)
    }

    func linkAccount(token: String, password: String) async throws -> SignInOutcome {
        struct Body: Encodable, Sendable {
            let link_token: String
            let password: String
        }
        let result: AuthResult = try await api.post("v1/auth/oauth/link", body: Body(link_token: token, password: password), workspace: .none, authorized: false)
        return try await complete(result)
    }

    func beginPasskey() async throws -> PasskeyBegin {
        try await api.post("v1/auth/passkey/login/begin", workspace: .none, authorized: false)
    }

    func finishPasskey(token: String, credential: JSONValue) async throws -> SignInOutcome {
        struct Body: Encodable, Sendable {
            let passkey_token: String
            let credential: JSONValue
        }
        let result: AuthResult = try await api.post("v1/auth/passkey/login/finish", body: Body(passkey_token: token, credential: credential), workspace: .none, authorized: false)
        return try await complete(result)
    }

    private func complete(_ result: AuthResult) async throws -> SignInOutcome {
        if result.linkRequired, let token = result.linkToken {
            return .link(token: token, email: result.email ?? "")
        }
        if result.mfaRequired, let token = result.mfaToken {
            return .mfa(token: token)
        }
        guard result.accessToken != nil else { throw APIError.decoding }
        let client = api
        await client.adopt(result)
        // The session now belongs to the account; another try starts on a client of its own.
        api = APIClient(instance: instance)
        attest = AppAttestClient(api: api)
        try await onSignedIn?(client, authConfig)
        return .signedIn
    }
}

enum SignInError: LocalizedError {
    case humanCheckUnavailable
    case tooManyAccounts

    var errorDescription: String? {
        switch self {
        case .humanCheckUnavailable:
            "This server checks sign-ins with a captcha the app can't show. Use another sign-in option, or sign in on the web."
        case .tooManyAccounts:
            "You're signed in to \(AccountKeyring.maxAccounts) accounts, the most this app holds. Sign out of one, then try again."
        }
    }
}
