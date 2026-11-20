/**
 * File: UseCaseLook.swift
 * -----------------------
 * Layer: Core
 * Description: What the styles of a use case diagram's node or relationship make of it, as Pele's resolveStyle reads
 *              them: its fill, outline and text colors, bold, italic and size, and the text color Pele's ink picks over
 *              a fill.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// The look a node's or a relationship's styles give it, its class styles first and its own after them.
public struct UseCaseLook: Equatable, Sendable {
    public let fill: DiagramColor?
    public let stroke: DiagramColor?
    public let strokeWidth: CGFloat?
    public let strokeDashLengths: [CGFloat]?
    public let textColor: DiagramColor?
    /// The dark or light text color Pele's ink picks over the fill, for text that sets no color.
    public let ink: DiagramColor?
    /// The color Pele's ink picks over the fill for a line on it.
    public let lineInk: DiagramColor?
    public let isBold: Bool
    public let isItalic: Bool
    /// `font-size`, in points, from above 0 to 200.
    public let fontSize: CGFloat?
    /// Whether `fill` is written, which keeps a boundary's fill at full opacity.
    public let setsFill: Bool
    /// Whether the fill paints anything (Pele's `paints`): written, not `none` or `transparent`, not fully clear.
    public let paintsFill: Bool
    /// `fill-opacity`, when written as an amount.
    public let fillOpacity: CGFloat?
    /// `stroke-opacity` and `opacity`, 1 when not written as an amount.
    public let strokeOpacity: CGFloat
    public let opacity: CGFloat
    /// Whether the stroke is written `none` or `transparent`: such a line has no casing (Pele's `casing`).
    public let hidesStroke: Bool

    static let none = UseCaseLook(styles: [])

    /// The largest `font-size` Pele takes.
    static let largestFontSize: CGFloat = 200

    init(styles: [String]) {
        let declarations = styles.compactMap { style -> VennStyleDeclaration? in
            let parts = style.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return VennStyleDeclaration(property: UseCaseCharacters.trimmed(String(parts[0])).lowercased(), value: String(parts[1]))
        }
        let appearance = VennAppearance(declarations)
        fill = appearance.fill
        stroke = appearance.stroke
        strokeWidth = appearance.strokeWidth
        strokeDashLengths = appearance.strokeDashLengths
        textColor = appearance.textColor
        ink = appearance.ink(forTextOf: appearance)
        lineInk = appearance.ink(forTextOf: VennAppearance())
        isBold = appearance.isBold
        isItalic = appearance.isItalic
        let applied = declarations.filter { declaration in Self.value(of: declaration) != nil }
        let writtenFill = applied.last { declaration in declaration.property == "fill" }.flatMap(Self.value(of:))
        setsFill = writtenFill != nil
        let fillValue = writtenFill?.lowercased()
        let shownFill = (appearance.fillOpacity ?? 1) * (appearance.opacity ?? 1)
        paintsFill = fillValue != nil && fillValue != "none" && fillValue != "transparent" && (appearance.fill?.alpha ?? 1) * shownFill > 0
        fillOpacity = appearance.fillOpacity.map { amount in CGFloat(amount) }
        strokeOpacity = CGFloat(appearance.strokeOpacity ?? 1)
        opacity = CGFloat(appearance.opacity ?? 1)
        let writtenStroke = applied.last { declaration in declaration.property == "stroke" }.flatMap(Self.value(of:))
        hidesStroke = writtenStroke == "none" || writtenStroke == "transparent"
        fontSize = applied.last { declaration in declaration.property == "font-size" }.flatMap(Self.value(of:)).flatMap(Self.fontSize(_:))
    }

    /// How much of a fill shows: its `fill-opacity` (else `usual`) times its `opacity`.
    func fillAmount(usual: CGFloat = 1) -> CGFloat { (fillOpacity ?? usual) * opacity }

    /// How much of a stroke shows: its `stroke-opacity` times its `opacity`.
    var strokeAmount: CGFloat { strokeOpacity * opacity }

    /// The value Pele's `resolveStyle` keeps: `!important` taken out and trimmed, nil when empty or unsafe.
    private static func value(of declaration: VennStyleDeclaration) -> String? {
        let value = UseCaseCharacters.trimmed(declaration.value.replacingOccurrences(of: "!important", with: "", options: .caseInsensitive))
        return value.isEmpty || VennAppearance.isUnsafe(value) ? nil : value
    }

    /// `16`, `16px`, `12.5`: a size above 0 and at most 200.
    private static func fontSize(_ value: String) -> CGFloat? {
        let digits = value.hasSuffix("px") ? String(value.dropLast(2)) : value
        guard !digits.isEmpty, digits.utf8.allSatisfy({ byte in (byte >= 0x30 && byte <= 0x39) || byte == 0x2E }),
              let size = Double(digits.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false).prefix(2).joined(separator: ".")),
              size > 0, CGFloat(size) <= largestFontSize else { return nil }
        return CGFloat(size)
    }
}
