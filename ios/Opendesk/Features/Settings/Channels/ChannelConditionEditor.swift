import SwiftUI

/// What a condition field accepts: free text, one of a list, a number, or a question for Ollie.
enum ChannelConditionValue: Equatable {
    case text(String)
    case choice([ChannelChoice])
    /// A choice that also takes a typed value (an address).
    case choiceOrText([ChannelChoice], String)
    case number
    case ollie
}

struct ChannelChoice: Hashable, Identifiable {
    var value: String
    var label: String
    var group: String?
    var id: String { value }
}

/// One field a condition can test.
struct ChannelConditionField: Identifiable, Equatable {
    var key: String
    var label: String
    var group: String
    var ops: [String]
    var value: ChannelConditionValue
    var id: String { key }

    /// The value a fresh condition on this field starts with.
    var initial: ChannelCondition {
        switch key {
        case "channel": ChannelCondition(field: key, op: ops[0], value: "email")
        case "ai_decide": ChannelCondition(field: key, op: "gt", value: "0.8", question: "")
        default: ChannelCondition(field: key, op: ops[0], value: "")
        }
    }
}

enum ChannelConditionOps {
    static func label(_ op: String, field: String) -> String {
        if field == "ai_decide" { return op == "gt" ? "yes, at least" : "no, below" }
        switch op {
        case "equals": return "is"
        case "not_equals": return "is not"
        case "contains": return "contains"
        case "not_contains": return "doesn't contain"
        case "starts_with": return "starts with"
        case "gt": return "is more than"
        case "lt": return "is less than"
        default: return op
        }
    }
}

/// A list of conditions, each a field, an operator and a value.
struct ChannelConditionsEditor: View {
    @Binding var conditions: [ChannelCondition]
    let fields: [ChannelConditionField]
    /// "and" or "or" between rows; nil shows no joining word.
    var joiner: String?
    var max = 10
    var minimum = 0
    var disabled = false
    var addLabel = "Add condition"
    var newField = "subject"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($conditions) { $condition in
                let first = conditions.first?.id == condition.id
                let id = condition.id
                ChannelConditionRow(
                    condition: $condition,
                    fields: fields,
                    prefix: joiner.map { first ? "If" : $0 },
                    removable: conditions.count > minimum && !disabled
                ) {
                    conditions.removeAll { $0.id == id }
                    Haptics.tap()
                }
                .disabled(disabled)
            }
            if !disabled {
                HStack {
                    Button {
                        let field = fields.first { $0.key == newField } ?? fields[0]
                        conditions.append(field.initial)
                        Haptics.tap()
                    } label: {
                        Label(addLabel, systemImage: "plus").font(ODFont.sans(14, weight: .medium))
                    }
                    .disabled(conditions.count >= max)
                    Spacer()
                    Text("\(conditions.count) of \(max)").font(ODFont.mono(12)).foregroundStyle(Theme.fg3)
                }
                .foregroundStyle(Theme.fg)
            }
        }
    }
}

private struct ChannelConditionRow: View {
    @Binding var condition: ChannelCondition
    let fields: [ChannelConditionField]
    var prefix: String?
    var removable: Bool
    let remove: () -> Void

    private var field: ChannelConditionField? { fields.first { $0.key == condition.field } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let prefix {
                    Text(prefix).font(ODFont.sans(13, weight: .semibold)).foregroundStyle(Theme.fg3).frame(width: 22, alignment: .leading)
                }
                Menu {
                    ForEach(groups, id: \.self) { group in
                        Section(group) {
                            ForEach(fields.filter { $0.group == group }) { option in
                                Button(option.label) {
                                    var next = option.initial
                                    next.id = condition.id
                                    condition = next
                                }
                            }
                        }
                    }
                } label: {
                    pill(field?.label ?? "Field", strong: true)
                }
                if let field, field.ops.count > 1 {
                    Menu {
                        ForEach(field.ops, id: \.self) { op in
                            Button(ChannelConditionOps.label(op, field: field.key)) { condition.op = op }
                        }
                    } label: {
                        pill(ChannelConditionOps.label(condition.op, field: field.key), strong: false)
                    }
                } else if let field {
                    Text(ChannelConditionOps.label(condition.op, field: field.key)).font(ODFont.sans(13.5)).foregroundStyle(Theme.fg2)
                }
                Spacer(minLength: 0)
                if removable {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.fg3).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove condition")
                }
            }
            value
        }
        .padding(10)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var groups: [String] {
        var seen: [String] = []
        for field in fields where !seen.contains(field.group) { seen.append(field.group) }
        return seen
    }

    @ViewBuilder
    private var value: some View {
        switch field?.value {
        case let .text(prompt):
            input(prompt, keyboard: condition.field.contains("email") || condition.field == "received_at" ? .emailAddress : .default)
        case .number:
            input("100", keyboard: .decimalPad)
        case let .choice(choices):
            choiceMenu(choices)
        case let .choiceOrText(choices, prompt):
            if condition.op == "equals" || condition.op == "not_equals" {
                choiceMenu(choices)
                input("Or type an address", keyboard: .emailAddress)
            } else {
                input(prompt, keyboard: .emailAddress)
            }
        case .ollie:
            VStack(alignment: .leading, spacing: 8) {
                Menu {
                    ForEach([0.5, 0.6, 0.7, 0.8, 0.9, 0.95], id: \.self) { level in
                        Button("\(Int(level * 100))% sure") { condition.value = String(level) }
                    }
                } label: {
                    pill("\(Int((Double(condition.value) ?? 0.8) * 100))% sure", strong: false)
                }
                TextField(text: Binding(get: { condition.question ?? "" }, set: { condition.question = String($0.prefix(300)) }), axis: .vertical) {
                    Text("Is this a question about a contract?").foregroundStyle(Theme.fg4)
                }
                .font(ODFont.sans(15))
                .lineLimit(1 ... 4)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous))
                .accessibilityLabel("Question for Ollie")
            }
        case nil:
            input("Text", keyboard: .default)
        }
    }

    private func choiceMenu(_ choices: [ChannelChoice]) -> some View {
        Menu {
            let groups = choices.reduce(into: [String]()) { out, choice in
                if let group = choice.group, !out.contains(group) { out.append(group) }
            }
            if groups.isEmpty {
                ForEach(choices) { choice in Button(choice.label) { condition.value = choice.value } }
            } else {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(choices.filter { $0.group == group }) { choice in Button(choice.label) { condition.value = choice.value } }
                    }
                }
            }
        } label: {
            HStack {
                Text(choices.first { $0.value == condition.value }?.label ?? (condition.value.isEmpty ? "Choose" : condition.value))
                    .font(ODFont.sans(15))
                    .foregroundStyle(condition.value.isEmpty ? Theme.fg4 : Theme.fg)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.fg3)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous))
        }
    }

    private func input(_ prompt: String, keyboard: UIKeyboardType) -> some View {
        TextField(text: $condition.value) { Text(prompt).foregroundStyle(Theme.fg4) }
            .font(keyboard == .emailAddress ? ODFont.mono(14) : ODFont.sans(15))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous))
    }

    private func pill(_ text: String, strong: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).font(ODFont.sans(13.5, weight: strong ? .medium : .regular)).foregroundStyle(strong ? Theme.fg : Theme.fg2).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.fg4)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control - 3, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
