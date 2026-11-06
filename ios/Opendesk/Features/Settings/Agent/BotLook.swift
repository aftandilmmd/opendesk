import SwiftUI

// The bot look renderer (contracts/bots.md "The look"), the native twin of web/src/lib/botlook.ts
// and internal/ai/bots: the same parts table, colours, transforms and ink rule, so a bot drawn
// here is the bot visitors see. Everything drawn is a filled path from `BotParts`, and every
// colour is a validated #rrggbb.

/// A bot's look, read leniently: unknown or missing values take Ollie's.
struct BotLook: Hashable, Sendable {
    static let kinds = ["built", "emoji", "image"]
    static let shapes = ["blob", "circle", "rounded", "squircle", "hexagon", "cloud"]
    static let eyeStyles = ["dots", "ovals", "pills", "happy", "sleepy", "sparkle", "wink", "glasses", "star"]
    static let mouths = ["none", "smile", "grin", "open", "cat", "flat", "tongue", "smirk", "tiny"]
    static let accessories = ["none", "antenna", "headphones", "bow", "cap", "halo", "sprout", "crown"]
    static let backgrounds = ["none", "soft", "ring"]

    var kind = "built"
    var shape = "blob"
    var gradient = true
    var color = "#c9bcff"
    var to = "#4a2bc4"
    var eyes = "pills"
    var mouth = "none"
    var accessory = "none"
    var accent = "#f59e0b"
    var blush = false
    var background = "none"
    var emoji = ""

    /// Ollie, the default bot: the violet blob with two pill eyes.
    static let ollie = BotLook()

    static func read(_ value: JSONValue?) -> BotLook {
        let d = BotLook.ollie
        guard let value, value.object != nil else { return d }
        func one(_ key: String, _ list: [String], _ fallback: String) -> String {
            value[key]?.string.flatMap { list.contains($0) ? $0 : nil } ?? fallback
        }
        func hex(_ raw: String?, _ fallback: String) -> String {
            raw.flatMap { isHex($0) ? $0.lowercased() : nil } ?? fallback
        }
        var look = BotLook()
        look.kind = one("kind", kinds, d.kind)
        look.shape = one("shape", shapes, d.shape)
        let fill = value["fill"]
        let type = fill?["type"]?.string
        look.gradient = type == "gradient" ? true : type == "solid" ? false : d.gradient
        look.color = hex(fill?["color"]?.string, d.color)
        look.to = hex(fill?["to"]?.string, d.to)
        look.eyes = one("eyes", eyeStyles, d.eyes)
        look.mouth = one("mouth", mouths, d.mouth)
        look.accessory = one("accessory", accessories, d.accessory)
        look.accent = hex(value["accent"]?.string, d.accent)
        look.blush = value["blush"]?.bool ?? d.blush
        look.background = one("background", backgrounds, d.background)
        look.emoji = value["emoji"]?.string.flatMap { isEmoji($0) ? $0 : nil } ?? ""
        return look
    }

    var json: JSONValue {
        .object([
            "kind": .string(kind), "shape": .string(shape),
            "fill": .object(["type": .string(gradient ? "gradient" : "solid"), "color": .string(color), "to": .string(to)]),
            "eyes": .string(eyes), "mouth": .string(mouth), "accessory": .string(accessory), "accent": .string(accent),
            "blush": .bool(blush), "background": .string(background), "emoji": .string(emoji),
        ])
    }

    /// True for a #rrggbb colour.
    static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy(\.isHexDigit)
    }

    /// True when `s` is one emoji (a short run of pictographs, modifiers and joiners).
    static func isEmoji(_ s: String) -> Bool {
        guard !s.isEmpty, s.unicodeScalars.count <= 10, s.utf8.count <= 32 else { return false }
        var pict = false
        for scalar in s.unicodeScalars {
            let c = scalar.value
            let p = (0x1F000...0x1FAFF).contains(c) || (0x2600...0x27BF).contains(c) || (0x2300...0x23FF).contains(c)
                || (0x2B00...0x2BFF).contains(c) || (0x2190...0x21FF).contains(c) || (0x25A0...0x25FF).contains(c)
                || [0x3030, 0x303D, 0x3297, 0x3299, 0xA9, 0xAE, 0x203C, 0x2049, 0x2122, 0x2139, 0x24C2].contains(c)
            let mod = c == 0x200D || c == 0xFE0F || c == 0x20E3 || (0xE0020...0xE007F).contains(c)
                || (0x30...0x39).contains(c) || c == 0x23 || c == 0x2A
            if !p && !mod { return false }
            pict = pict || p || c == 0x20E3
        }
        return pict
    }

    /// The colour the eyes and mouth are drawn in: white on dark fills, ink on light ones.
    var ink: String {
        var (r, g, b) = Self.rgb(color)
        if gradient {
            let (r2, g2, b2) = Self.rgb(to)
            r = (r + r2) / 2
            g = (g + g2) / 2
            b = (b + b2) / 2
        }
        return 299 * r + 587 * g + 114 * b >= 165_000 ? BotParts.inkDark : BotParts.inkLight
    }

    static func rgb(_ hex: String) -> (Int, Int, Int) {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return ((n >> 16) & 255, (n >> 8) & 255, n & 255)
    }

    /// Accessories that take the accent colour.
    var showsAccent: Bool { kind == "built" && !["none", "halo", "sprout"].contains(accessory) }

    // MARK: Palette and randomize

    struct Family: Hashable, Sendable {
        let name: String
        let base: String
        let light: String
        let deep: String
    }

    /// Curated colour families: a base for solid fills and a light-to-deep pair for gradients.
    static let palette: [Family] = [
        Family(name: "violet", base: "#7c5cf2", light: "#c9bcff", deep: "#4a2bc4"),
        Family(name: "indigo", base: "#5b6cf0", light: "#c0c8ff", deep: "#3341b8"),
        Family(name: "blue", base: "#2f8cf0", light: "#a9d4ff", deep: "#1c5fc0"),
        Family(name: "sky", base: "#22b5e3", light: "#a5ecff", deep: "#0b7fae"),
        Family(name: "teal", base: "#14b8a6", light: "#9ff0e3", deep: "#0b7f73"),
        Family(name: "green", base: "#22b35e", light: "#b3f0c8", deep: "#127a3d"),
        Family(name: "lime", base: "#8cc63f", light: "#dcf5b4", deep: "#5a8f1f"),
        Family(name: "amber", base: "#f5a524", light: "#ffe2a6", deep: "#c46f06"),
        Family(name: "orange", base: "#f97316", light: "#ffcfa8", deep: "#c2410c"),
        Family(name: "coral", base: "#f2645a", light: "#ffc4bd", deep: "#c23a32"),
        Family(name: "rose", base: "#ec4899", light: "#ffc2e1", deep: "#b8226c"),
        Family(name: "plum", base: "#a855f7", light: "#e4c8ff", deep: "#7228c7"),
        Family(name: "slate", base: "#64748b", light: "#cfd8e3", deep: "#3b4659"),
        Family(name: "ink", base: "#2b2a35", light: "#6b6880", deep: "#16151c"),
    ]

    static let accents = ["#f59e0b", "#f6b81a", "#ef4444", "#ec4899", "#8b5cf6", "#3b82f6", "#14b8a6", "#22c55e", "#2a2838", "#ffffff"]
    static let emojiPicks = ["🦊", "🐙", "🦉", "🐝", "🐳", "🦄", "🐼", "🐸", "🌱", "🌻", "⭐", "🔥", "💡", "🚀", "🎧", "📚", "🧭", "🧩", "🍀", "☕", "🤖", "👋", "💬", "🎈"]

    /// The family the fill comes from, when it is one of the palette's.
    var family: Family? {
        Self.palette.first { gradient ? ($0.light == color && $0.deep == to) : $0.base == color }
    }

    mutating func pick(_ family: Family) {
        color = gradient ? family.light : family.base
        to = family.deep
    }

    /// Switches between solid and gradient, keeping the family.
    mutating func setGradient(_ on: Bool) {
        let fam = Self.palette.first { $0.base == color || $0.light == color || $0.deep == to }
        gradient = on
        if let fam { pick(fam) }
    }

    /// A pleasing random built look, the same rolls as the web's for the same seed.
    static func random(seed: UInt32) -> BotLook {
        var gen = Mulberry(seed: seed)
        let fi = Int(gen.next() * Double(palette.count)) % palette.count
        let fam = palette[fi]
        let gradient = gen.next() < 0.65
        let shape = gen.weighted([("blob", 25), ("circle", 14), ("rounded", 14), ("squircle", 20), ("hexagon", 10), ("cloud", 17)])
        let colours = palette.count - 2
        let ai = fi >= colours ? Int(gen.next() * Double(colours)) % colours : (fi + 4 + Int(gen.next() * 5)) % colours
        let eyes = gen.weighted([("dots", 18), ("ovals", 16), ("pills", 12), ("happy", 14), ("sleepy", 6), ("sparkle", 9), ("wink", 8), ("glasses", 8), ("star", 7)])
        let mouths: [(String, Double)] = eyes == "sleepy"
            ? [("none", 3), ("tiny", 3), ("flat", 2), ("smile", 2)]
            : eyes == "glasses"
            ? [("smile", 4), ("grin", 2), ("flat", 2), ("smirk", 2), ("tiny", 2)]
            : [("none", 4), ("smile", 6), ("grin", 4), ("open", 2), ("cat", 3), ("flat", 1), ("tongue", 2), ("smirk", 2), ("tiny", 4)]
        let mouth = gen.weighted(mouths)
        let rest = Array(accessories.dropFirst())
        let accessory = gen.next() < 0.45 ? "none" : rest[Int(gen.next() * Double(rest.count)) % rest.count]
        let warm = ["rose", "coral", "orange"].contains(fam.name)
        let blush = !warm && fam.name != "ink" && gen.next() < 0.45
        let background = gen.weighted([("none", 60), ("soft", 25), ("ring", 15)])
        var look = BotLook()
        look.shape = shape
        look.gradient = gradient
        look.color = gradient ? fam.light : fam.base
        look.to = fam.deep
        look.eyes = eyes
        look.mouth = mouth
        look.accessory = accessory
        look.accent = palette[ai].base
        look.blush = blush
        look.background = background
        return look
    }

    static func randomSeed() -> UInt32 { UInt32.random(in: 0...UInt32.max) }
}

/// mulberry32: the same seed gives the same rolls as the web's `seeded`.
struct Mulberry {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    mutating func weighted(_ items: [(String, Double)]) -> String {
        let total = items.reduce(0) { $0 + $1.1 }
        var r = next() * total
        for (value, weight) in items {
            r -= weight
            if r < 0 { return value }
        }
        return items.last?.0 ?? ""
    }
}

// MARK: - Parts

enum BotParts {
    static let inkLight = "#ffffff"
    static let inkDark = "#2a2838"
    static let stick = "#3f3a55"
    static let gold = "#f6b81a"
    static let leafDark = "#2f9e5b"
    static let leaf = "#4cc27a"
    static let blush = "#ff7a9a"
    static let tongue = "#ff7a93"

    /// The face's transform: a background shrinks it, an accessory makes room above it.
    static func transform(background: String, roomy: Bool) -> CGAffineTransform? {
        switch (background, roomy) {
        case ("soft", false): CGAffineTransform(a: 0.8, b: 0, c: 0, d: 0.8, tx: 6.4, ty: 6.4)
        case ("soft", true): CGAffineTransform(a: 0.72, b: 0, c: 0, d: 0.72, tx: 8.96, ty: 11.68)
        case ("ring", false): CGAffineTransform(a: 0.78, b: 0, c: 0, d: 0.78, tx: 7.04, ty: 7.04)
        case ("ring", true): CGAffineTransform(a: 0.702, b: 0, c: 0, d: 0.702, tx: 9.536, ty: 12.188)
        case (_, true): CGAffineTransform(a: 0.9, b: 0, c: 0, d: 0.9, tx: 3.2, ty: 6.6)
        default: nil
        }
    }

    static func path(_ key: String) -> Path { paths[key] ?? Path() }

    private static let paths: [String: Path] = source.mapValues(parse)

    /// Parses the absolute M, L, C, Q and Z commands the parts table uses.
    private static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number); number = "" }
        }
        for ch in d {
            if "MLCQZ".contains(ch) {
                flush()
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" {
                flush()
                number = "-"
            } else {
                number.append(ch)
            }
        }
        flush()
        var i = 0
        var command = "M"
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        func point() -> CGPoint { CGPoint(x: num(), y: num()) }
        while i < tokens.count {
            if let first = tokens[i].first, first.isLetter {
                command = tokens[i]
                i += 1
                if command == "Z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M":
                path.move(to: point())
                command = "L"
            case "L": path.addLine(to: point())
            case "C":
                let c1 = point(), c2 = point(), end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            case "Q":
                let c = point(), end = point()
                path.addQuadCurve(to: end, control: c)
            default: i += 1
            }
        }
        return path
    }

    private static let source: [String: String] = [
        "circle": "M32 7C45.81 7 57 18.19 57 32C57 45.81 45.81 57 32 57C18.19 57 7 45.81 7 32C7 18.19 18.19 7 32 7Z",
        "rounded": "M21 7L43 7C50.73 7 57 13.27 57 21L57 43C57 50.73 50.73 57 43 57L21 57C13.27 57 7 50.73 7 43L7 21C7 13.27 13.27 7 21 7Z",
        "squircle": "M32 7C51 7 57 13 57 32C57 51 51 57 32 57C13 57 7 51 7 32C7 13 13 7 32 7Z",
        "hexagon": "M26.37 8.75Q32 5.5 37.63 8.75L49.75 15.75Q55.38 19 55.38 25.5L55.38 39.5Q55.38 46 49.75 49.25L37.63 56.25Q32 59.5 26.37 56.25L14.25 49.25Q8.62 46 8.62 39.5L8.62 25.5Q8.62 19 14.25 15.75Z",
        "cloud": "M19.5 23.5C26.4 23.5 32 29.1 32 36C32 42.9 26.4 48.5 19.5 48.5C12.6 48.5 7 42.9 7 36C7 29.1 12.6 23.5 19.5 23.5ZM32 8.5C40.56 8.5 47.5 15.44 47.5 24C47.5 32.56 40.56 39.5 32 39.5C23.44 39.5 16.5 32.56 16.5 24C16.5 15.44 23.44 8.5 32 8.5ZM45 20.5C51.9 20.5 57.5 26.1 57.5 33C57.5 39.9 51.9 45.5 45 45.5C38.1 45.5 32.5 39.9 32.5 33C32.5 26.1 38.1 20.5 45 20.5ZM19.5 32L44.5 32C51.4 32 57 37.6 57 44.5L57 44.5C57 51.4 51.4 57 44.5 57L19.5 57C12.6 57 7 51.4 7 44.5L7 44.5C7 37.6 12.6 32 19.5 32Z",
        "blob": "M32 7C46.06 7 56.74 16.9 56.74 30.7C56.74 45.28 46.06 57 31.74 57C17.94 57 7.26 45.8 7.26 31.48C7.26 17.42 17.94 7 32 7Z",
        "shine_default": "M20.5 14.12C23.83 12.64 27.2 12.95 28.03 14.82C28.86 16.68 26.83 19.4 23.5 20.88C20.17 22.36 16.8 22.05 15.97 20.18C15.14 18.32 17.17 15.6 20.5 14.12Z",
        "shine_cloud": "M24.87 12.4C27.99 11.27 31.01 11.74 31.64 13.45C32.26 15.16 30.24 17.47 27.13 18.6C24.01 19.73 20.99 19.26 20.36 17.55C19.74 15.84 21.76 13.53 24.87 12.4Z",
        "shine_hex": "M21.45 15.59C24.38 14.03 27.44 14.07 28.3 15.68C29.15 17.29 27.48 19.86 24.55 21.41C21.62 22.97 18.56 22.93 17.7 21.32C16.85 19.71 18.52 17.14 21.45 15.59Z",
        "eye_dots": "M24 26.6C25.88 26.6 27.4 28.12 27.4 30C27.4 31.88 25.88 33.4 24 33.4C22.12 33.4 20.6 31.88 20.6 30C20.6 28.12 22.12 26.6 24 26.6ZM40 26.6C41.88 26.6 43.4 28.12 43.4 30C43.4 31.88 41.88 33.4 40 33.4C38.12 33.4 36.6 31.88 36.6 30C36.6 28.12 38.12 26.6 40 26.6Z",
        "eye_dots_hi": "M25.15 27.6C25.76 27.6 26.25 28.09 26.25 28.7C26.25 29.31 25.76 29.8 25.15 29.8C24.54 29.8 24.05 29.31 24.05 28.7C24.05 28.09 24.54 27.6 25.15 27.6ZM41.15 27.6C41.76 27.6 42.25 28.09 42.25 28.7C42.25 29.31 41.76 29.8 41.15 29.8C40.54 29.8 40.05 29.31 40.05 28.7C40.05 28.09 40.54 27.6 41.15 27.6Z",
        "eye_ovals": "M24 25.9C25.49 25.9 26.7 27.74 26.7 30C26.7 32.26 25.49 34.1 24 34.1C22.51 34.1 21.3 32.26 21.3 30C21.3 27.74 22.51 25.9 24 25.9ZM40 25.9C41.49 25.9 42.7 27.74 42.7 30C42.7 32.26 41.49 34.1 40 34.1C38.51 34.1 37.3 32.26 37.3 30C37.3 27.74 38.51 25.9 40 25.9Z",
        "eye_ovals_hi": "M24.9 27.2C25.45 27.2 25.9 27.65 25.9 28.2C25.9 28.75 25.45 29.2 24.9 29.2C24.35 29.2 23.9 28.75 23.9 28.2C23.9 27.65 24.35 27.2 24.9 27.2ZM40.9 27.2C41.45 27.2 41.9 27.65 41.9 28.2C41.9 28.75 41.45 29.2 40.9 29.2C40.35 29.2 39.9 28.75 39.9 28.2C39.9 27.65 40.35 27.2 40.9 27.2Z",
        "eye_pills": "M26.6 28.35L26.6 28.35C27.82 28.35 28.8 29.33 28.8 30.55L28.8 33.45C28.8 34.67 27.82 35.65 26.6 35.65L26.6 35.65C25.38 35.65 24.4 34.67 24.4 33.45L24.4 30.55C24.4 29.33 25.38 28.35 26.6 28.35ZM37.4 28.35L37.4 28.35C38.62 28.35 39.6 29.33 39.6 30.55L39.6 33.45C39.6 34.67 38.62 35.65 37.4 35.65L37.4 35.65C36.18 35.65 35.2 34.67 35.2 33.45L35.2 30.55C35.2 29.33 36.18 28.35 37.4 28.35Z",
        "eye_happy": "M18.8 31.6Q24 23.4 29.2 31.6Q29.6 32.6 28.6 32.9Q27.6 33.1 27.1 32.2Q24 27.4 20.9 32.2Q20.4 33.1 19.4 32.9Q18.4 32.6 18.8 31.6ZM34.8 31.6Q40 23.4 45.2 31.6Q45.6 32.6 44.6 32.9Q43.6 33.1 43.1 32.2Q40 27.4 36.9 32.2Q36.4 33.1 35.4 32.9Q34.4 32.6 34.8 31.6Z",
        "eye_sleepy": "M18.8 28.4Q24 36.6 29.2 28.4Q29.6 27.4 28.6 27.1Q27.6 26.9 27.1 27.8Q24 32.6 20.9 27.8Q20.4 26.9 19.4 27.1Q18.4 27.4 18.8 28.4ZM34.8 28.4Q40 36.6 45.2 28.4Q45.6 27.4 44.6 27.1Q43.6 26.9 43.1 27.8Q40 32.6 36.9 27.8Q36.4 26.9 35.4 27.1Q34.4 27.4 34.8 28.4Z",
        "eye_sparkle": "M24 24.6Q25.19 28.81 29.4 30Q25.19 31.19 24 35.4Q22.81 31.19 18.6 30Q22.81 28.81 24 24.6ZM40 24.6Q41.19 28.81 45.4 30Q41.19 31.19 40 35.4Q38.81 31.19 34.6 30Q38.81 28.81 40 24.6Z",
        "eye_wink": "M24 26.6C25.88 26.6 27.4 28.12 27.4 30C27.4 31.88 25.88 33.4 24 33.4C22.12 33.4 20.6 31.88 20.6 30C20.6 28.12 22.12 26.6 24 26.6ZM34.8 31.6Q40 23.4 45.2 31.6Q45.6 32.6 44.6 32.9Q43.6 33.1 43.1 32.2Q40 27.4 36.9 32.2Q36.4 33.1 35.4 32.9Q34.4 32.6 34.8 31.6Z",
        "eye_wink_hi": "M25.15 27.6C25.76 27.6 26.25 28.09 26.25 28.7C26.25 29.31 25.76 29.8 25.15 29.8C24.54 29.8 24.05 29.31 24.05 28.7C24.05 28.09 24.54 27.6 25.15 27.6Z",
        "eye_glasses": "M24 23.2C27.76 23.2 30.8 26.24 30.8 30C30.8 33.76 27.76 36.8 24 36.8C20.24 36.8 17.2 33.76 17.2 30C17.2 26.24 20.24 23.2 24 23.2ZM24 24.9C21.18 24.9 18.9 27.18 18.9 30C18.9 32.82 21.18 35.1 24 35.1C26.82 35.1 29.1 32.82 29.1 30C29.1 27.18 26.82 24.9 24 24.9ZM40 23.2C43.76 23.2 46.8 26.24 46.8 30C46.8 33.76 43.76 36.8 40 36.8C36.24 36.8 33.2 33.76 33.2 30C33.2 26.24 36.24 23.2 40 23.2ZM40 24.9C37.18 24.9 34.9 27.18 34.9 30C34.9 32.82 37.18 35.1 40 35.1C42.82 35.1 45.1 32.82 45.1 30C45.1 27.18 42.82 24.9 40 24.9ZM31.5 28.6L32.5 28.6C33 28.6 33.4 29 33.4 29.5L33.4 29.5C33.4 30 33 30.4 32.5 30.4L31.5 30.4C31 30.4 30.6 30 30.6 29.5L30.6 29.5C30.6 29 31 28.6 31.5 28.6ZM24 28.2C25.22 28.2 26.2 29.18 26.2 30.4C26.2 31.62 25.22 32.6 24 32.6C22.78 32.6 21.8 31.62 21.8 30.4C21.8 29.18 22.78 28.2 24 28.2ZM40 28.2C41.22 28.2 42.2 29.18 42.2 30.4C42.2 31.62 41.22 32.6 40 32.6C38.78 32.6 37.8 31.62 37.8 30.4C37.8 29.18 38.78 28.2 40 28.2Z",
        "eye_star": "M23.8 25.61Q24 25.1 24.2 25.61L25.04 27.79Q25.23 28.3 25.78 28.33L28.11 28.46Q28.66 28.49 28.23 28.83L26.42 30.3Q26 30.65 26.14 31.18L26.74 33.43Q26.88 33.96 26.42 33.67L24.46 32.4Q24 32.1 23.54 32.4L21.58 33.67Q21.12 33.96 21.26 33.43L21.86 31.18Q22 30.65 21.58 30.3L19.77 28.83Q19.34 28.49 19.89 28.46L22.22 28.33Q22.77 28.3 22.96 27.79ZM39.8 25.61Q40 25.1 40.2 25.61L41.04 27.79Q41.23 28.3 41.78 28.33L44.11 28.46Q44.66 28.49 44.23 28.83L42.42 30.3Q42 30.65 42.14 31.18L42.74 33.43Q42.88 33.96 42.42 33.67L40.46 32.4Q40 32.1 39.54 32.4L37.58 33.67Q37.12 33.96 37.26 33.43L37.86 31.18Q38 30.65 37.58 30.3L35.77 28.83Q35.34 28.49 35.89 28.46L38.22 28.33Q38.77 28.3 38.96 27.79Z",
        "mouth_smile": "M25.8 39.4Q32 47.2 38.2 39.4Q38.6 38.8 38 38.4Q37.3 37.9 36.7 38.6Q32 44 27.3 38.6Q26.7 37.9 26 38.4Q25.4 38.8 25.8 39.4Z",
        "mouth_grin": "M25.4 38.4L38.6 38.4C38.6 43.6 35.6 46.6 32 46.6C28.4 46.6 25.4 43.6 25.4 38.4Z",
        "mouth_tongue": "M25.4 38.4L38.6 38.4C38.6 43.6 35.6 46.6 32 46.6C28.4 46.6 25.4 43.6 25.4 38.4Z",
        "mouth_tongue_t": "M28.2 45.1C29 42.6 35 42.6 35.8 45.1C34.8 46.1 33.4 46.6 32 46.6C30.6 46.6 29.2 46.1 28.2 45.1Z",
        "mouth_open": "M32 38.1C33.82 38.1 35.3 39.85 35.3 42C35.3 44.15 33.82 45.9 32 45.9C30.18 45.9 28.7 44.15 28.7 42C28.7 39.85 30.18 38.1 32 38.1Z",
        "mouth_cat": "M25.6 39.6Q29 46 32 41.2Q35 46 38.4 39.6Q38.6 38.7 37.7 38.6Q37.1 38.6 36.9 39.2Q35 42.6 32.9 38.9Q32.5 38.3 32 38.3Q31.5 38.3 31.1 38.9Q29 42.6 27.1 39.2Q26.9 38.6 26.3 38.6Q25.4 38.7 25.6 39.6Z",
        "mouth_flat": "M28.2 40L35.8 40C36.46 40 37 40.54 37 41.2L37 41.2C37 41.86 36.46 42.4 35.8 42.4L28.2 42.4C27.54 42.4 27 41.86 27 41.2L27 41.2C27 40.54 27.54 40 28.2 40Z",
        "mouth_smirk": "M27 41.6Q33.6 44.6 38.6 38.4Q39 37.6 38.2 37.4Q37.6 37.3 37.2 37.9Q33.2 42.4 27.6 39.8Q26.9 39.6 26.6 40.3Q26.4 41.2 27 41.6Z",
        "mouth_tiny": "M28.8 40.2Q32 44.4 35.2 40.2Q35.5 39.5 34.9 39.3Q34.4 39.1 34 39.6Q32 41.9 30 39.6Q29.6 39.1 29.1 39.3Q28.5 39.5 28.8 40.2Z",
        "blush": "M18.6 35.3C20.64 35.3 22.3 36.33 22.3 37.6C22.3 38.87 20.64 39.9 18.6 39.9C16.56 39.9 14.9 38.87 14.9 37.6C14.9 36.33 16.56 35.3 18.6 35.3ZM45.4 35.3C47.44 35.3 49.1 36.33 49.1 37.6C49.1 38.87 47.44 39.9 45.4 39.9C43.36 39.9 41.7 38.87 41.7 37.6C41.7 36.33 43.36 35.3 45.4 35.3Z",
        "acc_antenna_stick": "M32 -1.5L32 -1.5C32.55 -1.5 33 -1.05 33 -0.5L33 7C33 7.55 32.55 8 32 8L32 8C31.45 8 31 7.55 31 7L31 -0.5C31 -1.05 31.45 -1.5 32 -1.5Z",
        "acc_antenna_ball": "M32 -6.4C33.88 -6.4 35.4 -4.88 35.4 -3C35.4 -1.12 33.88 0.4 32 0.4C30.12 0.4 28.6 -1.12 28.6 -3C28.6 -4.88 30.12 -6.4 32 -6.4Z",
        "acc_antenna_hi": "M30.9 -5.15C31.48 -5.15 31.95 -4.68 31.95 -4.1C31.95 -3.52 31.48 -3.05 30.9 -3.05C30.32 -3.05 29.85 -3.52 29.85 -4.1C29.85 -4.68 30.32 -5.15 30.9 -5.15Z",
        "acc_headphones_band": "M5 32C5 -7.5 59 -7.5 59 32L55.8 32C55.8 -3.2 8.2 -3.2 8.2 32Z",
        "acc_headphones_cups": "M6 24L6.4 24C8.61 24 10.4 25.79 10.4 28L10.4 37C10.4 39.21 8.61 41 6.4 41L6 41C3.79 41 2 39.21 2 37L2 28C2 25.79 3.79 24 6 24ZM57.6 24L58 24C60.21 24 62 25.79 62 28L62 37C62 39.21 60.21 41 58 41L57.6 41C55.39 41 53.6 39.21 53.6 37L53.6 28C53.6 25.79 55.39 24 57.6 24Z",
        "acc_bow": "M46 9.5C40.5 2.5 35.6 4.6 36.4 9.8C37 14 41 15 46 9.5ZM46 9.5C51.5 2.5 56.4 4.6 55.6 9.8C55 14 51 15 46 9.5Z",
        "acc_bow_knot": "M46 6.8C47.49 6.8 48.7 8.01 48.7 9.5C48.7 10.99 47.49 12.2 46 12.2C44.51 12.2 43.3 10.99 43.3 9.5C43.3 8.01 44.51 6.8 46 6.8Z",
        "acc_cap_dome": "M12.5 17.5C12.5 0.5 51.5 0.5 51.5 17.5Z",
        "acc_cap_brim": "M10.5 17.5C10.5 13.6 53.5 13.6 53.5 17.5C53.5 22.4 10.5 22.4 10.5 17.5Z",
        "acc_cap_button": "M32 2.3C33.05 2.3 33.9 3.15 33.9 4.2C33.9 5.25 33.05 6.1 32 6.1C30.95 6.1 30.1 5.25 30.1 4.2C30.1 3.15 30.95 2.3 32 2.3Z",
        "acc_halo": "M32 -3.3C39.18 -3.3 45 -1.6 45 0.5C45 2.6 39.18 4.3 32 4.3C24.82 4.3 19 2.6 19 0.5C19 -1.6 24.82 -3.3 32 -3.3ZM32 -1.6C26.48 -1.6 22 -0.66 22 0.5C22 1.66 26.48 2.6 32 2.6C37.52 2.6 42 1.66 42 0.5C42 -0.66 37.52 -1.6 32 -1.6Z",
        "acc_sprout_stem": "M31.3 8.5C31 4.5 31.6 1.4 32.7 -1L34 -0.4C33.1 1.8 32.8 4.8 33.1 8.5Z",
        "acc_sprout_leaves": "M32.5 1.2C28.2 -4.4 22.4 -2.6 21.6 0.4C25.2 3.4 29.6 3.8 32.5 1.2ZM33.2 -0.4C36 -6.4 42.6 -6.6 43.8 -3.8C41 -0.4 36.6 0.8 33.2 -0.4Z",
        "acc_crown": "M18.9 12Q18 12 18.11 11.11L19.39 0.39Q19.5 -0.5 20.15 0.13L25.15 4.97Q25.8 5.6 26.32 4.86L31.48 -2.46Q32 -3.2 32.52 -2.46L37.68 4.86Q38.2 5.6 38.85 4.97L43.85 0.13Q44.5 -0.5 44.61 0.39L45.89 11.11Q46 12 45.1 12Z",
        "acc_crown_gems": "M32 4.4C32.99 4.4 33.8 5.21 33.8 6.2C33.8 7.19 32.99 8 32 8C31.01 8 30.2 7.19 30.2 6.2C30.2 5.21 31.01 4.4 32 4.4ZM24.6 6.9C25.32 6.9 25.9 7.48 25.9 8.2C25.9 8.92 25.32 9.5 24.6 9.5C23.88 9.5 23.3 8.92 23.3 8.2C23.3 7.48 23.88 6.9 24.6 6.9ZM39.4 6.9C40.12 6.9 40.7 7.48 40.7 8.2C40.7 8.92 40.12 9.5 39.4 9.5C38.68 9.5 38.1 8.92 38.1 8.2C38.1 7.48 38.68 6.9 39.4 6.9Z",
        "bg_soft": "M32 0C49.67 0 64 14.33 64 32C64 49.67 49.67 64 32 64C14.33 64 0 49.67 0 32C0 14.33 14.33 0 32 0Z",
        "bg_ring": "M32 0.4C49.45 0.4 63.6 14.55 63.6 32C63.6 49.45 49.45 63.6 32 63.6C14.55 63.6 0.4 49.45 0.4 32C0.4 14.55 14.55 0.4 32 0.4ZM32 2.2C15.54 2.2 2.2 15.54 2.2 32C2.2 48.46 15.54 61.8 32 61.8C48.46 61.8 61.8 48.46 61.8 32C61.8 15.54 48.46 2.2 32 2.2Z",
    ]
}

private extension Color {
    init(botHex hex: String) {
        self.init(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0)
    }
}

// MARK: - Drawing

/// Draws a look into a canvas, at 64 units to the side.
enum BotRenderer {
    /// `blink` squashes the eyes (1 open, 0.1 shut); `bob` lifts the face in units.
    static func draw(_ look: BotLook, in context: inout GraphicsContext, size: CGFloat, blink: CGFloat = 1, bob: CGFloat = 0, squash: CGSize = CGSize(width: 1, height: 1)) {
        context.scaleBy(x: size / 64, y: size / 64)
        let deep = look.gradient ? look.to : look.color
        let emoji = look.kind == "emoji" && !look.emoji.isEmpty
        let withAccessory = !emoji && look.accessory != "none"

        func fill(_ key: String, _ hex: String, _ opacity: Double = 1, in ctx: GraphicsContext) {
            ctx.fill(BotParts.path(key), with: .color(Color(botHex: hex).opacity(opacity)))
        }

        if look.background == "soft" { fill("bg_soft", deep, 0.16, in: context) }
        if look.background == "ring" { fill("bg_ring", deep, in: context) }

        var face = context
        face.translateBy(x: 32, y: 38.4 + bob)
        face.scaleBy(x: squash.width, y: squash.height)
        face.translateBy(x: -32, y: -38.4)
        if let transform = BotParts.transform(background: look.background, roomy: withAccessory) {
            face.concatenate(transform)
        }

        let body = BotParts.path(look.shape)
        if look.gradient {
            let gradient = Gradient(colors: [Color(botHex: look.color), Color(botHex: look.to)])
            face.fill(body, with: .radialGradient(gradient, center: CGPoint(x: 22, y: 16), startRadius: 0, endRadius: 50))
        } else {
            face.fill(body, with: .color(Color(botHex: look.color)))
        }

        if emoji {
            face.draw(Text(look.emoji).font(.system(size: 31)), at: CGPoint(x: 32, y: 33.5), anchor: .center)
            return
        }

        let shine = look.shape == "cloud" ? "shine_cloud" : look.shape == "hexagon" ? "shine_hex" : "shine_default"
        fill(shine, "#ffffff", 0.45, in: face)
        if look.blush { fill("blush", BotParts.blush, 0.5, in: face) }

        let ink = look.ink
        var eyes = face
        if blink < 1 {
            let box = BotParts.path("eye_\(look.eyes)").boundingRect
            let anchor = CGPoint(x: box.midX, y: box.minY + box.height * 0.6)
            eyes.translateBy(x: anchor.x, y: anchor.y)
            eyes.scaleBy(x: 1, y: blink)
            eyes.translateBy(x: -anchor.x, y: -anchor.y)
        }
        fill("eye_\(look.eyes)", ink, in: eyes)
        if ink == BotParts.inkDark, ["dots", "ovals", "wink"].contains(look.eyes) {
            fill("eye_\(look.eyes)_hi", "#ffffff", in: eyes)
        }

        if look.mouth != "none" {
            fill("mouth_\(look.mouth)", ink, in: face)
            if look.mouth == "tongue" { fill("mouth_tongue_t", BotParts.tongue, in: face) }
        }

        guard withAccessory else { return }
        let a = look.accent
        switch look.accessory {
        case "antenna":
            fill("acc_antenna_stick", BotParts.stick, in: face)
            fill("acc_antenna_ball", a, in: face)
            fill("acc_antenna_hi", "#ffffff", 0.6, in: face)
        case "headphones":
            fill("acc_headphones_band", BotParts.stick, in: face)
            fill("acc_headphones_cups", a, in: face)
        case "bow":
            fill("acc_bow", a, in: face)
            fill("acc_bow_knot", a, in: face)
            fill("acc_bow_knot", "#000000", 0.18, in: face)
        case "cap":
            fill("acc_cap_dome", a, in: face)
            fill("acc_cap_brim", a, in: face)
            fill("acc_cap_brim", "#000000", 0.18, in: face)
            fill("acc_cap_button", a, in: face)
        case "halo":
            fill("acc_halo", BotParts.gold, in: face)
        case "sprout":
            fill("acc_sprout_stem", BotParts.leafDark, in: face)
            fill("acc_sprout_leaves", BotParts.leaf, in: face)
        case "crown":
            fill("acc_crown", BotParts.gold, in: face)
            fill("acc_crown_gems", a, in: face)
        default: break
        }
    }
}

/// A bot's face: its uploaded picture when the look is a picture, else the rendered look.
/// `state` drives the motion: an idle blink, a thinking bob, a happy hop. Nothing moves
/// under Reduce Motion.
struct BotFace: View {
    enum Mood: Equatable { case idle, thinking, happy }

    let look: BotLook
    var image: String?
    var size: CGFloat = 32
    var mood: Mood = .idle
    /// Blinks now and then while idle.
    var alive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hopStart: Date?

    private var picture: URL? {
        guard look.kind == "image", let image, let url = URL(string: image) else { return nil }
        return ["https", "http", "data"].contains(url.scheme ?? "") ? url : nil
    }

    var body: some View {
        Group {
            if let picture {
                AsyncImage(url: picture, transaction: Transaction(animation: Motion.fade)) { phase in
                    if case let .success(img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Circle().fill(Theme.sunken)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else if moving {
                TimelineView(.animation) { timeline in
                    canvas(at: timeline.date)
                }
            } else {
                canvas(at: nil)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { _, mood in
            hopStart = mood == .happy ? .now : nil
        }
        .accessibilityHidden(true)
    }

    private var moving: Bool { !reduceMotion && (alive || mood != .idle) }

    private func canvas(at date: Date?) -> some View {
        let motion = date.map(self.motion) ?? (blink: 1, bob: 0, squash: CGSize(width: 1, height: 1))
        return Canvas(rendersAsynchronously: false) { context, canvasSize in
            var ctx = context
            BotRenderer.draw(look, in: &ctx, size: min(canvasSize.width, canvasSize.height), blink: motion.blink, bob: motion.bob, squash: motion.squash)
        }
        .frame(width: size, height: size)
    }

    /// The CSS keyframes of the web renderer, sampled at `date`.
    private func motion(_ date: Date) -> (blink: CGFloat, bob: CGFloat, squash: CGSize) {
        let t = date.timeIntervalSinceReferenceDate
        var blink: CGFloat = 1
        if alive && mood == .idle {
            let phase = t.truncatingRemainder(dividingBy: 5.6) / 5.6
            if phase > 0.45 && phase < 0.49 {
                let k = 1 - abs(phase - 0.47) / 0.02
                blink = 1 - 0.9 * CGFloat(k)
            }
        }
        var bob: CGFloat = 0
        var squash = CGSize(width: 1, height: 1)
        switch mood {
        case .thinking:
            bob = -CGFloat((1 - cos(t * 2 * .pi)) / 2) * 0.07 * 50
        case .happy:
            if let hopStart {
                let p = date.timeIntervalSince(hopStart) / 0.7
                if p < 1 {
                    if p < 0.35 {
                        let k = CGFloat(sin(p / 0.35 * .pi / 2))
                        bob = -0.12 * 50 * k
                        squash = CGSize(width: 1 + 0.06 * k, height: 1 - 0.06 * k)
                    } else if p < 0.7 {
                        let k = CGFloat((p - 0.35) / 0.35)
                        bob = -0.12 * 50 * (1 - k)
                        squash = CGSize(width: 1.06 - 0.09 * k, height: 0.94 + 0.09 * k)
                    } else {
                        let k = CGFloat((p - 0.7) / 0.3)
                        squash = CGSize(width: 0.97 + 0.03 * k, height: 1.03 - 0.03 * k)
                    }
                }
            }
        case .idle: break
        }
        return (blink, bob, squash)
    }
}
