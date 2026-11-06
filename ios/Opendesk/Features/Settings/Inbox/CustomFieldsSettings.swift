import SwiftUI

/// Settings › Custom fields: typed fields for tickets, contacts and companies, with options,
/// colours, "required to solve", archive and order.
struct CustomFieldsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = CustomFieldsStore()
    @State private var entity: FieldEntity = .ticket
    @State private var editing: FieldEdit?
    @State private var confirm: AccountConfirm?
    @State private var editMode: EditMode = .inactive

    private var canEdit: Bool { env.session.isAdmin }
    private var mine: [CustomField] { store.fields.filter { $0.entity == entity.rawValue }.sorted { $0.position < $1.position } }
    private var active: [CustomField] { mine.filter { !$0.archived } }
    private var archived: [CustomField] { mine.filter(\.archived) }

    var body: some View {
        InboxLoadGate(load: store.load, retry: { await store.reload() }) {
            content
        }
        .accountTitle(SettingsPage.customFields.title)
        .toolbar {
            if canEdit, store.load == .ready {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if active.count > 1 {
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            withAnimation(Motion.snappy) { editMode = editMode.isEditing ? .inactive : .active }
                        }
                        .fontWeight(editMode.isEditing ? .semibold : .regular)
                    }
                    Button { editing = FieldEdit(field: nil, entity: entity) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New field")
                }
            }
        }
        .sheet(item: $editing) { edit in
            CustomFieldEditorSheet(store: store, field: edit.field, entity: edit.entity)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
        .task { await store.start(api: env.session.api, directory: env.directory) }
    }

    private var content: some View {
        List {
            intro
            activeSection
            if !archived.isEmpty { archivedSection }
        }
        .inboxListStyle()
        .environment(\.editMode, $editMode)
        .refreshable { await store.reload() }
        .motion(Motion.snappy, value: mine.map(\.id))
        .onChange(of: entity) { _, _ in editMode = .inactive }
    }

    private func entityLabel(_ option: FieldEntity) -> String {
        let count = store.fields.filter { $0.entity == option.rawValue && !$0.archived }.count
        return "\(option.plural) \(count)"
    }

    private var intro: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Extra details your team records on tickets, contacts and companies, like plan, order number or renewal date.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                if !canEdit { SettingsReadOnlyNote() }
                AccountSegmented(options: FieldEntity.allCases, selection: $entity, label: entityLabel)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)
        }
    }

    private var activeSection: some View {
        Section {
            if active.isEmpty {
                emptyRow
            } else {
                ForEach(active) { field in row(field) }
                    .onMove(perform: canEdit ? { move(from: $0, to: $1) } : nil)
            }
        } header: {
            InboxListHeader(title: "\(entity.title) fields")
        } footer: {
            if entity == .ticket {
                InboxListFooter(text: "Fields marked required must be filled in before a ticket can be solved.")
            }
        }
    }

    private var emptyRow: some View {
        let create: (() -> Void)? = canEdit ? { editing = FieldEdit(field: nil, entity: entity) } : nil
        return EmptyState(
            symbol: "slider.horizontal.3",
            title: "No \(entity.title.lowercased()) fields yet",
            message: entity.emptyHint,
            actionTitle: canEdit ? "New field" : nil,
            action: create
        )
        .listRowBackground(Theme.surface)
    }

    private var archivedSection: some View {
        Section {
            ForEach(archived) { field in row(field) }
        } header: {
            InboxListHeader(title: InboxText.count(archived.count, "archived field", "archived fields"))
        }
    }

    private func row(_ field: CustomField) -> some View {
        Button {
            if canEdit { editing = FieldEdit(field: field, entity: entity) }
        } label: {
            CustomFieldRow(field: field)
        }
        .buttonStyle(RowPressStyle())
        .inboxListRow()
        .contextMenu {
            if canEdit {
                Button { editing = FieldEdit(field: field, entity: entity) } label: { Label("Edit", systemImage: "pencil") }
                Button { setArchived(field, !field.archived) } label: {
                    Label(field.archived ? "Restore" : "Archive", systemImage: field.archived ? "arrow.uturn.backward" : "archivebox")
                }
                Divider()
                Button(role: .destructive) { askDelete(field) } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button(role: .destructive) { askDelete(field) } label: { Label("Delete", systemImage: "trash") }
                Button { setArchived(field, !field.archived) } label: {
                    Label(field.archived ? "Restore" : "Archive", systemImage: field.archived ? "arrow.uturn.backward" : "archivebox")
                }
                .tint(Tone.gray.solid)
            }
        }
    }

    private func move(from: IndexSet, to: Int) {
        var ids = active.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        guard ids != active.map(\.id) else { return }
        Task {
            do { try await store.reorder(entity, ids) } catch { env.toasts.error(error) }
        }
    }

    private func setArchived(_ field: CustomField, _ value: Bool) {
        Task {
            do { try await store.setArchived(field, value) } catch { env.toasts.error(error) }
        }
    }

    private func askDelete(_ field: CustomField) {
        confirm = AccountConfirm(
            title: "Delete this field?",
            message: "\(field.name) and every value stored in it are removed. This can't be undone.",
            confirmTitle: "Delete field"
        ) {
            do {
                try await store.delete(field)
                Haptics.success()
            } catch {
                env.toasts.error(error)
            }
        }
    }

    struct FieldEdit: Identifiable {
        let id = UUID()
        var field: CustomField?
        var entity: FieldEntity
    }

    /// Fields have no page of their own: a link to one opens the list.
    struct Detail: View {
        let id: String

        var body: some View {
            CustomFieldsSettings()
        }
    }
}

private struct CustomFieldRow: View {
    let field: CustomField

    var body: some View {
        HStack(spacing: 12) {
            AccountIconTile(symbol: field.type.symbol, tone: field.type.kindTone)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(field.name).font(ODFont.sans(15, weight: .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                    if field.requiredOnSolve { TonePill(text: "Required to solve", tone: .amber, height: 18) }
                    if field.archived { TonePill(text: "Archived", tone: .gray, height: 18) }
                }
                HStack(spacing: 5) {
                    Text(field.type.kindTitle).font(ODFont.footnote).foregroundStyle(Theme.fg3)
                    Text("\u{00B7}").foregroundStyle(Theme.fg4)
                    Text(field.key).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg4).lineLimit(1)
                }
                if field.type.takesOptions && !field.options.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(field.options.prefix(3)) { option in
                            TonePill(text: option.label, tone: Tone(label: option.color), height: 18) {
                                RoundedRectangle(cornerRadius: 1.5).fill(Tone(label: option.color).solid).frame(width: 6, height: 6)
                            }
                        }
                        if field.options.count > 3 {
                            Text("+\(field.options.count - 3)").font(ODFont.mono(11)).foregroundStyle(Theme.fg4)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .opacity(field.archived ? 0.65 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Store

@MainActor
@Observable
final class CustomFieldsStore {
    private(set) var fields: [CustomField] = []
    private(set) var load: InboxLoad = .loading

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var directory: DirectoryStore?

    func start(api: APIClient, directory: DirectoryStore) async {
        self.api = api
        self.directory = directory
        await reload()
    }

    func reload() async {
        guard let api else { return }
        do {
            let page: Page<CustomField> = try await api.get("v1/custom-fields", query: [URLQueryItem(name: "archived", value: "any")])
            fields = page.data
            load = .ready
        } catch {
            if error.isCancellation { return }
            if load != .ready { load = .failed(error.userMessage) }
        }
    }

    /// An option while it is edited: `optionID` is the saved id, empty for a new one.
    struct DraftOption: Identifiable, Equatable {
        let id = UUID()
        var optionID: String
        var label: String
        var color: Tone
    }

    func save(entity: FieldEntity, existing: CustomField?, key: String, name: String, type: CustomField.Kind, options: [DraftOption], required: Bool, description: String) async throws {
        guard let api else { throw APIError.signedOut }
        // Option ids stay as saved; new ones get a slug of their label, made unique.
        var ids = Set<String>()
        let clean: [JSONValue] = options.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }.map { option in
            var id = option.optionID.isEmpty ? FieldSlug.option(option.label) : option.optionID
            while ids.contains(id) { id += "-2" }
            ids.insert(id)
            return .object(["id": .string(id), "label": .string(option.label.trimmingCharacters(in: .whitespaces)), "color": .string(option.color.rawValue)])
        }
        var body: [String: JSONValue] = [
            "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        if type.takesOptions { body["options"] = .array(clean) }
        if entity == .ticket { body["required_on_solve"] = .bool(required) }
        let saved: CustomField
        if let existing {
            saved = try await api.patch("v1/custom-fields/\(existing.id)", body: JSONValue.object(body))
        } else {
            body["entity"] = .string(entity.rawValue)
            body["key"] = .string(key)
            body["type"] = .string(type.rawValue)
            saved = try await api.post("v1/custom-fields", body: JSONValue.object(body))
        }
        upsert(saved)
        changed()
    }

    func setArchived(_ field: CustomField, _ value: Bool) async throws {
        guard let api else { return }
        let before = fields
        if let index = fields.firstIndex(where: { $0.id == field.id }) { fields[index].archived = value }
        do {
            let saved: CustomField = try await api.patch("v1/custom-fields/\(field.id)", body: ["archived": value])
            upsert(saved)
            changed()
        } catch {
            fields = before
            throw error
        }
    }

    func delete(_ field: CustomField) async throws {
        guard let api else { return }
        try await api.delete("v1/custom-fields/\(field.id)")
        fields.removeAll { $0.id == field.id }
        changed()
    }

    func reorder(_ entity: FieldEntity, _ ids: [String]) async throws {
        guard let api else { return }
        let before = fields
        for (offset, id) in ids.enumerated() {
            if let index = fields.firstIndex(where: { $0.id == id }) { fields[index].position = offset }
        }
        do {
            struct Body: Encodable, Sendable { let entity: String; let ids: [String] }
            let page: Page<CustomField> = try await api.post("v1/custom-fields/reorder", body: Body(entity: entity.rawValue, ids: ids))
            for field in page.data { upsert(field) }
            changed()
        } catch {
            fields = before
            throw error
        }
    }

    private func upsert(_ field: CustomField) {
        if let index = fields.firstIndex(where: { $0.id == field.id }) { fields[index] = field } else { fields.append(field) }
    }

    /// The directory's fields drive the record sidebars and filters.
    private func changed() {
        guard let directory else { return }
        Task { await directory.load() }
    }
}

/// The contract's key rule and the web's slugs for keys and option ids.
enum FieldSlug {
    /// A lowercase slug, starting with a letter, up to 40.
    static func keyValid(_ key: String) -> Bool {
        guard let first = key.first, first.isASCII, first.isLowercase, first.isLetter, key.count <= 40 else { return false }
        return key.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }

    static func key(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en")).lowercased()
        var out = ""
        var gap = false
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if gap && !out.isEmpty { out.append("_") }
                out.append(character)
                gap = false
            } else {
                gap = true
            }
        }
        while let first = out.first, !first.isLetter { out.removeFirst() }
        return String(out.prefix(40))
    }

    static func option(_ label: String) -> String {
        let folded = label.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en")).lowercased()
        var out = ""
        var gap = false
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-") {
                if gap && !out.isEmpty { out.append("-") }
                out.append(character)
                gap = false
            } else {
                gap = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        while out.hasPrefix("-") { out.removeFirst() }
        let slug = String(out.prefix(40))
        return slug.isEmpty ? "option" : slug
    }
}
