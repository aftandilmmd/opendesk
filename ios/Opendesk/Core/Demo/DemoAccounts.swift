#if DEBUG
import Foundation

/// Several accounts in the demo: Maya signs in first, and "Add another account"
/// signs in Theo, a viewer at Margin, so the switcher has two people to show.
/// Each has their own tokens; only who they are differs (the rest of the world
/// answers as it does for Maya).
extension DemoBackend {
    static let secondAccessToken = "demo-access-theo"
    static let secondRefreshToken = "demo-refresh-theo"

    /// Sign-in, refresh and sign-out for both people, and `GET /v1/me` for Theo; nil for everything else.
    func accountsRoutes(_ call: Call) throws -> Data?? {
        for route in ["auth/login", "auth/register", "auth/mfa", "auth/oauth/exchange", "auth/oauth/link", "auth/passkey/login/finish", "auth/refresh"] where call.match("POST", route) != nil {
            let person = signingIn(call, refresh: route == "auth/refresh")
            signedIn.insert(person)
            let second = person == .theo
            return .some(encode(JSONValue.object([
                "access_token": .string(second ? Self.secondAccessToken : "demo-access-token"), "expires_in": .number(86400),
                "refresh_token": .string(second ? Self.secondRefreshToken : Self.refreshToken),
                "user": DemoSeed.json(second ? secondUser : world.user),
            ])))
        }
        if call.match("POST", "auth/logout") != nil {
            if let token = call.string("refresh_token") { signedIn.remove(token == Self.secondRefreshToken ? .theo : .maya) }
            return .some(nil)
        }
        if call.match("GET", "me") != nil, call.bearer == Self.secondAccessToken {
            let margin = world.workspaces.first { $0.id == DemoSeed.marginID } ?? world.workspaces[0]
            return .some(encode(Me(user: secondUser, memberships: [Membership(workspace: margin.workspace, role: DemoPerson.theo.role)])))
        }
        return nil
    }

    /// Who a sign-in opens: the person the address names; any other address opens Maya, or Theo
    /// once Maya is signed in.
    private func signingIn(_ call: Call, refresh: Bool) -> DemoPerson {
        if refresh { return call.string("refresh_token") == Self.secondRefreshToken ? .theo : .maya }
        switch call.string("email")?.lowercased() {
        case DemoPerson.theo.email: return .theo
        case DemoPerson.maya.email: return .maya
        default: return signedIn.contains(.maya) ? .theo : .maya
        }
    }

    private var secondUser: User {
        let theo = DemoPerson.theo
        return User(id: theo.id, email: theo.email, name: theo.name, avatarURL: nil, avatarSource: nil, emailVerified: true, totpEnabled: false, createdAt: DemoSeed.ago(90 * 1440))
    }
}
#endif
