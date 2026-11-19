/**
 * File: DiagramSVGSyntax.swift
 * ----------------------------
 * Layer: Core
 * Description: The pieces of SVG text the writer joins: escaped text, compact numbers and a path's data.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Escapes text, writes numbers and writes paths for `DiagramSVGWriter`.
enum DiagramSVGSyntax {
    /// `text` for an attribute's value or an element's content: `&`, `<`, `>`, `"` and `'` as entities, and the
    /// characters XML 1.0 has no place for (control characters other than tab, line feed and carriage return, U+FFFE and
    /// U+FFFF) left out.
    static func escaped(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: needsEscaping) else { return text }
        var escaped = ""
        escaped.reserveCapacity(text.utf8.count + 16)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: if isAllowedInXML(scalar) { escaped.unicodeScalars.append(scalar) }
            }
        }
        return escaped
    }

    private static func needsEscaping(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "&", "<", ">", "\"", "'": true
        default: !isAllowedInXML(scalar)
        }
    }

    private static func isAllowedInXML(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x9, 0xA, 0xD: true
        case 0x0...0x1F, 0x7F, 0xFFFE, 0xFFFF: false
        default: true
        }
    }

    /// `value` to two decimals without trailing zeros (`12`, `12.5`, `-0.25`), as Pele writes coordinates; 0 for a value
    /// that is not finite.
    static func number(_ value: CGFloat) -> String {
        guard value.isFinite, abs(value) < 1e12 else { return "0" }
        let hundredths = Int((value * 100).rounded())
        guard hundredths != 0 else { return "0" }
        let magnitude = abs(hundredths)
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let sign = hundredths < 0 ? "-" : ""
        switch fraction {
        case 0: return "\(sign)\(whole)"
        case let tenths where tenths.isMultiple(of: 10): return "\(sign)\(whole).\(tenths / 10)"
        case ..<10: return "\(sign)\(whole).0\(fraction)"
        default: return "\(sign)\(whole).\(fraction)"
        }
    }

    /// A path's data: `M`, `L`, `Q`, `C` and `Z` with absolute coordinates.
    static func pathData(_ path: CGPath) -> String {
        var data = ""
        path.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: data += "M" + pair(points[0])
            case .addLineToPoint: data += "L" + pair(points[0])
            case .addQuadCurveToPoint: data += "Q" + pair(points[0]) + " " + pair(points[1])
            case .addCurveToPoint: data += "C" + pair(points[0]) + " " + pair(points[1]) + " " + pair(points[2])
            case .closeSubpath: data += "Z"
            @unknown default: break
            }
        }
        return data
    }

    private static func pair(_ point: CGPoint) -> String {
        number(point.x) + " " + number(point.y)
    }
}
