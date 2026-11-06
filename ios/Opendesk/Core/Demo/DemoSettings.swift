#if DEBUG
import Foundation

// The workspace settings pages of the demo. Each group of `SettingsGroup` keeps its data
// and answers its routes from its own file (`DemoSettingsWorkspace.swift` and the rest);
// these run before every other area's routes.

struct DemoSettings: Sendable {
    var workspace = DemoWorkspaceSettings()
    var inbox = DemoInboxSettings()
    var channels = DemoChannelSettings()
    var agent = DemoAgentSettings()
    var developers = DemoDeveloperSettings()

    static func seed(_ ws: DemoWorkspace) -> DemoSettings {
        DemoSettings(
            workspace: .seed(ws),
            inbox: .seed(ws),
            channels: .seed(ws),
            agent: .seed(ws),
            developers: .seed(ws)
        )
    }
}

extension DemoBackend {
    func settingsRoutes(_ call: Call, in ws: inout DemoWorkspace) throws -> Data?? {
        if let answer = try workspaceSettingsRoutes(call, in: &ws) { return answer }
        if let answer = try inboxSettingsRoutes(call, in: &ws) { return answer }
        if let answer = try channelSettingsRoutes(call, in: &ws) { return answer }
        if let answer = try agentSettingsRoutes(call, in: &ws) { return answer }
        if let answer = try developerSettingsRoutes(call, in: &ws) { return answer }
        return nil
    }
}
#endif
