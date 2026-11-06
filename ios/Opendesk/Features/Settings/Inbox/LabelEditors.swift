import SwiftUI

/// Create or edit a label: name with a live chip, colour, description, group and where it applies.
struct LabelEditorSheet: View {
    let store: LabelsStore
    let label: SettingsLabel?
    var defaultGroup: String?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LabelsStore.Draft()
    @State private var saving = false
    @State private var error: String?

    private var duplicate: Bool {
        let name = draft.trimmed.lowercased()
        return !name.isEmpty && store.labels.contains { $0.id != label?.id && $0.name.lowercased() == name }
    }

    private var nameProblem: String? {
        if duplicate { return "A label with this name already exists." }
        if !draft.trimmed.isEmpty && draft.hasBadCharacters { return "Use letters, numbers, spaces and - _ . / : & + #." }
        return nil
    }

    private var shownColor: Tone { draft.color ?? LabelPalette.tone(for: draft.trimmed.isEmpty ? "label" : draft.trimmed) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(
                    title: label == nil ? "New label" : "Edit label",
                    subtitle: label == nil ? "Agents can add it to tickets right away." : nil
                ) { dismiss() }

                VStack(alignment: .leading, spacing: 8) {
                    ODTextField(label: "Name", text: $draft.name, prompt: "billing", submitLabel: .done)
                    HStack(spacing: 8) {
                        Text("Preview").font(ODFont.footnote).foregroundStyle(Theme.fg4)
                        InboxTagChip(name: draft.trimmed.isEmpty ? "Preview" : draft.trimmed, tone: shownColor, muted: draft.trimmed.isEmpty)
                    }
                    FormError(text: nameProblem)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    InboxToneGrid(selection: Binding<Tone?>(get: { shownColor }, set: { draft.color = $0 }))
                }

                VStack(alignment: .leading, spacing: 6) {
                    AccountTextEditor(label: "Description", text: $draft.description, prompt: "Questions about invoices, refunds and payment methods", minHeight: 80)
                    Text("Optional. Shown in pickers so everyone uses the label the same way.")
                        .font(ODFont.footnote)
                        .foregroundStyle(Theme.fg3)
                }

                if !store.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        InboxMenuField(
                            label: "Group",
                            value: store.group(draft.groupID)?.name ?? "No group",
                            tone: store.group(draft.groupID)?.color
                        ) {
                            Button("No group") { draft.groupID = nil }
                            ForEach(store.groups) { group in
                                Button(group.name) { draft.groupID = group.id }
                            }
                        }
                        if store.group(draft.groupID)?.exclusive == true {
                            Text("A record holds one label from this group at a time.")
                                .font(ODFont.footnote)
                                .foregroundStyle(Theme.fg3)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Applies to").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    HStack(spacing: 8) {
                        ForEach(LabelScope.allCases, id: \.self) { scope in scopeToggle(scope) }
                    }
                }

                FormError(text: error)
                Button(action: save) { ButtonLabel(title: label == nil ? "Create label" : "Save label", busy: saving) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(draft.trimmed.isEmpty || nameProblem != nil || draft.scopes.isEmpty || saving)
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
            .motion(Motion.snappy, value: nameProblem)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .onAppear {
            draft = label.map(LabelsStore.Draft.init) ?? LabelsStore.Draft(defaultGroup: defaultGroup)
        }
        .onChange(of: draft.name) { _, value in
            if value.count > 50 { draft.name = String(value.prefix(50)) }
            error = nil
        }
        .onChange(of: draft.description) { _, value in
            if value.count > 300 { draft.description = String(value.prefix(300)) }
        }
    }

    private func scopeToggle(_ scope: LabelScope) -> some View {
        let on = draft.scopes.contains(scope)
        return Button {
            Haptics.selection()
            if on { draft.scopes.remove(scope) } else { draft.scopes.insert(scope) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? Theme.fg : Theme.fg4)
                Image(systemName: scope.symbol).font(.system(size: 12)).foregroundStyle(Theme.fg3)
                Text(scope.title).font(ODFont.sans(13.5)).foregroundStyle(on ? Theme.fg : Theme.fg3).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(on ? Theme.sunken : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(on ? Theme.lineStrong : Theme.line, lineWidth: 1))
        }
        .buttonStyle(TapScaleStyle())
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        guard !draft.trimmed.isEmpty else { error = "Give the label a name."; return }
        if let nameProblem { error = nameProblem; return }
        guard !draft.scopes.isEmpty else { error = "Choose where the label can be used."; return }
        saving = true
        error = nil
        Task {
            do {
                let saved = try await store.save(draft, existing: label)
                Haptics.success()
                env.toasts.show(label == nil ? "Label \u{201C}\(saved.name)\u{201D} created" : "Label saved", kind: .success)
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
            saving = false
        }
    }
}

/// Create or edit a label group.
struct LabelGroupEditorSheet: View {
    let store: LabelsStore
    let group: SettingsLabelGroup?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LabelsStore.GroupDraft()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(
                    title: group == nil ? "New group" : "Edit group",
                    subtitle: "Groups keep related labels together, like Type or Plan."
                ) { dismiss() }
                ODTextField(label: "Name", text: $draft.name, prompt: "Type", submitLabel: .done)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colour (optional)").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    InboxToneGrid(selection: $draft.color, allowsNone: true)
                }
                InboxSwitchBox(title: "One label at a time", hint: "A record holds one label from this group at a time.", isOn: $draft.exclusive)
                FormError(text: error)
                Button(action: save) { ButtonLabel(title: group == nil ? "Create group" : "Save group", busy: saving) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(saving)
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .onAppear { if let group { draft = LabelsStore.GroupDraft(group) } }
        .onChange(of: draft.name) { _, value in
            if value.count > 50 { draft.name = String(value.prefix(50)) }
            error = nil
        }
    }

    private func save() {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Give the group a name."
            return
        }
        saving = true
        Task {
            do {
                try await store.saveGroup(draft, existing: group)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
            saving = false
        }
    }
}

/// Merge one label into another: everything labelled with it gets the other instead.
struct LabelMergeSheet: View {
    let store: LabelsStore
    let label: SettingsLabel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var into: String?
    @State private var busy = false
    @State private var error: String?

    private var options: [InboxOption] {
        store.labels.filter { $0.id != label.id && !$0.archived }.map { InboxOption(value: $0.id, label: $0.name, tone: $0.color) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AccountSheetHeader(
                title: "Merge label",
                subtitle: "Everything labelled \(label.name) gets the label you choose instead, and \(label.name) is deleted."
            ) { dismiss() }
            HStack(spacing: 10) {
                InboxTagChip(name: label.name, tone: label.color)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.fg4)
                Spacer(minLength: 0)
            }
            InboxPickerField(label: "Merge into", title: "Choose a label", options: options, value: into, placeholder: "Choose a label") { into = $0 }
            FormError(text: error)
            Spacer(minLength: 0)
            Button(action: merge) { ButtonLabel(title: "Merge", busy: busy) }
                .buttonStyle(AccountDangerButtonStyle())
                .disabled(into == nil || busy)
                .opacity(into == nil ? 0.5 : 1)
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
    }

    private func merge() {
        guard let into else { return }
        busy = true
        error = nil
        Task {
            do {
                try await store.merge(label, into: into)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
            busy = false
        }
    }
}
