import SwiftUI

/// Create or edit a custom field: name, key (fixed after create), type (fixed after create),
/// options with colours, description and, on tickets, required to solve.
struct CustomFieldEditorSheet: View {
    let store: CustomFieldsStore
    let field: CustomField?
    let entity: FieldEntity

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var key = ""
    @State private var keyTouched = false
    @State private var type: CustomField.Kind = .text
    @State private var options: [CustomFieldsStore.DraftOption] = []
    @State private var description = ""
    @State private var required = false
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    private var isNew: Bool { field == nil }

    private var keyProblem: String? {
        guard isNew, !key.isEmpty else { return nil }
        if !FieldSlug.keyValid(key) { return "Start with a letter; use lowercase letters, numbers and _." }
        if store.fields.contains(where: { $0.entity == entity.rawValue && $0.key == key }) { return "Another field already uses this key." }
        return nil
    }

    private var namedOptions: [CustomFieldsStore.DraftOption] {
        options.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AccountSheetHeader(
                    title: isNew ? "New \(entity.title.lowercased()) field" : "Edit field",
                    subtitle: isNew ? "Agents fill it in from the record's sidebar." : "The key and type stay fixed so stored values keep working."
                ) { dismiss() }

                ODTextField(label: "Name", text: $name, prompt: "Plan tier", submitLabel: .done)

                VStack(alignment: .leading, spacing: 6) {
                    if isNew {
                        ODTextField(label: "Key", text: Binding(get: { key }, set: { key = $0.lowercased(); keyTouched = true }), prompt: "plan_tier", submitLabel: .done)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ODFont.mono(14))
                    } else {
                        Text("Key").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                        HStack {
                            Text(key).font(ODFont.mono(14)).foregroundStyle(Theme.fg3)
                            Spacer()
                            Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(Theme.fg4)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 42)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    if let keyProblem {
                        FormError(text: keyProblem)
                    } else {
                        Text(isNew ? "Used by the API, filters and automations." : "Keys can't change.")
                            .font(ODFont.footnote)
                            .foregroundStyle(Theme.fg3)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
                    if isNew {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(CustomField.Kind.ordered, id: \.self) { kind in typeTile(kind) }
                        }
                    } else {
                        HStack(spacing: 10) {
                            AccountIconTile(symbol: type.symbol, tone: type.kindTone, size: 26)
                            Text(type.kindTitle).font(ODFont.sans(14.5)).foregroundStyle(Theme.fg)
                            Spacer()
                            Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(Theme.fg4)
                        }
                        Text("The type can't change after a field is created.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                    }
                }

                if type.takesOptions { optionsEditor }

                VStack(alignment: .leading, spacing: 6) {
                    AccountTextEditor(label: "Description", text: $description, prompt: "", minHeight: 64)
                    Text("Shown to agents next to the field.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                }

                if entity == .ticket {
                    InboxSwitchBox(title: "Required to solve", hint: "A ticket can't be solved or closed while this field is empty.", isOn: $required)
                }

                FormError(text: error)
                Button(action: save) { ButtonLabel(title: isNew ? "Create field" : "Save field", busy: saving) }
                    .buttonStyle(InkButtonStyle())
                    .disabled(saving || keyProblem != nil)
            }
            .padding(22)
            .motion(Motion.snappy, value: error)
            .motion(Motion.snappy, value: type)
            .motion(Motion.snappy, value: options.map(\.id))
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.surface)
        .onAppear(perform: fill)
        .onChange(of: name) { _, value in
            if value.count > 60 { name = String(value.prefix(60)) }
            if isNew && !keyTouched { key = FieldSlug.key(value) }
            error = nil
        }
    }

    private func typeTile(_ kind: CustomField.Kind) -> some View {
        let on = type == kind
        return Button {
            Haptics.selection()
            type = kind
            if kind.takesOptions && options.isEmpty { addOption() }
        } label: {
            HStack(spacing: 8) {
                AccountIconTile(symbol: kind.symbol, tone: kind.kindTone, size: 24)
                Text(kind.kindTitle).font(ODFont.sans(13.5, weight: on ? .medium : .regular)).foregroundStyle(on ? Theme.fg : Theme.fg2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
            .background(on ? Theme.sunken : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(on ? Theme.fg : Theme.line, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(TapScaleStyle())
        .accessibilityLabel(kind.kindTitle)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var optionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options").font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            VStack(spacing: 6) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    optionRow(index: index, option: option)
                }
            }
            Button(action: addOption) {
                Label("Add option", systemImage: "plus")
                    .font(ODFont.sans(13.5, weight: .medium))
                    .foregroundStyle(Theme.fg2)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            if !isNew {
                Text("Removing an option clears it from records that have it.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
            }
        }
    }

    private func optionRow(index: Int, option: CustomFieldsStore.DraftOption) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(LabelPalette.tones, id: \.self) { tone in
                    Button {
                        options[index].color = tone
                    } label: {
                        if tone == option.color {
                            Label(tone.rawValue.capitalized, systemImage: "checkmark")
                        } else {
                            Text(tone.rawValue.capitalized)
                        }
                    }
                }
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(option.color.solid)
                    .frame(width: 18, height: 18)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Colour for \(option.label.isEmpty ? "option \(index + 1)" : option.label)")

            TextField("Option name", text: Binding(get: { options.indices.contains(index) ? options[index].label : "" }, set: { if options.indices.contains(index) { options[index].label = String($0.prefix(60)) } }))
                .font(ODFont.sans(14.5))
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityLabel("Option \(index + 1)")

            Menu {
                Button { move(index, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(index == 0)
                Button { move(index, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(index == options.count - 1)
                Divider()
                Button(role: .destructive) { options.remove(at: index) } label: { Label("Remove option", systemImage: "minus.circle") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.fg3)
                    .frame(width: 34, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Option actions")
        }
    }

    private func addOption() {
        let tone = LabelPalette.tones.filter { $0 != .gray }
        let next = tone.isEmpty ? Tone.gray : tone[options.count % tone.count]
        options.append(.init(optionID: "", label: "", color: next))
    }

    private func move(_ index: Int, by step: Int) {
        let target = index + step
        guard options.indices.contains(index), options.indices.contains(target) else { return }
        options.swapAt(index, target)
    }

    private func fill() {
        guard !loaded else { return }
        loaded = true
        guard let field else { return }
        name = field.name
        key = field.key
        keyTouched = true
        type = field.type
        options = field.options.map { .init(optionID: $0.id, label: $0.label, color: Tone(label: $0.color)) }
        description = field.description
        required = field.requiredOnSolve
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Give the field a name."; return }
        if isNew && !FieldSlug.keyValid(key) { error = "Start with a letter; use lowercase letters, numbers and _."; return }
        if let keyProblem { error = keyProblem; return }
        if type.takesOptions && namedOptions.isEmpty { error = "Add at least one option."; return }
        saving = true
        error = nil
        Task {
            do {
                try await store.save(entity: entity, existing: field, key: key, name: trimmed, type: type, options: options, required: required, description: description)
                Haptics.success()
                env.toasts.show(isNew ? "Field created" : "Field saved", kind: .success)
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.userMessage
            }
            saving = false
        }
    }
}
