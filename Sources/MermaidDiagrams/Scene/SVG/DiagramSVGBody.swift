/**
 * File: DiagramSVGBody.swift
 * --------------------------
 * Layer: Core
 * Description: Writes a scene's items as SVG elements into the document's buffer, the room of each element's fixed
 *              parts made sure of once: a path per shape (one for a fill and its stroke), a text per placed text, and
 *              before them the definitions of the gradients they name.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

import CoreGraphics

/// The elements of an SVG document's body, written item by item into `content`; the gradients they name are defined
/// first, in `<defs>`, numbered in the order the items use them. Each element makes sure once of the room of its fixed
/// parts (its tag, attributes, colors and numbers) and writes them unchecked; a path's data, a class, an identifier and
/// a text's characters make sure of their own room, which only they know.
struct DiagramSVGBody: ~Copyable {
    var paints: DiagramSVGPaintWriter
    let identifierPrefix: String
    var content: DiagramSVGBuffer
    /// How many gradient fills the items written so far used.
    private var gradientCount = 0

    /// The room of an element's fill: ` fill="`, its color, its opacity attribute.
    static let fillRoom = DiagramSVGPaintWriter.largestColorByteCount + 64
    /// The room of a stroke's attributes but its dashes: its color, opacity, width, ends and corners.
    static let strokeRoom = DiagramSVGPaintWriter.largestColorByteCount + 192
    /// The room of each dash length and the space before it.
    static let dashRoom = DiagramSVGNumberWriting.largestNumberByteCount + 1
    /// The room of a text's fixed attributes after its class: its size, paint, emphasis, font and rotation.
    static let textOpeningRoom = fillRoom + strokeRoom + 256
    /// The room of a line's or a run's `tspan` but its text: its position and emphasis.
    static let lineRoom = 256

    init(colors: DiagramSVGColors, identifierPrefix: String, content: consuming DiagramSVGBuffer) {
        paints = DiagramSVGPaintWriter(colors: colors)
        self.identifierPrefix = identifierPrefix
        self.content = content
    }

    /// The system's monospaced fonts, behind Pele's `--pele-font-mono` when the colors are Pele's variables.
    private var monospacedFontFamily: StaticString {
        paints.isPeleVariables ? "var(--pele-font-mono,ui-monospace,SFMono-Regular,Menlo,monospace)" : "ui-monospace,SFMono-Regular,Menlo,monospace"
    }

    // MARK: Shapes

    /// A shape's element up to its path's data, which the scene's reader writes next, wherever the scene keeps it.
    mutating func appendShapeOpening(part: DiagramScenePart) {
        content.append("<path class=\"pele-")
        content.append(part.rawValue)
        content.append("\" d=\"")
    }

    /// The rest of a shape's element after its path's data: its painting.
    mutating func appendShapeClosing(painting: DiagramShapePainting) {
        switch painting {
        case .fill(let paint):
            content.reserve(Self.fillRoom + 3)
            content.write(byte: UInt8(ascii: "\""))
            writeFill(paint)
        case .stroke(let paint, let stroke):
            content.reserve(Self.strokeRoom + stroke.dashLengths.count * Self.dashRoom + 24)
            content.write("\" fill=\"none\"")
            writeStroke(paint, stroke)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            content.reserve(Self.fillRoom + Self.strokeRoom + stroke.dashLengths.count * Self.dashRoom + 3)
            content.write(byte: UInt8(ascii: "\""))
            writeFill(fillPaint)
            writeStroke(strokePaint, stroke)
        case .gradientFill(let gradient):
            gradientCount += 1
            content.append("\" fill=\"url(#")
            appendGradientIdentifier(number: gradientCount)
            content.reserve(Self.fillRoom)
            content.write(")\"")
            content.write(opacity: gradient.opacity, attribute: " fill-opacity=\"")
        }
        content.write("/>")
    }

    /// ` fill="…"` and its opacity, within the room reserved.
    @inline(__always)
    private mutating func writeFill(_ paint: DiagramPaint) {
        content.write(" fill=\"")
        let opacity = paints.writeColor(of: paint, into: &content)
        content.write(byte: UInt8(ascii: "\""))
        content.write(opacity: opacity, attribute: " fill-opacity=\"")
    }

    /// The stroke's color, opacity, width, ends, corners and dashes, within the room reserved.
    private mutating func writeStroke(_ paint: DiagramPaint, _ stroke: DiagramStroke) {
        content.write(" stroke=\"")
        let opacity = paints.writeColor(of: paint, into: &content)
        content.write(byte: UInt8(ascii: "\""))
        content.write(opacity: opacity, attribute: " stroke-opacity=\"")
        content.write(" stroke-width=\"")
        content.write(number: stroke.lineWidth)
        content.write(byte: UInt8(ascii: "\""))
        switch stroke.lineCap {
        case .round: content.write(" stroke-linecap=\"round\"")
        case .square: content.write(" stroke-linecap=\"square\"")
        default: break
        }
        switch stroke.lineJoin {
        case .round: content.write(" stroke-linejoin=\"round\"")
        case .bevel: content.write(" stroke-linejoin=\"bevel\"")
        default: break
        }
        guard !stroke.dashLengths.isEmpty else { return }
        content.write(" stroke-dasharray=\"")
        for (index, length) in stroke.dashLengths.enumerated() {
            if index > 0 { content.write(byte: UInt8(ascii: " ")) }
            content.write(number: length)
        }
        content.write(byte: UInt8(ascii: "\""))
    }

    /// `<prefix>-gradient-<n>`, a gradient's id.
    private mutating func appendGradientIdentifier(number: Int) {
        content.append(identifierPrefix)
        content.reserve(10 + DiagramSVGNumberWriting.largestNumberByteCount)
        content.write("-gradient-")
        content.write(number: CGFloat(number))
    }

    // MARK: Gradients

    /// Opens `<defs>` before the first gradient's definition.
    mutating func appendDefinitionsOpening() {
        content.append("<defs>")
    }

    mutating func appendDefinitionsClosing() {
        content.append("</defs>")
    }

    /// A gradient across the page between its two points, the end colors carried on beyond them (SVG's `pad`).
    mutating func appendGradientDefinition(_ gradient: DiagramLinearGradient, number: Int) {
        content.append("<linearGradient id=\"")
        appendGradientIdentifier(number: number)
        content.reserve(2 * Self.fillRoom + 4 * DiagramSVGNumberWriting.largestNumberByteCount + 160)
        content.write("\" gradientUnits=\"userSpaceOnUse\" x1=\"")
        content.write(number: gradient.startPoint.x)
        content.write("\" y1=\"")
        content.write(number: gradient.startPoint.y)
        content.write("\" x2=\"")
        content.write(number: gradient.endPoint.x)
        content.write("\" y2=\"")
        content.write(number: gradient.endPoint.y)
        content.write("\"><stop offset=\"0\" stop-color=\"")
        let startOpacity = paints.writeColor(of: gradient.startPaint, into: &content)
        content.write(byte: UInt8(ascii: "\""))
        content.write(opacity: startOpacity, attribute: " stop-opacity=\"")
        content.write("/><stop offset=\"1\" stop-color=\"")
        let endOpacity = paints.writeColor(of: gradient.endPaint, into: &content)
        content.write(byte: UInt8(ascii: "\""))
        content.write(opacity: endOpacity, attribute: " stop-opacity=\"")
        content.write("/></linearGradient>")
    }

    // MARK: Text

    /// One `text` per placed text, centered on each line's middle; several lines in `tspan`s. Each keeps its spaces
    /// (`xml:space="preserve"`), as Core Text measured and drew them: SVG would otherwise run several into one and drop
    /// those at a line's ends, which moves centered text. An outline is a text of its own under the text, as Pele
    /// writes it: no fill, the stroke in the outline's paint.
    mutating func add(_ text: DiagramSceneText) {
        if let outline = text.outline {
            appendTextOpening(text)
            content.write(" fill=\"none\" xml:space=\"preserve\"")
            writeStroke(outline.paint, DiagramStroke(lineWidth: outline.lineWidth, lineJoin: .round))
            writeTextEmphasisAndRotation(text)
            addLines(of: text.block)
        }
        appendTextOpening(text)
        content.write(" fill=\"")
        let opacity = paints.writeColor(of: text.paint, into: &content)
        content.write("\" xml:space=\"preserve\"")
        content.write(opacity: opacity, attribute: " fill-opacity=\"")
        writeTextEmphasisAndRotation(text)
        addLines(of: text.block)
    }

    /// `<text`, its class and size, with the room of the rest of its opening reserved.
    private mutating func appendTextOpening(_ text: DiagramSceneText) {
        content.append("<text class=\"pele-")
        content.append(text.part.rawValue)
        content.reserve(Self.textOpeningRoom)
        content.write("\" font-size=\"")
        content.write(number: text.block.fontSize)
        content.write(byte: UInt8(ascii: "\""))
    }

    /// The emphasis and the rotation, after the painting, within the room reserved.
    private mutating func writeTextEmphasisAndRotation(_ text: DiagramSceneText) {
        if text.isBold { content.write(" font-weight=\"bold\"") }
        if text.isItalic { content.write(" font-style=\"italic\"") }
        if text.isMonospaced { writeFontFamily() }
        guard let rotation = text.rotation else { return }
        let center = text.block.center
        content.write(" transform=\"rotate(")
        content.write(number: rotation * 180 / .pi)
        content.write(byte: UInt8(ascii: " "))
        content.write(number: center.x)
        content.write(byte: UInt8(ascii: " "))
        content.write(number: center.y)
        content.write(")\"")
    }

    private mutating func writeFontFamily() {
        content.write(" font-family=\"")
        content.write(monospacedFontFamily)
        content.write(byte: UInt8(ascii: "\""))
    }

    /// ` x="…" y="…"`: a line's middle and its baseline, as `DiagramSceneText.lines` places them (the same arithmetic,
    /// without making the lines).
    @inline(__always)
    private mutating func writePosition(ofLine index: Int, in block: DiagramTextBlock, top: CGFloat) {
        let middle = top + (CGFloat(index) + 0.5) * block.lineHeight
        content.write(" x=\"")
        content.write(number: block.center.x)
        content.write("\" y=\"")
        content.write(number: middle + block.fontSize * DiagramTextDrawing.baselineShiftRatio)
        content.write(byte: UInt8(ascii: "\""))
    }

    /// The rest of a `text` whose opening is written: one line in the `text` itself, several in `tspan`s; a text whose
    /// lines have runs in their emphasis writes them as Pele writes a label's spans.
    private mutating func addLines(of block: DiagramTextBlock) {
        let top = block.center.y - block.size.height / 2
        if let lineRuns = block.lineRuns { return addLines(of: block, runs: lineRuns, top: top) }
        if block.lines.count == 1 {
            content.reserve(Self.lineRoom)
            writePosition(ofLine: 0, in: block, top: top)
            content.write(" text-anchor=\"middle\">")
            content.appendEscaped(block.lines[0])
            content.append("</text>")
            return
        }
        content.reserve(Self.lineRoom)
        content.write(" text-anchor=\"middle\">")
        for (index, line) in block.lines.enumerated() {
            content.reserve(Self.lineRoom)
            content.write("<tspan")
            writePosition(ofLine: index, in: block, top: top)
            content.write(byte: UInt8(ascii: ">"))
            content.appendEscaped(line)
            content.append("</tspan>")
        }
        content.append("</text>")
    }

    /// The lines of a text whose lines have runs: a `tspan` at the line's middle for its first run and one after it for
    /// each other run, with the run's weight, slant or font.
    private mutating func addLines(of block: DiagramTextBlock, runs lineRuns: [[DiagramTextRun]], top: CGFloat) {
        content.reserve(Self.lineRoom)
        content.write(" text-anchor=\"middle\">")
        for lineIndex in block.lines.indices {
            let runs = lineRuns[lineIndex]
            content.reserve(Self.lineRoom)
            guard !runs.isEmpty else {
                content.write("<tspan")
                writePosition(ofLine: lineIndex, in: block, top: top)
                content.write("></tspan>")
                continue
            }
            for (index, run) in runs.enumerated() {
                content.reserve(Self.lineRoom)
                content.write("<tspan")
                if index == 0 { writePosition(ofLine: lineIndex, in: block, top: top) }
                if run.style.contains(.bold) { content.write(" font-weight=\"bold\"") }
                if run.style.contains(.italic) { content.write(" font-style=\"italic\"") }
                if run.style.contains(.monospaced) { writeFontFamily() }
                content.write(byte: UInt8(ascii: ">"))
                content.appendEscaped(run.text)
                content.append("</tspan>")
            }
        }
        content.append("</text>")
    }
}
