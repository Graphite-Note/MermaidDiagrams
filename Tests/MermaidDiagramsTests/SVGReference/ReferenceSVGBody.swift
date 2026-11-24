/**
 * File: ReferenceSVGBody.swift
 * ----------------------------
 * Layer: Tests
 * Description: 0.7.0's writing of a scene's items as SVG elements (DiagramSVGBody of de81532), kept unchanged but
 *              for its names as part of the reference writer.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// The elements of an SVG document's body, written item by item into `content`; the gradients they name are defined
/// first, in `<defs>` (`appendDefinitions(of:)`), numbered in the order the items use them.
struct ReferenceSVGBody: ~Copyable {
    private var paints: ReferenceSVGPaintTexts
    let identifierPrefix: String
    var content: ReferenceSVGBuffer
    /// How many gradient fills the items written so far used.
    private var gradientCount = 0

    init(colors: DiagramSVGColors, identifierPrefix: String, content: consuming ReferenceSVGBuffer) {
        paints = ReferenceSVGPaintTexts(colors: colors)
        self.identifierPrefix = identifierPrefix
        self.content = content
    }

    /// The system's monospaced fonts, behind Pele's `--pele-font-mono` when the colors are Pele's variables.
    private var monospacedFontFamily: StaticString {
        switch paints.colors {
        case .palette: "ui-monospace,SFMono-Regular,Menlo,monospace"
        case .peleVariables: "var(--pele-font-mono,ui-monospace,SFMono-Regular,Menlo,monospace)"
        }
    }

    mutating func referenceText(of paint: DiagramPaint) -> ReferenceSVGPaintText {
        paints.referenceText(of: paint)
    }

    mutating func add(_ item: DiagramSceneItem) {
        switch item {
        case .shape(let shape): add(shape)
        case .text(let text): add(text)
        }
    }

    private mutating func add(_ shape: DiagramSceneShape) {
        content.append("<path class=\"pele-")
        content.append(shape.part.rawValue)
        content.append("\" d=\"")
        content.appendPathData(shape.path)
        content.append("\"")
        switch shape.painting {
        case .fill(let paint):
            appendFill(paints.referenceText(of: paint))
        case .stroke(let paint, let stroke):
            content.append(" fill=\"none\"")
            appendStrokeAttributes(paints.referenceText(of: paint), stroke)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            appendFill(paints.referenceText(of: fillPaint))
            appendStrokeAttributes(paints.referenceText(of: strokePaint), stroke)
        case .gradientFill(let gradient):
            gradientCount += 1
            content.append(" fill=\"url(#")
            Self.appendGradientIdentifier(prefix: identifierPrefix, number: gradientCount, into: &content)
            content.append(")\"")
            content.appendOpacity(gradient.opacity, attribute: "fill-opacity")
        }
        content.append("/>")
    }

    /// ` fill="…"` and its opacity.
    private mutating func appendFill(_ paint: ReferenceSVGPaintText) {
        content.append(" fill=\"")
        content.append(paint.color)
        content.append("\"")
        content.appendOpacity(paint.opacity, attribute: "fill-opacity")
    }

    private mutating func appendStrokeAttributes(_ paint: ReferenceSVGPaintText, _ stroke: DiagramStroke) {
        content.append(" stroke=\"")
        content.append(paint.color)
        content.append("\"")
        content.appendOpacity(paint.opacity, attribute: "stroke-opacity")
        content.append(" stroke-width=\"")
        content.appendNumber(stroke.lineWidth)
        content.append("\"")
        switch stroke.lineCap {
        case .round: content.append(" stroke-linecap=\"round\"")
        case .square: content.append(" stroke-linecap=\"square\"")
        default: break
        }
        switch stroke.lineJoin {
        case .round: content.append(" stroke-linejoin=\"round\"")
        case .bevel: content.append(" stroke-linejoin=\"bevel\"")
        default: break
        }
        if !stroke.dashLengths.isEmpty {
            content.append(" stroke-dasharray=\"")
            content.appendNumbers(stroke.dashLengths)
            content.append("\"")
        }
    }

    /// `<prefix>-gradient-<n>`, a gradient's id. Static, so that no copy of `self` is made beside its buffer passed
    /// `inout`.
    private static func appendGradientIdentifier(prefix: String, number: Int, into buffer: inout ReferenceSVGBuffer) {
        buffer.append(prefix)
        buffer.append("-gradient-")
        buffer.appendNumber(CGFloat(number))
    }

    /// `<defs>` with a definition of each gradient fill of `items`, numbered in their order as `add(_:)` numbers their
    /// uses, or nothing when no item has one: written before the items, where the document has them, so that nothing is
    /// put in before the body afterwards.
    mutating func appendDefinitions(of items: [DiagramSceneItem]) {
        var definitionCount = 0
        for item in items {
            guard case .shape(let shape) = item, case .gradientFill(let gradient) = shape.painting else { continue }
            if definitionCount == 0 { content.append("<defs>") }
            definitionCount += 1
            appendGradientDefinition(gradient, number: definitionCount)
        }
        if definitionCount > 0 { content.append("</defs>") }
    }

    /// A gradient across the page between its two points, the end colors carried on beyond them (SVG's `pad`).
    private mutating func appendGradientDefinition(_ gradient: DiagramLinearGradient, number: Int) {
        let start = paints.referenceText(of: gradient.startPaint)
        let end = paints.referenceText(of: gradient.endPaint)
        content.append("<linearGradient id=\"")
        Self.appendGradientIdentifier(prefix: identifierPrefix, number: number, into: &content)
        content.append("\" gradientUnits=\"userSpaceOnUse\" x1=\"")
        content.appendNumber(gradient.startPoint.x)
        content.append("\" y1=\"")
        content.appendNumber(gradient.startPoint.y)
        content.append("\" x2=\"")
        content.appendNumber(gradient.endPoint.x)
        content.append("\" y2=\"")
        content.appendNumber(gradient.endPoint.y)
        content.append("\"><stop offset=\"0\" stop-color=\"")
        content.append(start.color)
        content.append("\"")
        content.appendOpacity(start.opacity, attribute: "stop-opacity")
        content.append("/><stop offset=\"1\" stop-color=\"")
        content.append(end.color)
        content.append("\"")
        content.appendOpacity(end.opacity, attribute: "stop-opacity")
        content.append("/></linearGradient>")
    }

    /// One `text` per placed text, centered on each line's middle; several lines in `tspan`s. Each keeps its spaces
    /// (`xml:space="preserve"`), as Core Text measured and drew them: SVG would otherwise run several into one and drop
    /// those at a line's ends, which moves centered text.
    private mutating func add(_ text: DiagramSceneText) {
        let paint = paints.referenceText(of: text.paint)
        if let outline = text.outline {
            // The outline is a text of its own under the text, as Pele writes it: no fill, the stroke in the outline's paint.
            let outlinePaint = paints.referenceText(of: outline.paint)
            appendTextOpening(text) { body in
                body.content.append(" fill=\"none\" xml:space=\"preserve\"")
                body.appendStrokeAttributes(outlinePaint, DiagramStroke(lineWidth: outline.lineWidth, lineJoin: .round))
            }
            addLines(of: text.block)
        }
        appendTextOpening(text) { body in
            body.content.append(" fill=\"")
            body.content.append(paint.color)
            body.content.append("\" xml:space=\"preserve\"")
            body.content.appendOpacity(paint.opacity, attribute: "fill-opacity")
        }
        addLines(of: text.block)
    }

    /// `<text` and its attributes: its class and size, its painting, then its emphasis and rotation.
    private mutating func appendTextOpening(_ text: DiagramSceneText, painting: (inout ReferenceSVGBody) -> Void) {
        content.append("<text class=\"pele-")
        content.append(text.part.rawValue)
        content.append("\" font-size=\"")
        content.appendNumber(text.block.fontSize)
        content.append("\"")
        painting(&self)
        if text.isBold { content.append(" font-weight=\"bold\"") }
        if text.isItalic { content.append(" font-style=\"italic\"") }
        if text.isMonospaced { appendFontFamily() }
        if let rotation = text.rotation {
            let center = text.block.center
            content.append(" transform=\"rotate(")
            content.appendNumber(rotation * 180 / .pi)
            content.append(byte: UInt8(ascii: " "))
            content.appendNumber(center.x)
            content.append(byte: UInt8(ascii: " "))
            content.appendNumber(center.y)
            content.append(")\"")
        }
    }

    private mutating func appendFontFamily() {
        content.append(" font-family=\"")
        content.append(monospacedFontFamily)
        content.append("\"")
    }

    /// ` x="…" y="…"`: a line's middle and its baseline, as `DiagramSceneText.lines` places them (the same arithmetic,
    /// without making the lines).
    private mutating func appendPosition(ofLine index: Int, in block: DiagramTextBlock, top: CGFloat) {
        let middle = top + (CGFloat(index) + 0.5) * block.lineHeight
        content.append(" x=\"")
        content.appendNumber(block.center.x)
        content.append("\" y=\"")
        content.appendNumber(middle + block.fontSize * DiagramTextDrawing.baselineShiftRatio)
        content.append("\"")
    }

    /// The rest of a `text` whose opening is written: one line in the `text` itself, several in `tspan`s. A text whose
    /// lines have runs in their emphasis writes each line as Pele writes a label's spans: a `tspan` at the line's middle
    /// for its first run and one after it for each other run, with the run's weight, slant or font.
    private mutating func addLines(of block: DiagramTextBlock) {
        let top = block.center.y - block.size.height / 2
        if let lineRuns = block.lineRuns {
            addLines(of: block, runs: lineRuns, top: top)
            return
        }
        if block.lines.count == 1 {
            appendPosition(ofLine: 0, in: block, top: top)
            content.append(" text-anchor=\"middle\">")
            content.appendEscaped(block.lines[0])
            content.append("</text>")
            return
        }
        content.append(" text-anchor=\"middle\">")
        for (index, line) in block.lines.enumerated() {
            content.append("<tspan")
            appendPosition(ofLine: index, in: block, top: top)
            content.append(">")
            content.appendEscaped(line)
            content.append("</tspan>")
        }
        content.append("</text>")
    }

    /// The lines of a text whose lines have runs: each run a `tspan`, the first of a line at the line's middle.
    private mutating func addLines(of block: DiagramTextBlock, runs lineRuns: [[DiagramTextRun]], top: CGFloat) {
        content.append(" text-anchor=\"middle\">")
        for lineIndex in block.lines.indices {
            let runs = lineRuns[lineIndex]
            guard !runs.isEmpty else {
                content.append("<tspan")
                appendPosition(ofLine: lineIndex, in: block, top: top)
                content.append("></tspan>")
                continue
            }
            for (index, run) in runs.enumerated() {
                content.append("<tspan")
                if index == 0 { appendPosition(ofLine: lineIndex, in: block, top: top) }
                appendRunAttributes(run.style)
                content.append(">")
                content.appendEscaped(run.text)
                content.append("</tspan>")
            }
        }
        content.append("</text>")
    }

    /// The attributes of a run's emphasis, Pele's `spanStyle`.
    private mutating func appendRunAttributes(_ style: DiagramTextStyle) {
        if style.contains(.bold) { content.append(" font-weight=\"bold\"") }
        if style.contains(.italic) { content.append(" font-style=\"italic\"") }
        if style.contains(.monospaced) { appendFontFamily() }
    }
}
