/**
 * File: DiagramThemeColorExpression.swift
 * ---------------------------------------
 * Layer: Core
 * Description: A theme color read as CSS reads it, to be painted: a color, a role of the palette a `var()` names, a
 *              `light-dark()` pair or a `color-mix()`, resolved only when a palette is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// A theme color's value as CSS Color 4 and 5 read it, short of what a palette decides: a color whose channels are known,
/// the text color (`currentColor`), a variable of Pele's (a palette's role, a series, or another with its fallback), a
/// choice between a light page's color and a dark page's, or a mixture. What this reading does not know (a `calc()`, a
/// `var()` inside a color's channels, a mixing space or a `color()` space it has no conversion for) is `unsupported`, and
/// its series keeps the theme's color when painted, where a browser may paint it.
indirect enum DiagramThemeColorExpression: Hashable, Sendable {
    case color(DiagramLinearColor)
    case currentColor
    case role(DiagramPaletteRole)
    /// `var(--pele-series-N)`, as the slot it names (N - 1), and its fallback.
    case series(slot: Int, fallback: DiagramThemeColorExpression?)
    /// `var()` of a variable no palette sets: its fallback, or nothing.
    case unknownVariable(fallback: DiagramThemeColorExpression?)
    case lightDark(light: DiagramThemeColorExpression, dark: DiagramThemeColorExpression)
    case mixture(DiagramColorMixture)
    case unsupported

    /// How deep functions may nest in a value read here: a value of at most 200 characters nests less than this in any
    /// color a browser reads.
    static let deepestNesting = 12

    /// The series slots it refers to, fallbacks and mixed colors included.
    var referencedSlots: Set<Int> {
        switch self {
        case .series(let slot, let fallback): Set([slot]).union(fallback?.referencedSlots ?? [])
        case .unknownVariable(let fallback): fallback?.referencedSlots ?? []
        case .lightDark(let light, let dark): light.referencedSlots.union(dark.referencedSlots)
        case .mixture(let mixture): mixture.first.referencedSlots.union(mixture.second.referencedSlots)
        case .color, .currentColor, .role, .unsupported: []
        }
    }

    /// `text` read; `unsupported` for what is not read here.
    static func read(_ text: Substring, depth: Int = 0) -> DiagramThemeColorExpression {
        let value = CSSColorSyntax.trimmed(text)
        guard depth < deepestNesting, !value.unicodeScalars.contains(where: CSSColorSyntax.isOtherWhitespace) else { return .unsupported }
        guard let opening = value.firstIndex(of: "(") else { return keyword(value.lowercased()) }
        guard value.hasSuffix(")") else { return .unsupported }
        let name = value[..<opening].lowercased()
        let arguments = value[value.index(after: opening)..<value.index(before: value.endIndex)]
        switch name {
        case "var": return variable(arguments, depth: depth)
        case "light-dark": return lightDark(arguments, depth: depth)
        case "color-mix": return DiagramColorMixture.read(arguments, depth: depth).map(DiagramThemeColorExpression.mixture) ?? .unsupported
        default: return DiagramColorFunction.read(name: name, arguments: arguments).map(DiagramThemeColorExpression.color) ?? .unsupported
        }
    }

    /// A hexadecimal color, a color name, `transparent` or `currentcolor`.
    private static func keyword(_ value: String) -> DiagramThemeColorExpression {
        if value == "currentcolor" { return .currentColor }
        guard let color = DiagramColor(cssText: value) else { return .unsupported }
        return .color(DiagramLinearColor(encoded: color))
    }

    /// `var(--name)` or `var(--name, fallback)`: a palette's role, a series, or another variable.
    private static func variable(_ arguments: Substring, depth: Int) -> DiagramThemeColorExpression {
        let comma = CSSColorSyntax.firstTopLevelComma(in: arguments)
        let name = CSSColorSyntax.trimmed(arguments[..<(comma ?? arguments.endIndex)])
        let fallback = comma.map { comma in read(arguments[arguments.index(after: comma)...], depth: depth + 1) }
        let seriesNumber = name.hasPrefix(seriesPrefix) ? name.dropFirst(seriesPrefix.count) : ""
        if let number = Int(seriesNumber), String(number) == seriesNumber, (1...DiagramSeriesColors.slotCount).contains(number) {
            return .series(slot: number - 1, fallback: fallback)
        }
        if let role = paletteRoles[String(name)] { return .role(role) }
        return .unknownVariable(fallback: fallback)
    }

    /// `light-dark(light, dark)`.
    private static func lightDark(_ arguments: Substring, depth: Int) -> DiagramThemeColorExpression {
        let pieces = CSSColorSyntax.topLevelPieces(of: arguments, separatedBy: ",")
        guard pieces.count == 2 else { return .unsupported }
        return .lightDark(light: read(pieces[0], depth: depth + 1), dark: read(pieces[1], depth: depth + 1))
    }

    private static let seriesPrefix = "--pele-series-"
    /// Pele's variables a palette sets, by their role.
    private static let paletteRoles: [String: DiagramPaletteRole] = [
        "--pele-bg": .background, "--pele-fg": .foreground, "--pele-line": .line, "--pele-surface": .surface,
        "--pele-surface-alt": .alternateSurface, "--pele-border": .border, "--pele-accent": .accent, "--pele-muted": .muted,
        "--pele-critical": .critical,
    ]
}

/// What CSS's syntax needs here: its own whitespace, and cutting a value at its top level, outside any parentheses.
enum CSSColorSyntax {
    /// Space, tab, line feed, carriage return and form feed.
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0C}"
    }

    /// JavaScript's whitespace that CSS does not take as whitespace, such as a no-break space: a value that holds one is
    /// not read here.
    static func isOtherWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        JavaScriptWhitespace.contains(scalar) && !isWhitespace(scalar)
    }

    static func trimmed(_ text: Substring) -> Substring {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { scalar in !isWhitespace(scalar) }),
              let last = scalars.lastIndex(where: { scalar in !isWhitespace(scalar) }) else { return text[text.endIndex...] }
        return Substring(scalars[first...last])
    }

    /// The first comma outside parentheses.
    static func firstTopLevelComma(in text: Substring) -> Substring.Index? {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0: return index
            default: break
            }
        }
        return nil
    }

    /// `text` cut at each `separator` outside parentheses, each piece trimmed.
    static func topLevelPieces(of text: Substring, separatedBy separator: Character) -> [Substring] {
        var pieces: [Substring] = []
        var depth = 0
        var start = text.startIndex
        for index in text.indices {
            switch text[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case separator where depth == 0:
                pieces.append(trimmed(text[start..<index]))
                start = text.index(after: index)
            default: break
            }
        }
        pieces.append(trimmed(text[start...]))
        return pieces
    }

    /// `text` cut at whitespace outside parentheses, with no empty piece.
    static func topLevelWords(of text: Substring) -> [Substring] {
        var words: [Substring] = []
        var depth = 0
        var start: Substring.Index?
        for index in text.indices {
            let character = text[index]
            if character == "(" { depth += 1 } else if character == ")" { depth -= 1 }
            let isSpace = depth == 0 && character.unicodeScalars.allSatisfy(isWhitespace)
            if isSpace, let wordStart = start {
                words.append(text[wordStart..<index])
                start = nil
            } else if !isSpace, start == nil {
                start = index
            }
        }
        if let start { words.append(text[start...]) }
        return words
    }
}
