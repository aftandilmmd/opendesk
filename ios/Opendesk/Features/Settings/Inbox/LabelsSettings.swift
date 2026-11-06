import SwiftUI

/// Settings › Labels (the API's tags): coloured labels in groups, with where they apply,
/// how often they're used, archive, merge and order, and who may create new ones.
struct LabelsSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var store = LabelsStore()
    @State private var query = ""
    @State private var editing: LabelEdit?
    @State private var groupEditing: GroupEdit?
    @State private var merging: SettingsLabel?
    @State private var confirm: AccountConfirm?
    @State private var showArchived = false
    @State private var editMode: EditMode = .inactive

    private var canEdit: Bool { env.session.isAdmin }
    private var term: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private func matches(_ label: SettingsLabel) -> Bool {
        term.isEmpty || label.name.lowercased().contains(term) || label.description.lowercased().contains(term)
    }

    struct LabelSection: Identifiable {
        var group: SettingsLabelGroup?
        var rows: [SettingsLabel]
        var id: String { group?.id ?? "none" }
    }

    /// The groups in order, then the labels in none (or in a group that no longer exists).
    private var sections: [LabelSection] {
        let shown = store.active.filter(matches)
        var out = store.groups.map { group in LabelSection(group: group, rows: shown.filter { $0.groupID == group.id }) }
        out.append(LabelSection(group: nil, rows: shown.filter { label in label.groupID == nil || !store.groups.contains { $0.id == label.groupID } }))
        return out.filter { $0.group != nil || !$0.rows.isEmpty || store.groups.isEmpty }
    }

    var body: some View {
        InboxLoadGate(load: store.load, rows: 6, retry: { await store.reload() }) {
            content
        }
        .accountTitle(SettingsPage.labels.title)
        .toolbar { toolbar }
        .sheet(item: $editing) { edit in
            LabelEditorSheet(store: store, label: edit.label, defaultGroup: edit.group)
                .presentationDetents([.large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .sheet(item: $groupEditing) { edit in
            LabelGroupEditorSheet(store: store, group: edit.group)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .sheet(item: $merging) { label in
            LabelMergeSheet(store: store, label: label)
                .presentationDetents([.medium])
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        .accountConfirm($confirm)
        .task { await store.start(api: env.session.api, directory: env.directory) }
        .onChange(of: env.directory.tags) { _, _ in Task { await store.reload() } }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if canEdit, store.load == .ready {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !store.active.isEmpty && term.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation(Motion.snappy) { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .fontWeight(editMode.isEditing ? .semibold : .regular)
                }
                Menu {
                    Button { editing = LabelEdit(label: nil) } label: { Label("New label", systemImage: "tag") }
                    Button { groupEditing = GroupEdit(group: nil) } label: { Label("New group", systemImage: "folder.badge.plus") }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New label or group")
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Coloured labels sort tickets, contacts and companies so they are easy to find, filter and report on. Deleting a label takes it off everything that has it.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !canEdit { SettingsReadOnlyNote() }
                    if !store.labels.isEmpty { InboxStatStrip(items: summary) }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            }

            if store.active.isEmpty {
                Section {
                    EmptyState(
                        symbol: "tag",
                        title: "No labels yet",
                        message: "Labels you add to tickets show up here. Create a few to get started, like billing or bug.",
                        actionTitle: canEdit ? "New label" : nil,
                        action: canEdit ? { editing = LabelEdit(label: nil) } : nil
                    )
                    .listRowBackground(Theme.surface)
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        if section.rows.isEmpty {
                            Text(term.isEmpty ? "No labels in this group yet" : "No labels match")
                                .font(ODFont.callout)
                                .foregroundStyle(Theme.fg3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .inboxListRow()
                        }
                        ForEach(section.rows) { label in
                            row(label)
                        }
                        .onMove(perform: canEdit && term.isEmpty ? { from, to in move(section.rows, from: from, to: to) } : nil)
                    } header: {
                        header(section.group, count: section.rows.count)
                    }
                }
            }

            if !store.archived.isEmpty {
                Section {
                    Button {
                        withAnimation(Motion.snappy) { showArchived.toggle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.fg4)
                                .rotationEffect(.degrees(showArchived ? 90 : 0))
                            Text(InboxText.count(store.archived.count, "archived label", "archived labels"))
                                .font(ODFont.sans(14.5, weight: .medium))
                                .foregroundStyle(Theme.fg2)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .inboxListRow()
                    if showArchived {
                        ForEach(store.archived.filter(matches)) { label in row(label) }
                    }
                }
            }

            if canEdit { creationSection }
        }
        .inboxListStyle()
        .environment(\.editMode, $editMode)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter labels")
        .refreshable { await store.reload() }
        .motion(Motion.snappy, value: store.labels.map(\.id))
    }

    private var summary: [InboxStatStrip.Item] {
        [
            .init(label: "Labels", value: "\(store.active.count)"),
            .init(label: "Groups", value: "\(store.groups.count)"),
            .init(label: "On tickets", value: store.active.reduce(0) { $0 + ($1.usage?.tickets ?? 0) }.formatted()),
            .init(label: "Archived", value: "\(store.archived.count)"),
        ]
    }

    @ViewBuilder
    private func header(_ group: SettingsLabelGroup?, count: Int) -> some View {
        HStack(spacing: 7) {
            if let group {
                if let color = group.color {
                    RoundedRectangle(cornerRadius: 2).fill(color.solid).frame(width: 8, height: 8)
                }
                Text(group.name).font(ODFont.sans(12.5, weight: .semibold)).foregroundStyle(Theme.fg2)
                if group.exclusive {
                    Text("One at a time")
                        .font(ODFont.sans(10.5, weight: .medium))
                        .foregroundStyle(Theme.fg3)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
                        .accessibilityHint("A record holds one label from this group at a time.")
                }
                Text("\(count)").font(ODFont.mono(11)).foregroundStyle(Theme.fg4)
                Spacer()
                if canEdit {
                    Menu {
                        Button { editing = LabelEdit(label: nil, group: group.id) } label: { Label("Add a label", systemImage: "plus") }
                        Button { groupEditing = GroupEdit(group: group) } label: { Label("Edit group", systemImage: "pencil") }
                        Divider()
                        Button(role: .destructive) { askDeleteGroup(group) } label: { Label("Delete group", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.fg3)
                            .frame(width: 32, height: 24)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Actions for group \(group.name)")
                }
            } else {
                Text(store.groups.isEmpty ? InboxText.count(count, "label", "labels") : "Other labels")
                    .font(ODFont.sans(12.5, weight: .semibold))
                    .foregroundStyle(Theme.fg2)
                Spacer()
            }
        }
        .textCase(nil)
        .padding(.horizontal, 4)
    }

    private func row(_ label: SettingsLabel) -> some View {
        Button {
            if canEdit { editing = LabelEdit(label: label) }
        } label: {
            LabelRow(label: label)
        }
        .buttonStyle(RowPressStyle())
        .inboxListRow()
        .contextMenu { if canEdit { menu(label) } }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canEdit {
                Button(role: .destructive) { askDelete(label) } label: { Label("Delete", systemImage: "trash") }
                Button { setArchived(label, !label.archived) } label: {
                    Label(label.archived ? "Restore" : "Archive", systemImage: label.archived ? "arrow.uturn.backward" : "archivebox")
                }
                .tint(Tone.gray.solid)
            }
        }
        .accessibilityHint(canEdit ? "Edit \(label.name)" : "")
    }

    @ViewBuilder
    private func menu(_ label: SettingsLabel) -> some View {
        Button { editing = LabelEdit(label: label) } label: { Label("Edit", systemImage: "pencil") }
        Menu {
            ForEach(LabelPalette.tones, id: \.self) { tone in
                Button {
                    recolor(label, tone)
                } label: {
                    if tone == label.color { Label(tone.rawValue.capitalized, systemImage: "checkmark") } else { Text(tone.rawValue.capitalized) }
                }
            }
        } label: {
            Label("Colour", systemImage: "paintpalette")
        }
        if !store.groups.isEmpty {
            Menu {
                Button("No group") { move(label, to: nil) }
                ForEach(store.groups) { group in
                    Button(group.name) { move(label, to: group.id) }
                }
            } label: {
                Label("Move to group", systemImage: "folder")
            }
        }
        Button { merging = label } label: { Label("Merge into another label", systemImage: "arrow.triangle.merge") }
        Button { setArchived(label, !label.archived) } label: {
            Label(label.archived ? "Restore" : "Archive", systemImage: label.archived ? "arrow.uturn.backward" : "archivebox")
        }
        Divider()
        Button(role: .destructive) { askDelete(label) } label: { Label("Delete", systemImage: "trash") }
    }

    private var creationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Who can create labels").font(ODFont.sans(15)).foregroundStyle(Theme.fg)
                AccountSegmented(
                    options: ["anyone", "admins"],
                    selection: Binding(get: { store.creation }, set: { value in setCreation(value) }),
                    label: { $0 == "admins" ? "Admins only" : "Anyone" }
                )
                Text(store.creation == "admins"
                    ? "Agents pick from existing labels. Only admins create new ones."
                    : "Typing a new name in a label picker creates the label.")
                    .font(ODFont.footnote)
                    .foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .inboxListRow()
        } header: {
            InboxListHeader(title: "Creating labels")
        }
    }

    // MARK: Actions

    private func move(_ rows: [SettingsLabel], from: IndexSet, to: Int) {
        var ids = rows.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        guard ids != rows.map(\.id) else { return }
        Task {
            do { try await store.reorder(ids) } catch { env.toasts.error(error) }
        }
    }

    private func setArchived(_ label: SettingsLabel, _ value: Bool) {
        Task {
            do {
                try await store.patch(label, ["archived": .bool(value)]) { $0.archived = value }
                env.toasts.show(value ? "\u{201C}\(label.name)\u{201D} archived" : "\u{201C}\(label.name)\u{201D} restored", kind: .success)
            } catch {
                env.toasts.error(error)
            }
        }
    }

    private func recolor(_ label: SettingsLabel, _ tone: Tone) {
        Task {
            do { try await store.patch(label, ["color": .string(tone.rawValue)]) { $0.color = tone } } catch { env.toasts.error(error) }
        }
    }

    private func move(_ label: SettingsLabel, to group: String?) {
        Task {
            do { try await store.patch(label, ["group_id": group.map(JSONValue.string) ?? .null]) { $0.groupID = group } } catch { env.toasts.error(error) }
        }
    }

    private func setCreation(_ value: String) {
        Task {
            do {
                try await store.setCreation(value)
                env.toasts.show("Label setting saved", kind: .success)
            } catch {
                env.toasts.error(error)
            }
        }
    }

    private func askDelete(_ label: SettingsLabel) {
        confirm = AccountConfirm(
            title: "Delete this label?",
            message: "\u{201C}\(label.name)\u{201D} will be removed from every ticket, contact and company that has it. This can't be undone.",
            confirmTitle: "Delete label"
        ) {
            do {
                try await store.delete(label)
                Haptics.success()
            } catch {
                env.toasts.error(error)
            }
        }
    }

    private func askDeleteGroup(_ group: SettingsLabelGroup) {
        confirm = AccountConfirm(
            title: "Delete this group?",
            message: "The labels in \(group.name) stay and move to Other labels.",
            confirmTitle: "Delete group"
        ) {
            do {
                try await store.deleteGroup(group)
                Haptics.success()
            } catch {
                env.toasts.error(error)
            }
        }
    }

    struct LabelEdit: Identifiable {
        let id = UUID()
        var label: SettingsLabel?
        var group: String?
    }

    struct GroupEdit: Identifiable {
        let id = UUID()
        var group: SettingsLabelGroup?
    }

    /// Labels have no page of their own: a link to one opens the list.
    struct Detail: View {
        let id: String

        var body: some View {
            LabelsSettings()
        }
    }
}

/// One label: its chip, description, where it applies and how often it's used.
private struct LabelRow: View {
    let label: SettingsLabel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                InboxTagChip(name: label.name, tone: label.color)
                if !label.description.isEmpty {
                    Text(label.description)
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(LabelScope.allCases, id: \.self) { scope in
                    Image(systemName: scope.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.fg3)
                        .opacity(label.appliesTo.contains(scope) ? 1 : 0.22)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("For " + label.appliesTo.map { $0.title.lowercased() }.joined(separator: ", "))
            Text((label.usage?.total ?? 0).formatted())
                .font(ODFont.mono(12))
                .foregroundStyle(Theme.fg3)
                .monospacedDigit()
                .frame(minWidth: 30, alignment: .trailing)
                .accessibilityLabel(label.usage.map { "\($0.tickets) tickets, \($0.contacts) contacts, \($0.companies) companies" } ?? "Not used")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 50)
        .opacity(label.archived ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}
