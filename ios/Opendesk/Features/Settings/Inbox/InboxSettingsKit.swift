import SwiftUI

// Pieces the Inbox settings pages share, on top of the Account kit and the settings kit.

// MARK: - Loading

/// A page's first load: still loading, failed with nothing to show, or ready.
enum InboxLoad: Equatable {
    case loading
    case failed(String)
    case ready
}

/// The standard body of a page while its first load runs or after it failed.
struct InboxLoadGate<Content: View>: View {
    let load: InboxLoad
    var rows = 5
    let retry: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch load {
        case .loading:
            ScrollView { Panel { SkeletonRows(count: rows) }.padding(16) }
                .background(Theme.chrome.ignoresSafeArea())
        case let .failed(message):
            ErrorState(message: message) { Task { await retry() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.chrome.ignoresSafeArea())
        case .ready:
            content()
        }
    }
}

// MARK: - Summary

/// A row of small figures above a list (the web's summary strip).
struct InboxStatStrip: View {
    struct Item: Identifiable {
        var label: String
        var value: String
        var tone: Tone?
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if let tone = item.tone { Circle().fill(tone.solid).frame(width: 6, height: 6) }
                            Text(item.label)
                                .font(ODFont.sans(11.5, weight: .medium))
                                .foregroundStyle(Theme.fg3)
                                .lineLimit(1)
                        }
                        Text(item.value)
                            .font(ODFont.mono(17, weight: .medium))
                            .foregroundStyle(Theme.fg)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minWidth: 92, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Colour

/// The label palette as a grid of swatches; `allowsNone` adds a "no colour" swatch first.
struct InboxToneGrid: View {
    @Binding var selection: Tone?
    var allowsNone = false
    var disabled = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
            if allowsNone { swatch(nil) }
            ForEach(LabelPalette.tones, id: \.self) { tone in swatch(tone) }
        }
        .disabled(disabled)
    }

    private func swatch(_ tone: Tone?) -> some View {
        let on = selection == tone
        return Button {
            Haptics.selection()
            selection = tone
        } label: {
            ZStack {
                if let tone {
                    Circle().fill(tone.solid)
                } else {
                    Circle().strokeBorder(Theme.lineStrong, lineWidth: 1.5)
                    Image(systemName: "slash.circle").font(.system(size: 13)).foregroundStyle(Theme.fg3)
                }
            }
            .frame(width: 26, height: 26)
            .padding(3)
            .overlay(Circle().strokeBorder(on ? Theme.fg : Color.clear, lineWidth: 2))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(TapScaleStyle(scale: 0.9))
        .accessibilityLabel(tone?.rawValue.capitalized ?? "No colour")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A label as the web draws it: a soft chip in its colour with a dot.
struct InboxTagChip: View {
    let name: String
    let tone: Tone
    var muted = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.solid).frame(width: 7, height: 7)
            Text(name).font(ODFont.sans(12.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(tone == .gray ? Theme.fg2 : tone.text)
        .padding(.horizontal, 8)
        .frame(height: 23)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous).strokeBorder(tone.line, lineWidth: 1))
        .opacity(muted ? 0.6 : 1)
    }
}

// MARK: - Inputs

/// A number with minus and plus buttons, in the app's style (never a system spinner).
struct InboxStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var suffix: String?
    var disabled = false
    var label = "Value"

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
            HStack(spacing: 4) {
                Text("\(value)")
                    .font(ODFont.mono(14.5, weight: .medium))
                    .foregroundStyle(Theme.fg)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                if let suffix {
                    Text(suffix).font(ODFont.sans(13)).foregroundStyle(Theme.fg3)
                }
            }
            .frame(minWidth: 64)
            button("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .frame(height: 34)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control - 2, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .motion(Motion.snappy, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)\(suffix.map { " " + $0 } ?? "")")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Theme.fg2 : Theme.fg4)
                .frame(width: 36, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// A form row that opens a menu of choices: a label over a field-styled button.
struct InboxMenuField<Items: View>: View {
    let label: String
    let value: String
    var symbol: String?
    var tone: Tone?
    var placeholder = false
    var disabled = false
    @ViewBuilder var items: () -> Items

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label).font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            }
            Menu {
                items()
            } label: {
                InboxFieldBox(value: value, symbol: symbol, tone: tone, placeholder: placeholder, chevron: "chevron.up.chevron.down")
            }
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1)
        }
    }
}

/// The look of a picker field: a value on a white box with a hairline and a chevron.
struct InboxFieldBox: View {
    let value: String
    var symbol: String?
    var tone: Tone?
    var placeholder = false
    var chevron = "chevron.right"

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tone.map { $0 == .gray ? Theme.fg3 : $0.text } ?? Theme.fg3)
                    .frame(width: 18)
            } else if let tone {
                Circle().fill(tone.solid).frame(width: 8, height: 8)
            }
            Text(value)
                .font(ODFont.sans(15.5))
                .foregroundStyle(placeholder ? Theme.fg4 : Theme.fg)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: chevron).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.fg3)
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// A switch with a title and a line of help in a bordered box, for editor sheets.
struct InboxSwitchBox: View {
    let title: String
    var hint: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(ODFont.sans(14.5, weight: .medium)).foregroundStyle(Theme.fg)
                if let hint {
                    Text(hint).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn).labelsHidden().tint(Tone.green.solid)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

// MARK: - Option picker

/// One choice in an `InboxOptionSheet`.
struct InboxOption: Identifiable, Hashable {
    var value: String
    var label: String
    var hint: String?
    var symbol: String?
    var tone: Tone?
    var group: String?
    var keywords: [String] = []

    var id: String { value }

    func matches(_ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return true }
        return label.lowercased().contains(text) || (hint?.lowercased().contains(text) ?? false) || keywords.contains { $0.lowercased().contains(text) }
    }
}

/// A searchable list of choices in a sheet. Single choice picks and closes; several choices
/// are confirmed with Done. `createTitle` adds a row that makes a new value from the search text.
struct InboxOptionSheet: View {
    let title: String
    let options: [InboxOption]
    var multiple = false
    var selected: Set<String> = []
    var prompt = "Search"
    var emptyText = "Nothing matches."
    var createTitle: ((String) -> String)?
    var onCreate: ((String) -> Void)?
    let onPick: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: Set<String> = []

    private var shown: [InboxOption] { options.filter { $0.matches(query) } }

    private var groups: [(name: String?, options: [InboxOption])] {
        var out: [(name: String?, options: [InboxOption])] = []
        for option in shown {
            if let index = out.firstIndex(where: { $0.name == option.group }) {
                out[index].options.append(option)
            } else {
                out.append((option.group, [option]))
            }
        }
        return out
    }

    private var creatable: String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard onCreate != nil, !text.isEmpty, !options.contains(where: { $0.label.caseInsensitiveCompare(text) == .orderedSame }) else { return nil }
        return text
    }

    var body: some View {
        PickerSheet(title: title, query: $query, prompt: prompt, trailing: multiple ? ("Done", { onPick(Array(chosen)); dismiss() }) : nil) {
            VStack(alignment: .leading, spacing: 12) {
                if let text = creatable, let createTitle {
                    Panel {
                        Button {
                            Haptics.tap()
                            onCreate?(text)
                            dismiss()
                        } label: {
                            PanelRow(title: createTitle(text), symbol: "plus")
                        }
                        .buttonStyle(RowPressStyle())
                    }
                }
                if shown.isEmpty && creatable == nil {
                    Text(emptyText)
                        .font(ODFont.callout)
                        .foregroundStyle(Theme.fg3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 8) {
                        if let name = group.name { SectionLabel(name).padding(.horizontal, 4) }
                        Panel {
                            ForEach(Array(group.options.enumerated()), id: \.element.id) { index, option in
                                if index > 0 { Hairline(inset: 48) }
                                row(option)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { chosen = selected }
    }

    private func row(_ option: InboxOption) -> some View {
        let on = chosen.contains(option.value)
        return Button {
            Haptics.selection()
            if multiple {
                if on { chosen.remove(option.value) } else { chosen.insert(option.value) }
            } else {
                onPick([option.value])
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let symbol = option.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(option.tone.map { $0 == .gray ? Theme.fg2 : $0.text } ?? Theme.fg2)
                    } else if let tone = option.tone {
                        Circle().fill(tone.solid).frame(width: 9, height: 9)
                    }
                }
                .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(ODFont.sans(15)).foregroundStyle(Theme.fg).lineLimit(1)
                    if let hint = option.hint, !hint.isEmpty {
                        Text(hint).font(ODFont.footnote).foregroundStyle(Theme.fg3).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: multiple ? (on ? "checkmark.square.fill" : "square") : "checkmark")
                    .font(.system(size: multiple ? 17 : 13, weight: .semibold))
                    .foregroundStyle(multiple ? (on ? Theme.fg : Theme.fg4) : Theme.fg)
                    .opacity(multiple || on ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Opens an `InboxOptionSheet` from a field-styled button.
struct InboxPickerField: View {
    let label: String
    let title: String
    let options: [InboxOption]
    let value: String?
    var placeholder = "Choose"
    var invalid = false
    var disabled = false
    var createTitle: ((String) -> String)?
    let onPick: (String) -> Void

    @State private var open = false

    private var current: InboxOption? { options.first { $0.value == value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label).font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg2)
            }
            Button {
                open = true
            } label: {
                InboxFieldBox(
                    value: current?.label ?? (value?.isEmpty == false ? value! : placeholder),
                    symbol: current?.symbol,
                    tone: current?.tone,
                    placeholder: current == nil && (value ?? "").isEmpty
                )
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(invalid ? Tone.red.solid.opacity(0.6) : .clear, lineWidth: 1))
            }
            .buttonStyle(TapScaleStyle(scale: 0.99))
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1)
        }
        .sheet(isPresented: $open) {
            InboxOptionSheet(
                title: title,
                options: options,
                selected: value.map { [$0] } ?? [],
                createTitle: createTitle,
                onCreate: createTitle == nil ? nil : { onPick($0) },
                onPick: { if let first = $0.first { onPick(first) } }
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(Theme.Radius.sheet)
        }
    }
}

// MARK: - Rows and links

extension View {
    /// A row in one of the group's lists: no system insets, the white panel behind it.
    func inboxListRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.lineSoft)
    }

    /// The group's list style: inset groups on the grey chrome.
    func inboxListStyle() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.chrome.ignoresSafeArea())
            .contentMargins(.bottom, 100, for: .scrollContent)
    }
}

/// A section heading inside a List, in the app's type.
struct InboxListHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).font(ODFont.sans(12.5, weight: .medium)).foregroundStyle(Theme.fg3)
            Spacer()
            if let trailing { Text(trailing).font(ODFont.mono(11.5)).foregroundStyle(Theme.fg4) }
        }
        .textCase(nil)
        .padding(.horizontal, 4)
    }
}

/// A footnote under a List section.
struct InboxListFooter: View {
    let text: String

    var body: some View {
        Text(text).font(ODFont.footnote).foregroundStyle(Theme.fg3).padding(.horizontal, 4)
    }
}

/// An underlined link in a footnote that opens another settings page.
struct InboxSettingLink: View {
    let title: String
    let page: SettingsPage

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button {
            Haptics.tap()
            env.router.accountPath.append(.setting(page))
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
            }
            .font(ODFont.sans(13, weight: .medium))
            .foregroundStyle(Theme.fg2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text

enum InboxText {
    /// "HH:MM" on the person's clock ("9:00 AM" or "09:00"); "24:00" is the end of the day.
    static func time(_ hhmm: String) -> String {
        let minutes = HoursRange.minutes(hhmm)
        let end = minutes >= 24 * 60
        let date = Calendar.current.date(from: DateComponents(hour: end ? 0 : minutes / 60, minute: end ? 0 : minutes % 60)) ?? .now
        let text = Format.clock(date)
        return end && text.hasPrefix("00") ? "24" + text.dropFirst(2) : text
    }

    static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n.formatted()) \(n == 1 ? one : many)"
    }

    /// 1200 → "1.2k", as the web's `compact`.
    static func compact(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName).precision(.fractionLength(0 ... 1)))
    }
}
