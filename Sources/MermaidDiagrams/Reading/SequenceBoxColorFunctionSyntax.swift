/**
 * File: SequenceBoxColorFunctionSyntax.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Whether a sequence `box` line starts with a well-formed `rgb()`, `rgba()`, `hsl()` or `hsla()` color,
 *              as Pele checks it without a browser.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation

/// Pele's check of a CSS color function (`src/diagrams/sequence/colors.ts`): the name in lowercase right before the
/// parenthesis, the closing parenthesis last, three channels and maybe an alpha, with commas (legacy: numbers or
/// percentages alike in `rgb`, a hue then two percentages in `hsl`) or with spaces and `/ alpha` (modern, `none` allowed).
enum SequenceBoxColorFunctionSyntax {
    private enum TermKind {
        case invalid
        case number
        case percentage
        case angle
        case none
    }

    /// The longest function text Pele accepts.
    private static let maximumLength = 120

    static func isColorFunction(_ color: String) -> Bool {
        guard let opening = color.firstIndex(of: "(") else { return false }
        let name = color[..<opening]
        guard ["rgb", "rgba", "hsl", "hsla"].contains(name), color.count <= maximumLength,
              let closing = color.firstIndex(of: ")"), color.index(after: closing) == color.endIndex else { return false }
        let isHSL = name.hasPrefix("hsl")
        let inner = color[color.index(after: opening)..<closing].trimmingCharacters(in: .whitespacesAndNewlines)
        let isLegacy = inner.contains(",")
        var channels: [String]
        var alpha: String?
        if isLegacy {
            channels = inner.components(separatedBy: ",").map { part in part.trimmingCharacters(in: .whitespacesAndNewlines) }
            if channels.count == 4 { alpha = channels.removeLast() }
        } else {
            let halves = inner.components(separatedBy: "/")
            guard halves.count <= 2 else { return false }
            channels = halves[0].trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
            if channels.isEmpty { channels = [""] }
            if halves.count == 2 { alpha = halves[1].trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard channels.count == 3 else { return false }
        if let alpha, !isAlpha(alpha, isModern: !isLegacy) { return false }
        let kinds = channels.map(kind)
        if isLegacy {
            if isHSL { return (kinds[0] == .number || kinds[0] == .angle) && kinds[1] == .percentage && kinds[2] == .percentage }
            return (kinds[0] == .number || kinds[0] == .percentage) && kinds[1] == kinds[0] && kinds[2] == kinds[0]
        }
        return kinds.enumerated().allSatisfy { index, kind in
            kind == .number || kind == .none || (isHSL && index == 0 ? kind == .angle : kind == .percentage)
        }
    }

    private static func isAlpha(_ term: String, isModern: Bool) -> Bool {
        let termKind = kind(term)
        return termKind == .number || termKind == .percentage || (isModern && termKind == .none)
    }

    /// `none`, or Pele's `/^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?(%|deg|grad|rad|turn)?$/i`.
    private static func kind(_ term: String) -> TermKind {
        let lowered = term.lowercased()
        if lowered == "none" { return .none }
        var scalars = lowered.unicodeScalars[...]
        if let sign = scalars.first, sign == "+" || sign == "-" { scalars = scalars.dropFirst() }
        let isDigit = { (scalar: Unicode.Scalar) in ("0"..."9").contains(scalar) }
        let wholeDigits = scalars.prefix(while: isDigit).count
        scalars = scalars.dropFirst(wholeDigits)
        if scalars.first == "." {
            let fractionDigits = scalars.dropFirst().prefix(while: isDigit).count
            guard fractionDigits > 0 else { return .invalid }
            scalars = scalars.dropFirst(1 + fractionDigits)
        } else if wholeDigits == 0 {
            return .invalid
        }
        if scalars.first == "e" {
            var exponent = scalars.dropFirst()
            if let sign = exponent.first, sign == "+" || sign == "-" { exponent = exponent.dropFirst() }
            let exponentDigits = exponent.prefix(while: isDigit).count
            if exponentDigits > 0 { scalars = exponent.dropFirst(exponentDigits) }
        }
        switch UnicodeScalarText.string(scalars) {
        case "": return .number
        case "%": return .percentage
        case "deg", "grad", "rad", "turn": return .angle
        default: return .invalid
        }
    }
}
