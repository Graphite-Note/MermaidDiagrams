/**
 * File: ReferenceDiagramColor.swift
 * ---------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's reading of a style's color (DiagramColor.init?(cssText:)), frozen as the
 *              reference: through the value's characters, trimmed and lowered.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The color a style value writes, as 0.7.0 read it.
enum ReferenceDiagramColor {
    static func color(cssText: String) -> DiagramColor? {
        let text = cssText.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            guard let color = Self.hexadecimalColor(String(text.dropFirst())) else { return nil }
            return color
        } else if text.hasPrefix("rgb"), let color = Self.functionalColor(text) {
            return color
        } else if text == "none" || text == "transparent" {
            return DiagramColor(red: 0, green: 0, blue: 0, alpha: 0)
        } else if let value = DiagramColor.cssColorNames[text] {
            return DiagramColor(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        } else {
            return nil
        }
    }

    private static func hexadecimalColor(_ digits: String) -> DiagramColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded: String
        switch digits.count {
        case 3, 4: expanded = digits.map { digit in "\(digit)\(digit)" }.joined()
        case 6, 8: expanded = digits
        default: return nil
        }
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        let hasOpacity = expanded.count == 8
        let shift: UInt64 = hasOpacity ? 8 : 0
        return DiagramColor(red: Double(value >> (16 + shift) & 0xFF) / 255, green: Double(value >> (8 + shift) & 0xFF) / 255,
                            blue: Double(value >> shift & 0xFF) / 255, alpha: hasOpacity ? Double(value & 0xFF) / 255 : 1)
    }

    /// `rgb(51, 51, 51)`, `rgba(51 51 51 / 50%)` and `rgb(20%, 20%, 20%)`.
    private static func functionalColor(_ text: String) -> DiagramColor? {
        guard let opening = text.firstIndex(of: "("), text.hasSuffix(")"), ["rgb", "rgba"].contains(String(text[..<opening])) else { return nil }
        let inside = text[text.index(after: opening)..<text.index(before: text.endIndex)]
        let parts = inside.split(whereSeparator: { character in character == "," || character == " " || character == "/" }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var channels: [Double] = []
        for part in parts.prefix(3) {
            guard let channel = number(part, fullScale: 255) else { return nil }
            channels.append(min(1, max(0, channel)))
        }
        let alpha = parts.count == 4 ? number(parts[3], fullScale: 1).map { opacity in min(1, max(0, opacity)) } : 1
        guard let alpha else { return nil }
        return DiagramColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// A number out of `fullScale`, or a percentage.
    private static func number(_ text: String, fullScale: Double) -> Double? {
        if text.hasSuffix("%") { return Double(text.dropLast()).map { percentage in percentage / 100 } }
        return Double(text).map { value in value / fullScale }
    }
}
