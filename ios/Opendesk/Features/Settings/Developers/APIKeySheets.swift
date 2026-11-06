import SwiftUI

// The sheets of Settings › API keys: a new key (shown once), its permissions, its expiry,
// the bot it speaks as, and its name. A new key, an added permission and a later expiry ask
// for a fresh sign-in, as on the web; taking access away applies at once.

// MARK: - Scopes

/// The scope presets and chips, for a new key and for changing an existing one's.
struct APIKeyScopeChecklist: View {
    @Binding var scopes: [String]

    private enum Preset: String, CaseIterable { case read, full, custom }

    private var preset: Preset {
        if scopes.count == APIKeyScopes.all.count, APIKeyScopes.isFull(scopes) { return .full }
        if APIKeyScopes.isReadOnly(scopes) { return .read }
        return .custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DevFieldLabel(title: "Scopes")
            AccountSegmented(options: Preset.allCases, selection: Binding(get: { preset }, set: { value in
                switch value {
                case .read: scopes = APIKeyScopes.read
                case .full: scopes = APIKeyScopes.all
                case .custom: break
                }
            })) { value in
                switch value {
                case .read: "Read only"
                case .full: "Full access"
                case .custom: "Custom"
                }
            }
            Panel {
                ForEach(Array(APIKeyScopes.groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Hairline(inset: 14) }
                    HStack(spacing: 8) {
                        Text(group.label)
                            .font(ODFont.sans(14.5))
                            .foregroundStyle(Theme.fg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 6)
                        ForEach(group.scopes, id: \.id) { scope in
                            DevCheckChip(title: scope.label, on: scopes.contains(scope.id)) { toggle(scope.id) }
                                .accessibilityLabel("\(group.label) \(scope.label.lowercased())")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 48)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(Motion.snappy) {
            if scopes.contains(id) { scopes.removeAll { $0 == id } } else { scopes.append(id) }
        }
    }
}

/// A key's access as one chip per resource, with only the levels it has there: an eye for
/// read, a pencil for write. Every scope reads "Full access", every read scope "Read only".
struct APIKeyAccessChips: View {
    let scopes: [String]
    /// Chips before "+N"; nil shows every one.
    var shown: Int? = 3

    var body: some View {
        let groups = APIKeyScopes.grouped(scopes)
        FlowLayout(spacing: 4) {
            if APIKeyScopes.isFull(scopes) {
                chipFrame(tone: .amber) { Text("Full access") }
            } else if APIKeyScopes.isReadOnly(scopes) {
                chipFrame(tone: nil) { Text("Read only") }
            } else {
                ForEach(groups.prefix(shown ?? groups.count)) { access in
                    chip(access)
                }
                if let shown, groups.count > shown {
                    let rest = groups.dropFirst(shown)
                    chipFrame(tone: nil) { Text("+\(rest.count)").foregroundStyle(Theme.fg3) }
                        .accessibilityLabel(rest.map(\.words).joined(separator: ", "))
                }
            }
        }
    }

    private func chip(_ access: APIKeyScopes.Access) -> some View {
        chipFrame(tone: nil) {
            HStack(spacing: 4) {
                Text(access.name)
                switch access.level {
                case .subscribe: Text("· subscribe").foregroundStyle(Theme.fg4)
                case .draft: Text("· drafts as you").foregroundStyle(Theme.fg4)
                case .read: eye
                case .write: pencil
                case .readWrite:
                    eye
                    pencil
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(access.words)
    }

    private var eye: some View { Image(systemName: "eye").font(.system(size: 10, weight: .medium)).foregroundStyle(Tone.violet.text) }
    private var pencil: some View { Image(systemName: "pencil").font(.system(size: 10, weight: .medium)).foregroundStyle(Tone.amber.text) }

    private func chipFrame(tone: Tone?, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(ODFont.sans(12))
            .foregroundStyle(tone?.text ?? Theme.fg2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 21)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous).strokeBorder(tone?.line ?? Theme.line, lineWidth: 1))
    }
}

// MARK: - New key

enum APIKeyExpiryPreset: String, CaseIterable, Identifiable {
    case days30, days90, days365, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days30: "In 30 days"
        case .days90: "In 90 days"
        case .days365: "In a year"
        case .never: "Never"
        }
    }

    var short: String {
        switch self {
        case .days30: "30 days"
        case .days90: "90 days"
        case .days365: "1 year"
        case .never: "Never"
        }
    }

    var days: Int? {
        switch self {
        case .days30: 30
        case .days90: 90
        case .days365: 365
        case .never: nil
        }
    }

    func date(from now: Date = AppClock.now) -> Date? {
        days.map { now.addingTimeInterval(Double($0) * 86400) }
    }
}

/// A new key: name, expiry, scopes, the bot it speaks as and its private teams; then its
/// secret, shown once.
struct CreateAPIKeySheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var expiry: APIKeyExpiryPreset = .days90
    @State private var scopes = APIKeyScopes.read
    @State private var privateTeams: [String] = []
    @State private var bot: String?
    @State private var busy = false
    @State private var error: String?
    @State private var created: CreatedAPIKey?
    @State private var reauth: AccountStore.ReauthPrompt?

    private var store: APIKeysStore { APIKeysStore.shared }
    private var speaks: Bool { APIKeyScopes.canSpeak(scopes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let created {
                    AccountSheetHeader(title: "Copy your new key", subtitle: "This is the only time it's shown. Store it somewhere safe, like your secrets manager.", closeLabel: "Done") { dismiss() }
                    DevSecretPanel(secret: created.secret, warning: "You won't see it again. If you lose it, revoke the key and make a new one.")
                    Button("Done") { dismiss() }
                        .buttonStyle(InkButtonStyle())
                } else {
                    form
                }
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
            .motion(Motion.smooth, value: created == nil)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .interactiveDismissDisabled(created != nil)
        .devReauth($reauth)
        .task { await DevDirectory.shared.loadBots(env.session) }
    }

    @ViewBuilder
    private var form: some View {
        AccountSheetHeader(title: "New API key", closeLabel: "Cancel") { dismiss() }
        ODTextField(label: "Name", text: Binding(get: { name }, set: { name = String($0.prefix(80)) }), prompt: "Zapier sync", submitLabel: .done)
        VStack(alignment: .leading, spacing: 8) {
            DevFieldLabel(title: "Expires")
            AccountSegmented(options: APIKeyExpiryPreset.allCases, selection: $expiry) { $0.short }
        }
        APIKeyScopeChecklist(scopes: $scopes)
        if speaks {
            APIKeyBotPicker(selection: $bot)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        DevPrivateTeamsField(value: $privateTeams)
        FormError(text: error)
        Button(action: submit) { ButtonLabel(title: "Create key", busy: busy) }
            .buttonStyle(InkButtonStyle())
            .disabled(busy)
    }

    private func submit() {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return error = "Name the key so you know what uses it." }
        guard !scopes.isEmpty else { return error = "Choose at least one scope." }
        let new = APIKeysStore.NewKey(name: trimmed, scopes: scopes, expiresAt: expiry.date(), privateTeamIDs: privateTeams, botID: speaks ? bot : nil)
        busy = true
        Task {
            do {
                try await create(new)
            } catch {
                if let prompt = DevReauth.prompt(for: error, retry: { try await create(new) }) {
                    reauth = prompt
                } else if !error.isCancellation {
                    Haptics.error()
                    self.error = error.userMessage
                }
            }
            busy = false
        }
    }

    private func create(_ new: APIKeysStore.NewKey) async throws {
        let key = try await store.create(new)
        Haptics.success()
        created = key
    }
}

/// Picks the bot a key speaks as, or none: the key then writes as itself.
struct APIKeyBotPicker: View {
    @Binding var selection: String?

    private var directory: DevDirectory { DevDirectory.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DevFieldLabel(title: "Speaks as")
            Panel {
                AccountChoiceRow(symbol: "chevron.left.forwardslash.chevron.right", title: "No bot: it writes as the API", chosen: selection == nil) { selection = nil }
                ForEach(directory.bots) { bot in
                    Hairline(inset: 56)
                    Button {
                        Haptics.selection()
                        selection = bot.id
                    } label: {
                        HStack(spacing: 12) {
                            BotAvatar(bot: bot.ref, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bot.name).font(ODFont.sans(15.5)).foregroundStyle(Theme.fg)
                                if !bot.role.isEmpty { Text(bot.role).font(ODFont.footnote).foregroundStyle(Theme.fg3) }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.fg)
                                .opacity(selection == bot.id ? 1 : 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityAddTraits(selection == bot.id ? .isSelected : [])
                }
            }
            Text("Replies and notes this key writes on tickets show and go out as this bot: its name, its face and its email sign-off. For an AI of your own that answers customers.")
                .font(ODFont.footnote)
                .foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Permissions

/// Changes an existing key's scopes. Taking a scope away is immediate; adding one asks for the
/// same recent sign-in as making a key.
struct APIKeyScopesSheet: View {
    let key: APIKeyRecord

    @Environment(\.dismiss) private var dismiss
    @State private var scopes: [String] = []
    @State private var busy = false
    @State private var error: String?
    @State private var reauth: AccountStore.ReauthPrompt?

    private var added: [String] { scopes.filter { !key.scopes.contains($0) } }
    private var removed: [String] { key.scopes.filter { !scopes.contains($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(title: "Permissions for \(key.name)", subtitle: "Choose what this key can do. Taking a permission away applies at once.", closeLabel: "Cancel") { dismiss() }
                APIKeyScopeChecklist(scopes: $scopes)
                if !added.isEmpty || !removed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        DevFieldLabel(title: "Changes")
                        FlowLayout(spacing: 4) {
                            ForEach(added, id: \.self) { DevMonoChip(text: "+ \($0)", tone: .amber) }
                            ForEach(removed, id: \.self) { DevMonoChip(text: "− \($0)", struck: true) }
                        }
                    }
                    .transition(.opacity)
                }
                if !added.isEmpty {
                    Text("Adding a permission asks for a recent sign-in, as creating a key does.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                }
                FormError(text: error)
                Button(action: save) { ButtonLabel(title: "Save permissions", busy: busy) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(busy || (added.isEmpty && removed.isEmpty))
            }
            .padding(22)
            .motion(Motion.snappy, value: scopes)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .devReauth($reauth)
        .onAppear { if scopes.isEmpty { scopes = key.scopes } }
    }

    private func save() {
        error = nil
        guard !scopes.isEmpty else { return error = "Choose at least one scope." }
        let patch: [String: JSONValue] = ["scopes": .array(scopes.map(JSONValue.string))]
        busy = true
        Task {
            do {
                try await apply(patch)
            } catch {
                if let prompt = DevReauth.prompt(for: error, retry: { try await apply(patch) }) {
                    reauth = prompt
                } else if !error.isCancellation {
                    Haptics.error()
                    self.error = error.userMessage
                }
            }
            busy = false
        }
    }

    private func apply(_ patch: [String: JSONValue]) async throws {
        try await APIKeysStore.shared.update(key.id, patch)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Expiry

/// Moves an existing key's expiry. An earlier date applies at once; a later one, or never, asks
/// for the same recent sign-in as making a key. An expired key can't be brought back.
struct APIKeyExpirySheet: View {
    let key: APIKeyRecord

    private enum Choice: Hashable { case never, preset(APIKeyExpiryPreset), date }
    private enum Next: Equatable { case invalid, never, at(Date) }

    @Environment(\.dismiss) private var dismiss
    @State private var now = AppClock.now
    @State private var choice: Choice = .never
    @State private var day = AppClock.now
    @State private var busy = false
    @State private var error: String?
    @State private var reauth: AccountStore.ReauthPrompt?
    @State private var ready = false

    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now }

    private var next: Next {
        switch choice {
        case .never: return .never
        case let .preset(preset): return preset.date(from: now).map(Next.at) ?? .never
        case .date:
            let at = Date.endOfDay(day)
            return at > now ? .at(at) : .invalid
        }
    }

    private var unchanged: Bool {
        switch next {
        case .invalid: return true
        case .never: return key.expiresAt == nil
        case .at:
            if case .date = choice, let current = key.expiresAt { return Calendar.current.isDate(day, inSameDayAs: current) }
            return false
        }
    }

    /// A later date, or none where there was one: the key works longer.
    private var widens: Bool {
        guard !unchanged else { return false }
        switch next {
        case .invalid: return false
        case .never: return key.expiresAt != nil
        case let .at(date): return key.expiresAt.map { date > $0 } ?? false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(
                    title: "Expiry of \(key.name)",
                    subtitle: key.expiresAt.map { "Now expires \(Format.fullDate($0))." } ?? "Now never expires.",
                    closeLabel: "Cancel"
                ) { dismiss() }
                Panel {
                    AccountChoiceRow(title: "Never", chosen: choice == .never) { choice = .never }
                    ForEach([APIKeyExpiryPreset.days30, .days90, .days365]) { preset in
                        Hairline(inset: 14)
                        AccountChoiceRow(title: preset.title, subtitle: preset.date(from: now).map { Format.shortDate($0) }, chosen: choice == .preset(preset)) { choice = .preset(preset) }
                    }
                    Hairline(inset: 14)
                    AccountChoiceRow(title: "On a date", chosen: choice == .date) { choice = .date }
                }
                if choice == .date {
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker("Date", selection: $day, in: tomorrow..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(Theme.fg)
                            .padding(.horizontal, 8)
                            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        if next == .invalid { FormError(text: "Pick a day after today.") }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if widens {
                    Text("A later date, or none, asks for a recent sign-in, as creating a key does.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                }
                FormError(text: error)
                Button(action: save) { ButtonLabel(title: "Save expiry", busy: busy) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(busy || unchanged)
            }
            .padding(22)
            .motion(Motion.snappy, value: choice)
            .motion(Motion.snappy, value: error)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .devReauth($reauth)
        .onAppear {
            guard !ready else { return }
            ready = true
            // Opens on the key's own date: picking that same day again changes nothing.
            if let current = key.expiresAt {
                choice = .date
                day = max(current, tomorrow)
            } else {
                choice = .never
                day = now.addingTimeInterval(90 * 86400)
            }
        }
    }

    private func save() {
        error = nil
        let value: JSONValue
        switch next {
        case .invalid: return
        case .never: value = .null
        case let .at(date): value = .string(date.devISO)
        }
        let patch: [String: JSONValue] = ["expires_at": value]
        busy = true
        Task {
            do {
                try await apply(patch)
            } catch {
                if let prompt = DevReauth.prompt(for: error, retry: { try await apply(patch) }) {
                    reauth = prompt
                } else if !error.isCancellation {
                    Haptics.error()
                    self.error = error.userMessage
                }
            }
            busy = false
        }
    }

    private func apply(_ patch: [String: JSONValue]) async throws {
        try await APIKeysStore.shared.update(key.id, patch)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Bot

/// Changes the bot an existing key speaks as.
struct APIKeyBotSheet: View {
    let key: APIKeyRecord

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var bot: String?
    @State private var ready = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(title: "Bot for \(key.name)", closeLabel: "Cancel") { dismiss() }
                APIKeyBotPicker(selection: $bot)
                Button("Save") { save() }
                    .buttonStyle(InkButtonStyle())
            }
            .padding(22)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .task { await DevDirectory.shared.loadBots(env.session) }
        .onAppear {
            guard !ready else { return }
            ready = true
            bot = key.botID
        }
    }

    private func save() {
        let chosen = bot
        dismiss()
        guard chosen != key.botID else { return }
        Task {
            do {
                try await APIKeysStore.shared.optimistic(key.id, ["bot_id": chosen.map(JSONValue.string) ?? .null]) { $0.botID = chosen }
                Haptics.success()
            } catch {
                env.toasts.show("Couldn't change the key's bot", kind: .error)
            }
        }
    }
}

// MARK: - Name

struct APIKeyRenameSheet: View {
    let key: APIKeyRecord

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AccountSheetHeader(title: "Rename", closeLabel: "Cancel") { dismiss() }
            ODTextField(label: "Key name", text: Binding(get: { name }, set: { name = String($0.prefix(80)) }), submitLabel: .done) { save() }
            Button("Save") { save() }
                .buttonStyle(InkButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Theme.surface)
        .onAppear { if name.isEmpty { name = key.name } }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dismiss()
        guard trimmed != key.name else { return }
        Task {
            do {
                try await APIKeysStore.shared.optimistic(key.id, ["name": .string(trimmed)]) { $0.name = trimmed }
            } catch {
                env.toasts.show("Couldn't rename the key", kind: .error)
            }
        }
    }
}
