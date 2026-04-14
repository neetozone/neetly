import AppKit

struct TerminalConfig: Codable {
    let fontFamily: String?
    let fontSize: CGFloat?
    let backgroundColor: String?
    let foregroundColor: String?
    let selectionColor: String?
    let linkColor: String?
    let scrollback: Int?

    static let `default` = TerminalConfig(
        fontFamily: nil,
        fontSize: 17,
        backgroundColor: "#1e1f2e",
        foregroundColor: "#cdd8f4",
        selectionColor: "#635b70",
        linkColor: "#8bb8fa",
        scrollback: 10000
    )

    static func load() -> TerminalConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configFile = home.appendingPathComponent(".config/neetly/terminal.json")
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(TerminalConfig.self, from: data) else {
            return .default
        }
        return config
    }

    var font: NSFont {
        let size = fontSize ?? 17
        let candidates = [
            fontFamily,
            "JetBrains Mono",
            "Symbols Nerd Font Mono",
            "Noto Color Emoji",
        ].compactMap { $0 }

        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var bgColor: NSColor? {
        backgroundColor.flatMap { NSColor.fromHex($0) }
    }

    var fgColor: NSColor? {
        foregroundColor.flatMap { NSColor.fromHex($0) }
    }

    var selColor: NSColor? {
        selectionColor.flatMap { NSColor.fromHex($0) }
    }

    /// Returns the link color as an OSC 4 escape sequence that overrides ANSI
    /// palette colors 4 (blue) and 12 (bright blue), where most terminals render
    /// URLs.
    var oscLinkColorSequence: String? {
        guard let hex = linkColor?.trimmingCharacters(in: .whitespaces) else { return nil }
        var str = hex
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6 else { return nil }
        let r = String(str.prefix(2))
        let g = String(str.dropFirst(2).prefix(2))
        let b = String(str.dropFirst(4).prefix(2))
        // OSC 4 ; index ; rgb:RR/GG/BB ST  — set palette color
        // ESC ] 4 ; i ; rgb:... BEL
        let blue = "\u{1B}]4;4;rgb:\(r)/\(g)/\(b)\u{07}"
        let brightBlue = "\u{1B}]4;12;rgb:\(r)/\(g)/\(b)\u{07}"
        return blue + brightBlue
    }
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        var str = hex.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
