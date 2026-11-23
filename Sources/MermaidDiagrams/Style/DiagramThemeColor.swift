/**
 * File: DiagramThemeColor.swift
 * -----------------------------
 * Layer: Core
 * Description: A color a diagram's theme variables give one of its series, accepted only as Pele's safeColor accepts it:
 *              a color that can load nothing, end no declaration and read none of the page's variables but Pele's.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// A series color a diagram's theme variables set (`pie1: '#ffeb3b'`, `cScale0: oklch(70% 0.1 200)`), as CSS writes it.
/// Pele writes it into its SVG's style as it is (`--pele-series-1:#ffeb3b`), so a browser resolves it; `DiagramSceneRenderer`
/// resolves it as a browser does where it can (`DiagramSeriesColors.palette(over:)`).
public struct DiagramThemeColor: Hashable, Sendable {
    /// The value as written, without the whitespace around it: what an SVG writes.
    public let cssText: String
    /// What it is read as, to paint it.
    let expression: DiagramThemeColorExpression

    /// The color `cssText` writes, or nil for a value Pele's `safeColor` refuses, which leaves its series in the theme's
    /// color: up to 200 letters, digits, `_`, whitespace and `#%.,+-/()`; without a parenthesis a hexadecimal color, a
    /// CSS color name, `transparent` or `currentColor`; with them, balanced parentheses, only CSS's color functions
    /// (`rgb()`, `hsl()`, `hwb()`, `lab()`, `lch()`, `oklab()`, `oklch()`, `color()`, `color-mix()`, `light-dark()`,
    /// with their `a` forms) and `var()`, and `var()` only of Pele's own variables (`--pele-…`).
    public init?(cssText written: String) {
        let color = String(JavaScriptWhitespace.trimmed(Substring(written)))
        guard Self.isSafe(color) else { return nil }
        cssText = color
        expression = DiagramThemeColorExpression.read(Substring(color))
    }

    static func isSafe(_ color: String) -> Bool {
        guard (1...maximumLength).contains(color.utf16.count), color.unicodeScalars.allSatisfy(isAllowed) else { return false }
        guard color.contains("(") else { return isPlainColor(color) }
        var depth = 0
        for character in color {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0 && functionNames(in: color).allSatisfy { name in allowedFunctions.contains(name.lowercased()) }
            && variableNames(in: color).allSatisfy { name in name.hasPrefix("--pele-") }
    }

    /// Pele's `plainColor`: a hexadecimal color or one of CSS's named colors, `transparent` or `currentcolor`.
    private static func isPlainColor(_ raw: String) -> Bool {
        let value = String(JavaScriptWhitespace.trimmed(Substring(raw))).lowercased()
        let digits = value.dropFirst()
        let isHexadecimal = value.hasPrefix("#") && [3, 4, 6, 8].contains(digits.count) && digits.allSatisfy { digit in digit.isASCII && digit.isHexDigit }
        return isHexadecimal || DiagramSeriesInk.isNamedColor(value) || value == "transparent" || value == "currentcolor"
    }

    /// The name before each `(`, as Pele's pattern `([\w-]*)\s*\(` finds them one after another: the run of word
    /// characters and `-` just before it, whitespace between them allowed, never reaching back past the last `(`.
    static func functionNames(in color: String) -> [Substring] {
        let scalars = Array(color.unicodeScalars)
        var names: [Substring] = []
        var searchStart = 0
        for (index, scalar) in scalars.enumerated() where scalar == "(" {
            var nameEnd = index
            while nameEnd > searchStart, JavaScriptWhitespace.contains(scalars[nameEnd - 1]) { nameEnd -= 1 }
            var nameStart = nameEnd
            while nameStart > searchStart, isNameScalar(scalars[nameStart - 1]) { nameStart -= 1 }
            names.append(Substring(String(String.UnicodeScalarView(scalars[nameStart..<nameEnd]))))
            searchStart = index + 1
        }
        return names
    }

    /// The name after each `var(`, in any case, as Pele's pattern `var\(\s*([\w-]*)` finds them.
    static func variableNames(in color: String) -> [Substring] {
        let scalars = Array(color.unicodeScalars)
        let opening = Array("var(".unicodeScalars)
        var names: [Substring] = []
        var index = 0
        while index + opening.count <= scalars.count {
            let isOpening = zip(scalars[index..<index + opening.count], opening).allSatisfy { scalar, expected in
                scalar.properties.lowercaseMapping == String(expected)
            }
            guard isOpening else {
                index += 1
                continue
            }
            index += opening.count
            while index < scalars.count, JavaScriptWhitespace.contains(scalars[index]) { index += 1 }
            let start = index
            while index < scalars.count, isNameScalar(scalars[index]) { index += 1 }
            names.append(Substring(String(String.UnicodeScalarView(scalars[start..<index]))))
        }
        return names
    }

    /// JavaScript's `\w` and `-`.
    private static func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (MermaidByte.isLetter(UInt8(scalar.value)) || MermaidByte.isDigit(UInt8(scalar.value)) || scalar == "_" || scalar == "-")
    }

    /// Pele's `^[\w\s#%.,+\-/()]{1,200}$`, one scalar at a time.
    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        isNameScalar(scalar) || JavaScriptWhitespace.contains(scalar) || "#%.,+/()".unicodeScalars.contains(scalar)
    }

    private static let maximumLength = 200
    private static let allowedFunctions: Set<String> = [
        "rgb", "rgba", "hsl", "hsla", "hwb", "lab", "lch", "oklab", "oklch", "color", "color-mix", "light-dark", "var",
    ]
}
