/**
 * File: DiagramSVGBody.swift
 * --------------------------
 * Layer: Core
 * Description: Writes a scene's items as SVG elements into the document's buffer: a path per shape (one for a fill and
 *              its stroke), a text per placed text, and the gradients they name.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 23/11/2026
 */

import CoreGraphics

/// The elements of an SVG document's body, written item by item into `content`, and the gradients they name, into
/// `definitions`.
struct DiagramSVGBody {
    private var paints: DiagramSVGPaintTexts
    let identifierPrefix: String
    var content: DiagramSVGBuffer
    var definitions = DiagramSVGBuffer()
    private var gradientCount = 0

    init(colors: DiagramSVGColors, identifierPrefix: String, content: DiagramSVGBuffer) {
        paints = DiagramSVGPaintTexts(colors: colors)
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

    mutating func text(of paint: DiagramPaint) -> DiagramSVGPaintText {
        paints.text(of: paint)
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
        content.appendPathData(shape.scenePath)
        content.append("\"")
        switch shape.painting {
        case .fill(let paint):
            appendFill(paints.text(of: paint))
        case .stroke(let paint, let stroke):
            content.append(" fill=\"none\"")
            appendStrokeAttributes(paints.text(of: paint), stroke)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            appendFill(paints.text(of: fillPaint))
            appendStrokeAttributes(paints.text(of: strokePaint), stroke)
        case .gradientFill(let gradient):
            gradientCount += 1
            addGradientDefinition(gradient)
            content.append(" fill=\"url(#")
            Self.appendGradientIdentifier(prefix: identifierPrefix, number: gradientCount, into: &content)
            content.append(")\"")
            content.appendOpacity(gradient.opacity, attribute: "fill-opacity")
        }
        content.append("/>")
    }

    /// ` fill="…"` and its opacity.
    private mutating func appendFill(_ paint: DiagramSVGPaintText) {
        content.append(" fill=\"")
        content.append(paint.color)
        content.append("\"")
        content.appendOpacity(paint.opacity, attribute: "fill-opacity")
    }

    private mutating func appendStrokeAttributes(_ paint: DiagramSVGPaintText, _ stroke: DiagramStroke) {
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

    /// `<prefix>-gradient-<n>`, the latest gradient's id. Static, as `self` passed to a method of its own while one of its
    /// buffers is passed `inout` is copied, buffers and all, which made each gradient copy the whole document.
    private static func appendGradientIdentifier(prefix: String, number: Int, into buffer: inout DiagramSVGBuffer) {
        buffer.append(prefix)
        buffer.append("-gradient-")
        buffer.appendNumber(CGFloat(number))
    }

    /// A gradient across the page between its two points, the end colors carried on beyond them (SVG's `pad`).
    private mutating func addGradientDefinition(_ gradient: DiagramLinearGradient) {
        let start = paints.text(of: gradient.startPaint)
        let end = paints.text(of: gradient.endPaint)
        definitions.append("<linearGradient id=\"")
        Self.appendGradientIdentifier(prefix: identifierPrefix, number: gradientCount, into: &definitions)
        definitions.append("\" gradientUnits=\"userSpaceOnUse\" x1=\"")
        definitions.appendNumber(gradient.startPoint.x)
        definitions.append("\" y1=\"")
        definitions.appendNumber(gradient.startPoint.y)
        definitions.append("\" x2=\"")
        definitions.appendNumber(gradient.endPoint.x)
        definitions.append("\" y2=\"")
        definitions.appendNumber(gradient.endPoint.y)
        definitions.append("\"><stop offset=\"0\" stop-color=\"")
        definitions.append(start.color)
        definitions.append("\"")
        definitions.appendOpacity(start.opacity, attribute: "stop-opacity")
        definitions.append("/><stop offset=\"1\" stop-color=\"")
        definitions.append(end.color)
        definitions.append("\"")
        definitions.appendOpacity(end.opacity, attribute: "stop-opacity")
        definitions.append("/></linearGradient>")
    }

    /// One `text` per placed text, centered on each line's middle; several lines in `tspan`s. Each keeps its spaces
    /// (`xml:space="preserve"`), as Core Text measured and drew them: SVG would otherwise run several into one and drop
    /// those at a line's ends, which moves centered text.
    private mutating func add(_ text: DiagramSceneText) {
        let paint = paints.text(of: text.paint)
        let hasRuns = text.styledRuns != nil
        if let outline = text.outline {
            // The outline is a text of its own under the text, as Pele writes it: no fill, the stroke in the outline's paint.
            let outlinePaint = paints.text(of: outline.paint)
            appendTextOpening(text) { body in
                body.content.append(" fill=\"none\" xml:space=\"preserve\"")
                body.appendStrokeAttributes(outlinePaint, DiagramStroke(lineWidth: outline.lineWidth, lineJoin: .round))
            }
            addLines(text.lines, hasRuns: hasRuns)
        }
        appendTextOpening(text) { body in
            body.content.append(" fill=\"")
            body.content.append(paint.color)
            body.content.append("\" xml:space=\"preserve\"")
            body.content.appendOpacity(paint.opacity, attribute: "fill-opacity")
        }
        addLines(text.lines, hasRuns: hasRuns)
    }

    /// `<text` and its attributes: its class and size, its painting, then its emphasis and rotation.
    private mutating func appendTextOpening(_ text: DiagramSceneText, painting: (inout DiagramSVGBody) -> Void) {
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

    /// ` x="…" y="…"`: a line's middle and its baseline.
    private mutating func appendPosition(_ line: DiagramSceneTextLine) {
        content.append(" x=\"")
        content.appendNumber(line.center.x)
        content.append("\" y=\"")
        content.appendNumber(line.baselineStart.y)
        content.append("\"")
    }

    /// The rest of a `text` whose opening is written: one line in the `text` itself, several in `tspan`s. A text whose
    /// lines have runs in their emphasis writes each line as Pele writes a label's spans: a `tspan` at the line's middle
    /// for its first run and one after it for each other run, with the run's weight, slant or font.
    private mutating func addLines(_ lines: [DiagramSceneTextLine], hasRuns: Bool) {
        if hasRuns {
            content.append(" text-anchor=\"middle\">")
            for line in lines {
                guard !line.runs.isEmpty else {
                    content.append("<tspan")
                    appendPosition(line)
                    content.append("></tspan>")
                    continue
                }
                for (index, run) in line.runs.enumerated() {
                    content.append("<tspan")
                    if index == 0 { appendPosition(line) }
                    appendRunAttributes(run.style)
                    content.append(">")
                    content.appendEscaped(run.text)
                    content.append("</tspan>")
                }
            }
            content.append("</text>")
            return
        }
        if lines.count == 1, let line = lines.first {
            appendPosition(line)
            content.append(" text-anchor=\"middle\">")
            content.appendEscaped(line.text)
            content.append("</text>")
            return
        }
        content.append(" text-anchor=\"middle\">")
        for line in lines {
            content.append("<tspan")
            appendPosition(line)
            content.append(">")
            content.appendEscaped(line.text)
            content.append("</tspan>")
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
