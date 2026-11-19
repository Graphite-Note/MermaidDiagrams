/**
 * File: DiagramTextFitting.swift
 * ------------------------------
 * Layer: Core
 * Description: Fits one line of text into a width as Pele's fit-text does: the font shrinks down to a smallest size, and
 *              then the text is cut and ends in an ellipsis.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// One line of text fitted into a width: the text as it is drawn (cut and ending in `…` when it did not fit at the
/// smallest size), the font size it is drawn in and its width at that size.
struct DiagramFittedText: Equatable, Sendable {
    let text: String
    let fontSize: CGFloat
    let width: CGFloat

    /// The text as a one-line block, its center at the origin.
    var block: DiagramTextBlock {
        DiagramTextBlock(line: text, width: width, fontSize: fontSize)
    }
}

/// Fits a line of text into a width, as Pele's `common/fit-text.ts` does (a packet's fields, a treemap's boxes): first
/// by shrinking the font by whole points down to a smallest size, then by cutting the text and adding an ellipsis. Each
/// width is measured at the size the text would be drawn at (`DiagramTextMeasurerSizes`), so that small text, which Core
/// Text draws wider than in proportion, still fits.
enum DiagramTextFitting {
    private static let ellipsis = "\u{2026}"

    /// `text` fitted into `maximumWidth` starting at `fontSize` and not below `minimumFontSize`, measured as `measurers`
    /// measure it; nil when the text is empty, no width is left, or not even one character fits.
    static func fitted<Measurer: DiagramTextMeasuring>(_ text: String, maximumWidth: CGFloat, fontSize: CGFloat, minimumFontSize: CGFloat,
                                                      measurers: inout DiagramTextMeasurerSizes<Measurer>) -> DiagramFittedText? {
        guard !text.isEmpty, maximumWidth > 0, measurers.measurer.fontSize > 0 else { return nil }
        var width = measurers.width(of: text, atFontSize: fontSize)
        if width <= maximumWidth { return DiagramFittedText(text: text, fontSize: fontSize, width: width) }
        // Width grows with the font size, so one division lands on the right size or just above it.
        var size = max(minimumFontSize, (fontSize * maximumWidth / width).rounded(.down))
        while size >= minimumFontSize {
            width = measurers.width(of: text, atFontSize: size)
            if width <= maximumWidth { return DiagramFittedText(text: text, fontSize: size, width: width) }
            size -= 1
        }
        return cut(text, maximumWidth: maximumWidth, fontSize: minimumFontSize, measurers: &measurers)
    }

    /// `fitted(_:maximumWidth:fontSize:minimumFontSize:measurers:)` with the sizes of one measurer.
    static func fitted(_ text: String, maximumWidth: CGFloat, fontSize: CGFloat, minimumFontSize: CGFloat,
                       measurer: some DiagramTextMeasuring) -> DiagramFittedText? {
        var measurers = DiagramTextMeasurerSizes(measurer)
        return fitted(text, maximumWidth: maximumWidth, fontSize: fontSize, minimumFontSize: minimumFontSize, measurers: &measurers)
    }

    /// The longest start of `text` that ends in `…` and fits `maximumWidth` at `fontSize`, found by halving.
    private static func cut<Measurer: DiagramTextMeasuring>(_ text: String, maximumWidth: CGFloat, fontSize: CGFloat,
                                                           measurers: inout DiagramTextMeasurerSizes<Measurer>) -> DiagramFittedText? {
        let characters = Array(text.unicodeScalars)
        func start(_ length: Int) -> String {
            trimmedAtEnd(String(String.UnicodeScalarView(characters[..<length]))) + ellipsis
        }
        // The longest start that fits is found by doubling the length until one does not, then halving: a long text is
        // measured only as far as the width reaches.
        var low = 0
        var high = 1
        while high < characters.count - 1, measurers.width(of: start(high), atFontSize: fontSize) <= maximumWidth {
            low = high
            high *= 2
        }
        high = min(high, characters.count - 1)
        while low < high {
            let middle = (low + high + 1) / 2
            if measurers.width(of: start(middle), atFontSize: fontSize) <= maximumWidth { low = middle } else { high = middle - 1 }
        }
        guard low > 0 else { return nil }
        let cutText = start(low)
        let cutWidth = measurers.width(of: cutText, atFontSize: fontSize)
        return cutWidth <= maximumWidth ? DiagramFittedText(text: cutText, fontSize: fontSize, width: cutWidth) : nil
    }

    /// `text` without the white space JavaScript's `trimEnd` removes from its end.
    private static func trimmedAtEnd(_ text: String) -> String {
        var bytes = Array(text.utf8)[...]
        while case let length = JavaScriptWhitespace.lengthOfLast(in: bytes), length > 0 { bytes = bytes.dropLast(length) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// One line of `text` at `fontSize`, measured as `measurer` measures it at that size, its center at the origin.
    static func block(of text: String, fontSize: CGFloat, measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        var measurers = DiagramTextMeasurerSizes(measurer)
        return measurers.block(of: text, fontSize: fontSize)
    }

    /// The width of `text` at `fontSize` where the measurer's own size differs.
    static func width(of text: String, atFontSize fontSize: CGFloat, measurer: some DiagramTextMeasuring) -> CGFloat {
        var measurers = DiagramTextMeasurerSizes(measurer)
        return measurers.width(of: text, atFontSize: fontSize)
    }
}

extension DiagramTextBlock {
    /// One line at `fontSize` that is `width` wide, its line as high as Pele's lines are (one and a half times the size,
    /// rounded), its center at the origin.
    init(line: String, width: CGFloat, fontSize: CGFloat) {
        lines = [line]
        lineWidths = [width]
        self.fontSize = fontSize
        lineHeight = (fontSize * CoreTextDiagramTextMeasurer.lineHeightRatio).rounded()
        center = .zero
    }
}
