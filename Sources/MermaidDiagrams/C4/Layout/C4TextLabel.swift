/**
 * File: C4TextLabel.swift
 * -----------------------
 * Layer: Core
 * Description: Measures a C4 text as Pele's layoutLabel does, and the measurers of a C4 diagram's text: names and the
 *              title in bold, the rest at thirteen sixteenths of the size, a shape's kind a point smaller, a relation's
 *              technology in italic.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// A measured text as Pele's `layoutLabel` gives it: nothing for no text or an empty one; else its lines, broken at
/// `<br>`, a line break or a written `\n`, its tags dropped and its entity codes read, each wrapped at spaces past
/// `maximumWidth`. Lines of a text of more than one sit 1.3 times the size apart, rounded, where one line takes 1.5.
enum C4TextLabel {
    static func block(_ text: String?, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard let text, !text.isEmpty else { return nil }
        // The decoder breaks at a written `\\n` and trims each line before reading its codes, as Pele's layoutLabel does.
        return block(of: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
    }

    /// The text `text` of `diagram`, read from its bytes as `block(_:measurer:maximumWidth:)` reads its String.
    static func block(_ text: C4Text, in diagram: C4Diagram, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard !text.isNoneOrEmpty else { return nil }
        let label = diagram.withBytes(of: text) { bytes in DiagramLabelDecoder.label(fromUTF8: bytes, form: .plain) }
        return block(of: label, measurer: measurer, maximumWidth: maximumWidth)
    }

    /// `[text]`, as a type or a technology is written, or nil for no text or an empty one.
    static func bracketedBlock(_ text: C4Text, in diagram: C4Diagram, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard !text.isNoneOrEmpty else { return nil }
        return withBytes(before: Self.openingBracket, text, in: diagram, after: Self.closingBracket) { bytes in
            block(of: DiagramLabelDecoder.label(fromUTF8: bytes, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
        }
    }

    /// A relation's label as a dynamic diagram numbers it, `number: label`, or the label alone for number 0.
    static func numberedBlock(_ text: C4Text, number: Int, in diagram: C4Diagram, measurer: some DiagramTextMeasuring,
                              maximumWidth: CGFloat) -> DiagramTextBlock? {
        guard number > 0 else { return block(text, in: diagram, measurer: measurer, maximumWidth: maximumWidth) }
        return withBytes(before: Array("\(number): ".utf8), text, in: diagram, after: []) { bytes in
            block(of: DiagramLabelDecoder.label(fromUTF8: bytes, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
        }
    }

    /// Calls `body` with `prefix`, the bytes of `text` and `suffix` one after the other, in room taken on the stack.
    private static func withBytes<Result>(before prefix: [UInt8], _ text: C4Text, in diagram: C4Diagram, after suffix: [UInt8],
                                          _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
        let count = prefix.count + text.count + suffix.count
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: count) { room in
            var written = 0
            for byte in prefix { room[written] = byte; written += 1 }
            diagram.withBytes(of: text) { bytes in for byte in bytes { room[written] = byte; written += 1 } }
            for byte in suffix { room[written] = byte; written += 1 }
            return body(UnsafeBufferPointer(rebasing: room[0..<written]))
        }
    }

    private static let openingBracket: [UInt8] = [UInt8(ascii: "[")]
    private static let closingBracket: [UInt8] = [UInt8(ascii: "]")]

    /// A label measured, its lines with nothing on them still taking their height.
    private static func block(of label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock {
        let wrapped = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
        guard wrapped.lineCount == 0 else { return wrapped }
        // Lines with nothing on them still take their height, as Pele lays out each part between breaks.
        let lines = label.lineCount == 0 ? [""] : label.lines
        return DiagramTextBlock(lines: lines, lineWidths: lines.map { _ in CGFloat(0) }, fontSize: measurer.fontSize,
                                lineHeight: DiagramTextBlock.lineHeight(lineCount: lines.count, measurer: measurer))
    }
}

extension DiagramTextBlock? {
    /// The block's width and height, zero for none.
    var measuredWidth: CGFloat { self?.size.width ?? 0 }
    var measuredHeight: CGFloat { self?.size.height ?? 0 }
}

/// The measurers of a C4 diagram's text, Pele's sizes: the size in bold for names, headings and the title; Pele's
/// `small`, thirteen sixteenths of the size rounded, for technologies, descriptions, types and relations' labels; a point
/// less for a shape's kind; `small` in italic for a relation's technology.
struct C4Measurers<Measurer: DiagramTextMeasuring> {
    let name: Measurer
    let small: Measurer
    let smallest: Measurer
    let italicSmall: Measurer
}

extension C4Measurers where Measurer == CoreTextDiagramTextMeasurer {
    init(typography: DiagramTypography) {
        let small = typography.rowText
        let smallestSize = small.fontSize - 1
        self.init(name: typography.boldNodeText, small: small,
                  smallest: typography.axisText.fontSize == smallestSize ? typography.axisText : small.resized(to: smallestSize),
                  italicSmall: typography.planeMapText.italicRowText)
    }
}
