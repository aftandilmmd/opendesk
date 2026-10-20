import Foundation
import Observation
import UIKit
import UserNotifications
import os

/// APNs registration and the device record on the server (contracts/native.md "Push").
///
/// The system prompt is never shown cold: the app explains notifications
/// once, after sign-in, and asks only when the person agrees. With
/// `push = direct` the APNs token goes to the instance; with `relay` it is
/// first exchanged at the opendesk relay for a sealed relay token; with `off`
/// nothing is registered and the settings say so.
@MainActor
@Observable
final class PushManager: NSObject {
    static let shared = PushManager()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var device: PushDevice?
    private(set) var registering = false
    private(set) var lastError: String?

    @ObservationIgnored weak var environment: AppEnvironment?
    @ObservationIgnored private var apnsToken: String?
    @ObservationIgnored private let log = Logger(subsystem: "sh.opendesk.app", category: "push")
    /// Taps that arrive before the app is signed in wait here.
    @ObservationIgnored private(set) var pendingTap: PushPayload?

    private var session: SessionStore? { environment?.session }

    var mode: PushMode { session?.authConfig?.native.push ?? .off }

    var isEnabledOnDevice: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    /// The app should offer to turn notifications on (once, at a calm moment).
    var shouldOfferPermission: Bool {
        #if DEBUG
        if DemoMode.isOn { return false }
        #endif
        return authorization == .notDetermined && mode != .off && !Preferences.askedForPush && AppInfo.debugValue("OPENDESK_DEBUG_NO_PUSH_PROMPT") == nil
    }

    // MARK: Launch

    func prepare() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let assign = UNNotificationAction(identifier: PushCategory.assignToMe, title: String(localized: "push.action.assign_me"), options: [.authenticationRequired])
        let read = UNNotificationAction(identifier: PushCategory.markRead, title: String(localized: "push.action.mark_read"), options: [])
        let reply = UNTextInputNotificationAction(
            identifier: PushCategory.reply,
            title: String(localized: "push.action.reply"),
            options: [.authenticationRequired],
            textInputButtonTitle: String(localized: "push.action.send"),
            textInputPlaceholder: String(localized: "push.action.reply_placeholder")
        )
        let ticket = UNNotificationCategory(identifier: PushCategory.ticket, actions: [reply, assign, read], intentIdentifiers: [], options: [])
        center.setNotificationCategories([ticket])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Signed in and in a workspace: register again if allowed (the server upserts by token).
    func sessionReady() {
        #if DEBUG
        // Demo mode never registers with APNs; the device record comes from the demo backend.
        if DemoMode.isOn {
            Task { await loadDevice() }
            return
        }
        #endif
        Task {
            await refreshAuthorization()
            if isEnabledOnDevice, mode != .off {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await loadDevice()
        }
    }

    /// Asks the system (after the app explained why). Returns whether notifications are on.
    @discardableResult
    func requestPermission() async -> Bool {
        Preferences.askedForPush = true
        #if DEBUG
        if DemoMode.isOn { return false }
        #endif
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorization()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func declinePermission() {
        Preferences.askedForPush = true
    }

    /// Signed out: the server already deleted this session's devices; forget ours and clear the badge.
    func sessionEnded(_ instance: Instance) {
        Preferences.setDeviceID(nil, for: instance)
        device = nil
        setBadge(0)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }

    // MARK: Device record

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        apnsToken = token
        Task { await registerDevice(token: token) }
    }

    func didFailToRegister(_ error: Error) {
        log.warning("APNs registration failed: \(error.localizedDescription, privacy: .public)")
        lastError = "This device couldn't register for notifications."
    }

    private func registerDevice(token: String) async {
        #if DEBUG
        if DemoMode.isOn { return }
        #endif
        guard let session, session.phase == .ready else { return }
        let api = session.api
        let instance = session.instance
        registering = true
        defer { registering = false }
        struct Body: Encodable, Sendable {
            let platform: String
            let token: String?
            let relay_token: String?
            let environment: String
            let app_version: String
            let name: String
        }
        do {
            var relayToken: String?
            switch mode {
            case .off:
                return
            case .direct:
                break
            case .relay:
                guard let relay = session.authConfig?.native.relayURL, let relayURL = URL(string: relay) else { return }
                relayToken = try await exchangeAtRelay(relayURL, token: token, instance: instance)
            }
            let body = Body(
                platform: "ios",
                token: relayToken == nil ? token : nil,
                relay_token: relayToken,
                environment: AppInfo.pushEnvironment,
                app_version: AppInfo.version,
                name: UIDevice.current.name
            )
            let saved: PushDevice = try await api.post("v1/me/devices", body: body, workspace: .none)
            device = saved
            Preferences.setDeviceID(saved.id, for: instance)
            lastError = nil
        } catch {
            lastError = error.userMessage
            log.warning("device registration failed: \(error.userMessage, privacy: .public)")
        }
    }

    /// `POST {relay_url}/v1/push/relay/register`: the relay seals the APNs token for this instance.
    private func exchangeAtRelay(_ relay: URL, token: String, instance: Instance) async throws -> String {
        struct Body: Encodable { let token: String; let environment: String; let instance: String }
        struct Answer: Decodable { let relay_token: String }
        var request = URLRequest(url: relay.appending(path: "v1/push/relay/register"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.clientHeader, forHTTPHeaderField: "OD-Client")
        request.httpBody = try JSONEncoder().encode(Body(token: token, environment: AppInfo.pushEnvironment, instance: PushPayload.origin(instance.apiURL)))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        guard (200 ..< 300).contains(http.statusCode) else { throw APIError.parse(status: http.statusCode, data: data) }
        return try JSONDecoder().decode(Answer.self, from: data).relay_token
    }

    /// This install's device record, if the server has one.
    func loadDevice() async {
        guard let session else { return }
        guard let devices: [PushDevice] = try? await session.api.get("v1/me/devices", workspace: .none) else { return }
        let stored = Preferences.deviceID(for: session.instance)
        device = devices.first(where: { $0.id == stored }) ?? devices.first(where: \.current)
    }

    func setMuted(_ kind: NotificationKind, muted: Bool) async {
        guard let session, var current = device else { return }
        var types = Set(current.mutedTypes)
        if muted { types.insert(kind.rawValue) } else { types.remove(kind.rawValue) }
        let ordered = NotificationKind.allCases.map(\.rawValue).filter(types.contains)
        current.mutedTypes = ordered
        device = current
        struct Body: Encodable, Sendable { let muted_types: [String] }
        do {
            let saved: PushDevice = try await session.api.patch("v1/me/devices/\(current.id)", body: Body(muted_types: ordered), workspace: .none)
            device = saved
        } catch {
            lastError = error.userMessage
            await loadDevice()
        }
    }

    // MARK: Actions from a notification

    private func perform(action: String, payload: PushPayload, text: String?) async {
        guard let env = environment, let ticketID = payload.ticketID else { return }
        let session = env.session
        guard session.phase == .ready, payload.isFrom(session.instance) else { return }
        let api = session.api
        let workspace: WorkspaceScope = payload.workspaceID.map(WorkspaceScope.id) ?? .current
        do {
            switch action {
            case PushCategory.assignToMe:
                guard let me = session.user?.id else { return }
                struct Body: Encodable, Sendable { let assignee_id: String }
                var request = APIRequest(method: "PATCH", path: "v1/tickets/\(ticketID)", body: try APICoding.encoder.encode(Body(assignee_id: me)))
                request.workspace = workspace
                let _: Ticket = try await api.send(request)
            case PushCategory.markRead:
                break
            case PushCategory.reply:
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                struct Body: Encodable, Sendable { let kind: String; let body_html: String }
                var request = APIRequest(method: "POST", path: "v1/tickets/\(ticketID)/messages", body: try APICoding.encoder.encode(Body(kind: "reply", body_html: HTMLText.html(fromPlain: text))))
                request.workspace = workspace
                request.idempotencyKey = "push-reply-" + (payload.notificationID ?? UUID().uuidString)
                let _: Message = try await api.send(request)
            default:
                return
            }
            if let id = payload.notificationID {
                struct Read: Encodable, Sendable { let ids: [String] }
                var request = APIRequest(method: "POST", path: "v1/notifications/read", body: try APICoding.encoder.encode(Read(ids: [id])))
                request.workspace = workspace
                let _: EmptyBody = try await api.send(request)
            }
            env.notifications.foregrounded()
        } catch {
            log.warning("notification action failed: \(error.userMessage, privacy: .public)")
        }
    }

    func takePendingTap() -> PushPayload? {
        defer { pendingTap = nil }
        return pendingTap
    }

    fileprivate func opened(_ payload: PushPayload) {
        guard let env = environment, env.session.phase == .ready else {
            pendingTap = payload
            return
        }
        env.router.open(payload.target)
        if let id = payload.notificationID, payload.isFrom(env.session.instance) {
            Task {
                struct Read: Encodable, Sendable { let ids: [String] }
                var request = APIRequest(method: "POST", path: "v1/notifications/read", body: try? APICoding.encoder.encode(Read(ids: [id])))
                if let workspace = payload.workspaceID { request.workspace = .id(workspace) }
                let _: EmptyBody? = try? await env.session.api.send(request)
                env.notifications.foregrounded()
            }
        }
    }

    /// In the foreground a push for the ticket on screen stays quiet (realtime already shows it).
    fileprivate func presentation(for payload: PushPayload?) -> UNNotificationPresentationOptions {
        guard let payload, let env = environment else { return [.banner, .list, .sound, .badge] }
        if let ticketID = payload.ticketID, env.router.visibleTicketID == ticketID, payload.isFrom(env.session.instance) {
            return [.badge]
        }
        env.notifications.foregrounded()
        return [.banner, .list, .sound, .badge]
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let payload = PushPayload(userInfo: info)
        return await MainActor.run { self.presentation(for: payload) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let payload = PushPayload(userInfo: info) else { return }
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        if action == UNNotificationDefaultActionIdentifier {
            await MainActor.run { self.opened(payload) }
        } else if action != UNNotificationDismissActionIdentifier {
            await self.perform(action: action, payload: payload, text: text)
        }
    }
}

/// Bridges the UIKit launch and APNs callbacks into `PushManager`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated { PushManager.shared.prepare() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MainActor.assumeIsolated { PushManager.shared.didFailToRegister(error) }
    }
}
