import Foundation
import Observation

/// Labels and label groups as Settings › Labels edits them (contracts/api.md "Labels and custom fields").
/// Writes need admin; the directory store is refreshed after each so pickers follow.
@MainActor
@Observable
final class LabelsStore {
    private(set) var labels: [SettingsLabel] = []
    private(set) var groups: [SettingsLabelGroup] = []
    private(set) var load: InboxLoad = .loading
    /// Who may create a label by typing a new name: "anyone" or "admins".
    private(set) var creation = "anyone"

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
            async let tags: Page<SettingsLabel> = api.get("v1/tags", query: [URLQueryItem(name: "archived", value: "any")])
            async let groups: Page<SettingsLabelGroup> = api.get("v1/tag-groups")
            async let flags: InboxWorkspaceFlags? = try? api.get("v1/workspace")
            labels = try await tags.data.sorted { ($0.position, $0.name.lowercased()) < ($1.position, $1.name.lowercased()) }
            self.groups = try await groups.data.sorted { $0.position < $1.position }
            if let flags = await flags { creation = flags.labelCreation }
            load = .ready
        } catch {
            if error.isCancellation { return }
            if load != .ready { load = .failed(error.userMessage) }
        }
    }

    // MARK: Reading

    var active: [SettingsLabel] { labels.filter { !$0.archived } }
    var archived: [SettingsLabel] { labels.filter(\.archived) }

    func group(_ id: String?) -> SettingsLabelGroup? {
        guard let id else { return nil }
        return groups.first { $0.id == id }
    }

    // MARK: Labels

    struct Draft: Equatable {
        var name = ""
        var color: Tone?
        var description = ""
        var groupID: String?
        var scopes: Set<LabelScope> = Set(LabelScope.allCases)

        init(defaultGroup: String? = nil) { groupID = defaultGroup }

        init(_ label: SettingsLabel) {
            name = label.name
            color = label.color
            description = label.description
            groupID = label.groupID
            scopes = Set(label.appliesTo)
        }

        var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

        /// Letters, numbers, spaces and - _ . / : & + # (the server's rule).
        var hasBadCharacters: Bool {
            trimmed.contains { !($0.isLetter || $0.isNumber || " _-./:&+#".contains($0)) }
        }

        var body: JSONValue {
            var object: [String: JSONValue] = [
                "name": .string(trimmed),
                "description": .string(description.trimmingCharacters(in: .whitespacesAndNewlines)),
                "group_id": groupID.map(JSONValue.string) ?? .null,
                "applies_to": .array(LabelScope.allCases.filter { scopes.contains($0) }.map { .string($0.rawValue) }),
            ]
            if let color { object["color"] = .string(color.rawValue) }
            return .object(object)
        }
    }

    func save(_ draft: Draft, existing: SettingsLabel?) async throws -> SettingsLabel {
        guard let api else { throw APIError.signedOut }
        let saved: SettingsLabel
        if let existing {
            saved = try await api.patch("v1/tags/\(existing.id)", body: draft.body)
        } else {
            saved = try await api.post("v1/tags", body: draft.body)
        }
        upsert(saved)
        changed()
        return saved
    }

    /// One member of a label (archive, colour, group), applied at once and undone on failure.
    func patch(_ label: SettingsLabel, _ body: [String: JSONValue], apply: (inout SettingsLabel) -> Void) async throws {
        guard let api else { return }
        let before = labels
        if let index = labels.firstIndex(where: { $0.id == label.id }) { apply(&labels[index]) }
        do {
            let saved: SettingsLabel = try await api.patch("v1/tags/\(label.id)", body: JSONValue.object(body))
            upsert(saved)
            changed()
        } catch {
            labels = before
            throw error
        }
    }

    func delete(_ label: SettingsLabel) async throws {
        guard let api else { return }
        try await api.delete("v1/tags/\(label.id)")
        labels.removeAll { $0.id == label.id }
        changed()
    }

    /// Everything labelled `label` gets `into` instead, and `label` is deleted.
    func merge(_ label: SettingsLabel, into: String) async throws {
        guard let api else { return }
        let target: SettingsLabel = try await api.post("v1/tags/\(label.id)/merge", body: ["into": into])
        labels.removeAll { $0.id == label.id }
        upsert(target)
        changed()
    }

    /// Saves the order of a group's labels: they take the group's places in the new order.
    func reorder(_ ids: [String]) async throws {
        guard let api else { return }
        let before = labels
        let slots = labels.filter { ids.contains($0.id) }.map(\.position).sorted()
        for (offset, id) in ids.enumerated() {
            if let index = labels.firstIndex(where: { $0.id == id }) { labels[index].position = slots.indices.contains(offset) ? slots[offset] : offset }
        }
        labels.sort { ($0.position, $0.name.lowercased()) < ($1.position, $1.name.lowercased()) }
        do {
            let _: Page<SettingsLabel> = try await api.post("v1/tags/reorder", body: ["ids": ids])
            await reload()
            changed()
        } catch {
            labels = before
            throw error
        }
    }

    // MARK: Groups

    struct GroupDraft: Equatable {
        var name = ""
        var color: Tone?
        var exclusive = false

        init() {}

        init(_ group: SettingsLabelGroup) {
            name = group.name
            color = group.color
            exclusive = group.exclusive
        }

        var body: JSONValue {
            .object([
                "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
                "color": color.map { .string($0.rawValue) } ?? .null,
                "exclusive": .bool(exclusive),
            ])
        }
    }

    func saveGroup(_ draft: GroupDraft, existing: SettingsLabelGroup?) async throws {
        guard let api else { return }
        let saved: SettingsLabelGroup
        if let existing {
            saved = try await api.patch("v1/tag-groups/\(existing.id)", body: draft.body)
        } else {
            saved = try await api.post("v1/tag-groups", body: draft.body)
        }
        if let index = groups.firstIndex(where: { $0.id == saved.id }) { groups[index] = saved } else { groups.append(saved) }
        groups.sort { $0.position < $1.position }
        changed()
    }

    /// The group's labels stay and move to Other labels.
    func deleteGroup(_ group: SettingsLabelGroup) async throws {
        guard let api else { return }
        try await api.delete("v1/tag-groups/\(group.id)")
        groups.removeAll { $0.id == group.id }
        for index in labels.indices where labels[index].groupID == group.id { labels[index].groupID = nil }
        changed()
    }

    // MARK: Creating labels

    func setCreation(_ value: String) async throws {
        guard let api, value != creation else { return }
        let before = creation
        creation = value
        do {
            let _: EmptyBody = try await api.patch("v1/workspace", body: JSONValue.object(["settings": .object(["label_creation": .string(value)])]))
        } catch {
            creation = before
            throw error
        }
    }

    // MARK: Plumbing

    private func upsert(_ label: SettingsLabel) {
        if let index = labels.firstIndex(where: { $0.id == label.id }) { labels[index] = label } else { labels.append(label) }
        labels.sort { ($0.position, $0.name.lowercased()) < ($1.position, $1.name.lowercased()) }
    }

    /// Pickers across the app read labels from the directory.
    private func changed() {
        guard let directory else { return }
        Task { await directory.load() }
    }
}
