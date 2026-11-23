/**
 * File: TreemapClassTextStyle.swift
 * ---------------------------------
 * Layer: Core
 * Description: What a treemap's `classDef` sets of its nodes' text, as Pele reads it: a font size, a weight and a slant,
 *              and whether the text takes the ink of a fill the class sets.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation

/// What a treemap class sets of its boxes' text: `font-size` (a size of 1 to 200 points written as a number or in `px`, at
/// which the names and values are written and cut rather than shrunk), `font-weight` (bold from `bold`, `bolder` or 600 up)
/// and `font-style` (`italic`). Nil where the class does not set it; the last of a property written twice wins.
public struct TreemapClassTextStyle: Equatable, Sendable {
    public internal(set) var fontSize: CGFloat?
    public internal(set) var isBold: Bool?
    public internal(set) var isItalic: Bool?
    /// Whether the class sets its boxes' fill with a declaration Pele keeps (`fill:none`, `fill:#ff0`), whether or not
    /// this package reads its color: Pele's ink on that fill then colors the text, never its ink on a series color
    /// (`setsFill` in its treemap renderer). Nil where no class sets a fill.
    var setsFill: Bool?

    /// A style that sets nothing.
    public init() {}

    init(fontSize: CGFloat?, isBold: Bool?, isItalic: Bool?) {
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
    }

    /// The largest font size a class may set, as Pele allows.
    static let largestFontSize: CGFloat = 200

    /// This style with what `later` sets over it, property by property.
    func overridden(by later: TreemapClassTextStyle) -> TreemapClassTextStyle {
        var style = self
        style.fontSize = later.fontSize ?? fontSize
        style.isBold = later.isBold ?? isBold
        style.isItalic = later.isItalic ?? isItalic
        style.setsFill = later.setsFill ?? setsFill
        return style
    }

    /// Reads one declaration's property and value when the property is a font size, weight or style; nil for another
    /// property. `.some(false)` when it is one of them and its value is not used: unsafe, empty, or a size that is not a
    /// number of points from 1 to 200 (`2em`), which Pele would leave to the browser.
    mutating func read(property: String, value written: String) -> Bool? {
        guard ["font-size", "font-weight", "font-style"].contains(property) else { return nil }
        let value = MermaidByte.withoutImportance(written).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !Self.isUnsafe(value) else { return false }
        switch property {
        case "font-size":
            fontSize = Self.pointSize(value)
            return fontSize != nil
        case "font-weight":
            isBold = value == "bold" || value == "bolder" || (Double(value).map { weight in weight >= 600 } ?? false)
        default:
            isItalic = value == "italic"
        }
        return true
    }

    /// `14` or `14px`: digits and points, from more than 0 to 200.
    private static func pointSize(_ value: String) -> CGFloat? {
        let digits = value.hasSuffix("px") ? String(value.dropLast(2)) : value
        guard !digits.isEmpty, digits.allSatisfy({ character in character.isASCII && (character.isNumber || character == ".") }),
              let size = JavaScriptNumberReading.parseFloat(Array(digits.utf8)[...]), size > 0, CGFloat(size) <= largestFontSize else { return nil }
        return CGFloat(size)
    }

    /// Notes a `fill` declaration as Pele's `resolveStyle` keeps it: a value that is not empty once `!important` is taken
    /// out, nothing unsafe in it and no character XML refuses.
    mutating func readFill(value written: String) {
        let value = MermaidByte.withoutImportance(written).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !Self.isUnsafe(value), !value.unicodeScalars.contains(where: Self.isRefusedByXML) else { return }
        setsFill = true
    }

    /// Pele's `RE_INVALID_XML`: the control characters other than tab, line feed and carriage return, and U+FFFE and
    /// U+FFFF (a Swift string holds no lone surrogate).
    private static func isRefusedByXML(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return value <= 0x08 || value == 0x0B || value == 0x0C || (0x0E...0x1F).contains(value) || value == 0x7F || value == 0xFFFE || value == 0xFFFF
    }

    /// What Pele refuses in a style's value: a resource, a script, markup or the end of a declaration.
    private static func isUnsafe(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let unsafeParts = ["javascript:", "@import", "image-set", "/*", "<", ">", "{", "}", ";", "\\"]
        if unsafeParts.contains(where: { part in lowered.contains(part) }) { return true }
        return lowered.range(of: #"(url|expression)\s*\("#, options: .regularExpression) != nil
    }
}
