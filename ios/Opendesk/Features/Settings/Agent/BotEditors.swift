import PhotosUI
import SwiftUI

// The bot builder's two editors (contracts/bots.md): the look, from parts, an emoji or a picture,
// with every tile drawn by the shared renderer so what you pick is what visitors see; and the
// personality, the voice that never changes what the bot may do.

struct BotLookEditor: View {
    @Binding var look: BotLook
    let name: String
    let image: String?
    let uploading: Bool
    let upload: (UIImage) -> Void
    let removeImage: () -> Void

    @State private var photo: PhotosPickerItem?
    @State private var emojiText = ""

    private static let shapeNames = ["blob": "Blob", "circle": "Circle", "rounded": "Rounded", "squircle": "Squircle", "hexagon": "Hexagon", "cloud": "Cloud"]
    private static let eyeNames = ["dots": "Dots", "ovals": "Ovals", "pills": "Pills", "happy": "Happy", "sleepy": "Sleepy", "sparkle": "Sparkle", "wink": "Wink", "glasses": "Glasses", "star": "Stars"]
    private static let mouthNames = ["none": "None", "smile": "Smile", "grin": "Grin", "open": "Open", "cat": "Cat", "flat": "Flat", "tongue": "Tongue", "smirk": "Smirk", "tiny": "Tiny"]
    private static let accessoryNames = ["none": "None", "antenna": "Antenna", "headphones": "Headphones", "bow": "Bow", "cap": "Cap", "halo": "Halo", "sprout": "Sprout", "crown": "Crown"]
    private static let backgroundNames = ["none": "None", "soft": "Soft", "ring": "Ring"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("Style", hint: kindHint) {
                AccountSegmented(options: BotLook.kinds, selection: Binding(get: { look.kind }, set: { kind in
                    look.kind = kind
                    if kind == "emoji", look.emoji.isEmpty { look.emoji = "🦊" }
                }), label: { $0 == "built" ? "Built" : $0 == "emoji" ? "Emoji" : "Picture" })
            }
            if look.kind == "image" { picture }
            if look.kind == "emoji" { emoji }
            if look.kind != "image" {
                grid("Shape", BotLook.shapes, names: Self.shapeNames, value: \.shape)
                colour
            }
            if look.kind == "built" {
                grid("Eyes", BotLook.eyeStyles, names: Self.eyeNames, value: \.eyes)
                grid("Mouth", BotLook.mouths, names: Self.mouthNames, value: \.mouth)
                grid("Accessory", BotLook.accessories, names: Self.accessoryNames, value: \.accessory)
                if look.showsAccent { accent }
                Panel {
                    AccountToggleRow(title: "Blush", subtitle: "Rosy cheeks.", isOn: $look.blush)
                }
            }
            if look.kind != "image" {
                grid("Background", BotLook.backgrounds, names: Self.backgroundNames, value: \.background, keepBackground: true)
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { upload(image) }
                photo = nil
            }
        }
    }

    private var kindHint: String {
        switch look.kind {
        case "emoji": "Any emoji on a shape and colour you pick."
        case "image": "Your own picture, shown round."
        default: "Build a face from parts. Shuffle for ideas."
        }
    }

    private func group<Content: View>(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(ODFont.sans(13, weight: .medium)).foregroundStyle(Theme.fg)
                if let hint { Text(hint).font(ODFont.footnote).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }
    }

    /// A part's tiles: the current look with that one part changed (backgrounds off, so the part shows).
    private func grid(_ label: String, _ values: [String], names: [String: String], value: WritableKeyPath<BotLook, String>, keepBackground: Bool = false) -> some View {
        group(label) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54, maximum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(values, id: \.self) { option in
                    let chosen = look[keyPath: value] == option
                    Button {
                        Haptics.selection()
                        look[keyPath: value] = option
                    } label: {
                        BotFace(look: tile(value, option, keepBackground: keepBackground), size: 38)
                            .frame(width: 54, height: 54)
                            .background(chosen ? Theme.sunken : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(chosen ? Theme.fg : Theme.line, lineWidth: chosen ? 1.5 : 1))
                            .overlay(alignment: .topTrailing) {
                                if chosen {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .heavy))
                                        .foregroundStyle(Theme.surface)
                                        .frame(width: 14, height: 14)
                                        .background(Theme.fg, in: Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(TapScaleStyle(scale: 0.94))
                    .accessibilityLabel(names[option] ?? option)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    private func tile(_ key: WritableKeyPath<BotLook, String>, _ option: String, keepBackground: Bool) -> BotLook {
        var copy = look
        if copy.kind == "image" { copy.kind = "built" }
        if !keepBackground { copy.background = "none" }
        copy[keyPath: key] = option
        return copy
    }

    private var colour: some View {
        group("Colour") {
            VStack(alignment: .leading, spacing: 12) {
                AccountSegmented(options: [false, true], selection: Binding(get: { look.gradient }, set: { look.setGradient($0) }), label: { $0 ? "Gradient" : "Solid" }, height: 30)
                    .frame(width: 200)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32, maximum: 36), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(BotLook.palette, id: \.name) { family in
                        let chosen = look.family == family
                        Button {
                            Haptics.selection()
                            look.pick(family)
                        } label: {
                            Circle()
                                .fill(look.gradient
                                    ? AnyShapeStyle(RadialGradient(colors: [Color(hexString: family.light), Color(hexString: family.deep)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 22))
                                    : AnyShapeStyle(Color(hexString: family.base)))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().strokeBorder(chosen ? Theme.fg : .clear, lineWidth: 2))
                        }
                        .buttonStyle(TapScaleStyle(scale: 0.9))
                        .accessibilityLabel(family.name.capitalized)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                HStack(spacing: 12) {
                    BotHexField(label: look.gradient ? "From" : "Custom colour", value: $look.color)
                    if look.gradient { BotHexField(label: "To", value: $look.to) }
                }
            }
        }
    }

    private var accent: some View {
        group("Accent", hint: "Used for accessories and the ring.") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(BotLook.accents, id: \.self) { colour in
                        Button {
                            Haptics.selection()
                            look.accent = colour
                        } label: {
                            Circle().fill(Color(hexString: colour))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                                .padding(2)
                                .overlay(Circle().strokeBorder(look.accent == colour ? Theme.fg : .clear, lineWidth: 2))
                        }
                        .buttonStyle(TapScaleStyle(scale: 0.9))
                        .accessibilityLabel(colour)
                    }
                }
                BotHexField(label: "Custom accent", value: $look.accent)
            }
        }
    }

    private var emoji: some View {
        group("Emoji", hint: "One emoji.") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                    ForEach(BotLook.emojiPicks, id: \.self) { pick in
                        Button {
                            Haptics.selection()
                            look.emoji = pick
                        } label: {
                            Text(pick).font(.system(size: 22))
                                .frame(width: 38, height: 38)
                                .background(look.emoji == pick ? Theme.sunken : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(look.emoji == pick ? Theme.fg : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 10) {
                    Text("Or type your own").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                    TextField("", text: $emojiText)
                        .font(.system(size: 18))
                        .multilineTextAlignment(.center)
                        .frame(width: 64, height: 38)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .onChange(of: emojiText) { _, next in
                            let value = AgentText.trimmed(next)
                            if BotLook.isEmoji(value) { look.emoji = value }
                        }
                    if !emojiText.isEmpty, !BotLook.isEmoji(AgentText.trimmed(emojiText)) {
                        Text("Use a single emoji").font(ODFont.footnote).foregroundStyle(Tone.red.text)
                    }
                }
            }
        }
    }

    private var picture: some View {
        group("Picture", hint: "A square PNG, JPEG or WebP works best.") {
            HStack(spacing: 14) {
                ZStack {
                    if let image {
                        BotFace(look: look, image: image, size: 72)
                    } else {
                        Circle().fill(Theme.sunken).frame(width: 72, height: 72)
                            .overlay(Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(Theme.fg4))
                    }
                    if uploading {
                        Circle().fill(.black.opacity(0.35)).frame(width: 72, height: 72)
                        ProgressView().tint(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .compatible) {
                        Text(image == nil ? "Choose a picture" : "Change picture")
                    }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(uploading)
                    if image != nil {
                        Button("Remove picture", role: .destructive, action: removeImage)
                            .buttonStyle(ChipButtonStyle(tone: .red))
                            .disabled(uploading)
                    } else {
                        Text("No picture yet.").font(ODFont.footnote).foregroundStyle(Theme.fg3)
                    }
                }
            }
        }
    }
}

extension Color {
    /// A colour from a "#rrggbb" string.
    init(hexString: String) {
        self.init(hex: UInt32(hexString.dropFirst(), radix: 16) ?? 0)
    }
}

/// A #rrggbb field with a swatch; applies once the value is a full colour.
private struct BotHexField: View {
    let label: String
    @Binding var value: String

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(ODFont.sans(11.5)).foregroundStyle(Theme.fg3)
            HStack(spacing: 6) {
                Circle().fill(BotLook.isHex(value) ? Color(hexString: value) : .clear)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                TextField("#000000", text: $text)
                    .font(ODFont.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, next in
                        let raw = AgentText.trimmed(next).lowercased()
                        let hex = raw.hasPrefix("#") ? raw : "#" + raw
                        if BotLook.isHex(hex), hex != value { value = hex }
                    }
            }
            .padding(.horizontal, 10)
            .frame(width: 124, height: 36)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(badText ? Tone.red.solid.opacity(0.6) : Theme.line, lineWidth: 1))
        }
        .onAppear { text = value.uppercased() }
        .onChange(of: value) { _, next in
            if text.lowercased() != next { text = next.uppercased() }
        }
    }

    private var badText: Bool {
        let raw = AgentText.trimmed(text).lowercased()
        return !raw.isEmpty && !BotLook.isHex(raw.hasPrefix("#") ? raw : "#" + raw)
    }
}

// MARK: - Personality

enum BotLimits {
    static let name = 40
    static let role = 60
    static let customTone = 200
    static let instructions = 4000
    static let greeting = 300
    static let handoff = 300
    static let signOff = 200
    static let topics = 20

    /// Why a topic is refused, or nil.
    static func topicProblem(_ topic: String) -> String? {
        if topic.count < 2 { return "At least 2 characters" }
        if topic.count > 100 { return "Up to 100 characters" }
        if AgentText.hasMarkup(topic) { return "Plain text only, without < or >" }
        return nil
    }

    static func multilineProblem(_ text: String, max: Int) -> String? {
        if text.count > max { return "Up to \(max) characters" }
        let plain = text.replacingOccurrences(of: "\n", with: " ")
        return AgentText.hasMarkup(plain) ? "Plain text only, without < or >" : nil
    }

    static func invalid(_ p: BotPersonality) -> Bool {
        (p.tone == "custom" && AgentText.trimmed(p.customTone).isEmpty)
            || AgentText.problem(p.customTone, max: customTone) != nil
            || multilineProblem(p.greeting, max: greeting) != nil
            || multilineProblem(p.handoffMessage, max: handoff) != nil
            || multilineProblem(p.signOff, max: signOff) != nil
            || p.instructions.count > instructions
    }
}

struct BotPersonalityEditor: View {
    @Binding var personality: BotPersonality
    @Binding var language: String

    @Environment(AppEnvironment.self) private var env

    static let tones = ["friendly", "professional", "playful", "concise", "warm", "custom"]
    static let toneCopy: [String: (title: String, hint: String, sample: String)] = [
        "friendly": ("Friendly", "Warm and easy, like a helpful colleague.", "Hi! Happy to help with that. Here's what to do."),
        "professional": ("Professional", "Clear and composed, no small talk.", "Thank you for reaching out. Here are the steps to resolve this."),
        "playful": ("Playful", "Light and cheerful, still gets to the point.", "Ooh, good one! Let's sort this out together."),
        "concise": ("Concise", "As few words as the answer needs.", "Go to Settings, then Billing, then Cancel."),
        "warm": ("Warm", "Patient and kind, good for tricky moments.", "I'm sorry that happened. Let's get it fixed for you."),
        "custom": ("Custom", "Describe the voice in your own words.", "Your words, your voice."),
    ]
    private static let languages = ["en", "de", "fr", "es", "it", "pt-BR", "pt", "nl", "pl", "sv", "da", "nb", "fi", "cs", "hu", "ro", "tr", "uk", "ar", "he", "ja", "ko", "zh"]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                AgentGroupTitle(title: "Tone", hint: "How the bot sounds. It never changes what the bot is allowed to do.")
                Panel {
                    ForEach(Array(Self.tones.enumerated()), id: \.element) { index, tone in
                        if index > 0 { AccountDivider(tiles: false) }
                        let copy = Self.toneCopy[tone]
                        AccountChoiceRow(title: copy?.title ?? tone, subtitle: copy?.hint, chosen: personality.tone == tone) { personality.tone = tone }
                    }
                }
                if personality.tone == "custom" {
                    AgentField(label: "Describe the voice", text: $personality.customTone, prompt: "Calm, a little nerdy, explains the why", max: BotLimits.customTone, problem: AgentText.trimmed(personality.customTone).isEmpty ? "Required" : nil)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                AgentGroupTitle(title: "Reply length", hint: lengthHint)
                AccountSegmented(options: ["short", "medium", "detailed"], selection: $personality.replyLength, label: { $0.capitalized })
            }
            VStack(alignment: .leading, spacing: 8) {
                AgentGroupTitle(title: "Emoji", hint: emojiHint)
                AccountSegmented(options: ["none", "some", "lots"], selection: $personality.emoji, label: { $0.capitalized })
            }
            VStack(alignment: .leading, spacing: 8) {
                AgentGroupTitle(title: "Language", hint: "Auto answers in the customer's language.")
                Menu {
                    Picker("Language", selection: $language) {
                        Text("Auto").tag("")
                        ForEach(languageOptions, id: \.self) { code in
                            Text(Self.languageName(code)).tag(code)
                        }
                    }
                } label: {
                    HStack {
                        Text(language.isEmpty ? "Auto" : Self.languageName(language)).font(ODFont.sans(15)).foregroundStyle(Theme.fg)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.fg3)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }
            }
            AgentField(label: "Greeting", text: $personality.greeting, prompt: "Hi! I'm here to help. What can I do for you?", hint: "The first message visitors see in the widget.", multiline: true, problem: BotLimits.multilineProblem(personality.greeting, max: BotLimits.greeting))
            AgentField(label: "Handoff message", text: $personality.handoffMessage, prompt: "I'm bringing in someone from the team. They'll reply here.", hint: "What it says when it passes the chat to your team.", multiline: true, problem: BotLimits.multilineProblem(personality.handoffMessage, max: BotLimits.handoff))
            AgentField(label: "Email sign-off", text: $personality.signOff, prompt: "Best,\nThe Acme support team", hint: "How it signs emails. Leave empty to sign with its name.", multiline: true, problem: BotLimits.multilineProblem(personality.signOff, max: BotLimits.signOff))
            VStack(alignment: .leading, spacing: 6) {
                AgentField(label: "Instructions", text: $personality.instructions, prompt: "We sell project management software. Point billing questions to the billing page. Never promise delivery dates.", hint: "What the bot should know about your product and how to help. Rules and guardrails always come first.", multiline: true, problem: personality.instructions.count > BotLimits.instructions ? "Up to \(BotLimits.instructions) characters" : nil)
                Button("Add articles and sources in Knowledge") { env.router.accountPath.append(.setting(.knowledge)) }
                    .font(ODFont.sans(13, weight: .medium))
                    .foregroundStyle(Tone.violet.text)
            }
            AgentChipEditor(label: "Topics it declines", hint: "On top of the topics every bot declines.", items: $personality.blockedTopics, max: BotLimits.topics, prompt: "Add a topic", empty: "No extra topics", check: BotLimits.topicProblem)
        }
    }

    private var languageOptions: [String] {
        language.isEmpty || Self.languages.contains(language) ? Self.languages : [language] + Self.languages
    }

    private var lengthHint: String {
        switch personality.replyLength {
        case "short": "A few sentences at most."
        case "detailed": "Steps and context when they help."
        default: "Enough to explain, no more."
        }
    }

    private var emojiHint: String {
        switch personality.emoji {
        case "none": "Never uses emoji."
        case "lots": "Freely, to keep it light."
        default: "Now and then, where it fits."
        }
    }

    static func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
    }
}
