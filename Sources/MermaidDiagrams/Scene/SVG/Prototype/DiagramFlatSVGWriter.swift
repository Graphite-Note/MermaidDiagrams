/**
 * File: DiagramFlatSVGWriter.swift
 * --------------------------------
 * Layer: Core (design prototype, not for merging)
 * Description: Writes a flat scene as the SVG document `DiagramSVGWriter` writes of the same scene, byte for byte,
 *              straight from the scene's arrays into one reused block of bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The prototype of the design's SVG writer: the same document as `DiagramSVGWriter.document(of:diagramType:title:description:)`.
public struct DiagramFlatSVGWriter {
    public var colors: DiagramSVGColors
    public var identifierPrefix: String
    public var paintsBackground: Bool

    public init(colors: DiagramSVGColors = .peleVariables, identifierPrefix: String = "pele", paintsBackground: Bool = false) {
        self.colors = colors
        self.identifierPrefix = identifierPrefix
        self.paintsBackground = paintsBackground
    }

    public func document(of scene: DiagramFlatScene, diagramType: String, title: String? = nil, description: String? = nil,
                         scratch: DiagramSVGScratch) -> String {
        let colors: DiagramSVGColors
        switch self.colors {
        case .palette(let palette): colors = .palette(scene.seriesColors.palette(over: palette))
        case .peleVariables: colors = .peleVariables
        }
        let title = title.flatMap { title in title.isEmpty ? nil : title }
        let description = description.flatMap { description in description.isEmpty ? nil : description }
        var body = DiagramFlatSVGBody(colors: colors, identifierPrefix: identifierPrefix, writer: DiagramSVGByteWriter(scratch: scratch))
        body.writeRootOpening(of: scene, diagramType: diagramType, isLabelled: (title != nil, description != nil))
        if let title { body.writeHeadElement("title", suffix: "-title", text: title) }
        if let description { body.writeHeadElement("desc", suffix: "-desc", text: description) }
        if scene.hasGradientFills { body.writeDefinitions(of: scene) }
        if paintsBackground { body.writeBackground(of: scene) }
        scene.verbs.withUnsafeBufferPointer { verbs in
            scene.points.withUnsafeBufferPointer { points in
                scene.texts.withUnsafeBufferPointer { texts in
                for item in scene.items {
                    if item.isText {
                        body.write(texts.baseAddress.unsafelyUnwrapped + Int(item.index))
                    } else {
                        let shape = scene.shapes[Int(item.index)]
                        body.write(shape, verbs: verbs.baseAddress.unsafelyUnwrapped + Int(shape.verbStart),
                                   points: points.baseAddress.unsafelyUnwrapped + Int(shape.pointStart))
                    }
                }
                }
            }
        }
        body.writer.reserve(6)
        body.writer.write("</svg>")
        return body.writer.text
    }
}

/// The body's elements, as `DiagramSVGBody` writes them.
struct DiagramFlatSVGBody {
    private var paintTexts: DiagramSVGPaintTexts
    private let isPeleVariables: Bool
    let identifierPrefix: String
    var writer: DiagramSVGByteWriter
    private var gradientCount = 0
    /// The room an element takes beside its numbers' and its text's: its tag, class, paints and attributes.
    private static let elementRoom = 640

    init(colors: DiagramSVGColors, identifierPrefix: String, writer: DiagramSVGByteWriter) {
        paintTexts = DiagramSVGPaintTexts(colors: colors)
        if case .peleVariables = colors { isPeleVariables = true } else { isPeleVariables = false }
        self.identifierPrefix = identifierPrefix
        self.writer = writer
    }

    private var monospacedFontFamily: StaticString {
        switch paintTexts.colors {
        case .palette: "ui-monospace,SFMono-Regular,Menlo,monospace"
        case .peleVariables: "var(--pele-font-mono,ui-monospace,SFMono-Regular,Menlo,monospace)"
        }
    }

    /// A paint's text; a written color with Pele's variables spelled from its own sRGB components, which is what
    /// converting its `CGColor` to sRGB gives, without making the color.
    @inline(__always)
    private mutating func paintText(of paint: DiagramPaint) -> DiagramSVGPaintText {
        if isPeleVariables, case .color(let written) = paint.source {
            let components = DiagramSVGColors.SRGBComponents(red: written.red, green: written.green, blue: written.blue, opacity: written.alpha)
            return DiagramSVGPaintText(color: DiagramSVGColors.hexadecimal(components: components), opacity: CGFloat(written.alpha) * paint.opacity)
        }
        return paintTexts.text(of: paint)
    }

    // MARK: Root

    mutating func writeRootOpening(of scene: DiagramFlatScene, diagramType: String, isLabelled: (byTitle: Bool, byDescription: Bool)) {
        writer.reserve(160)
        writer.write("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" class=\"pele pele-")
        writer.writeEscapedReserving(diagramType)
        writer.reserve(128)
        writer.write("\" viewBox=\"0 0 ")
        writer.write(number: scene.size.width)
        writer.write(byte: UInt8(ascii: " "))
        writer.write(number: scene.size.height)
        writer.write("\" width=\"")
        writer.write(number: scene.size.width)
        writer.write("\" height=\"")
        writer.write(number: scene.size.height)
        writer.write("\" style=\"")
        writeRootStyleAndFontFamily(scene.font)
        writer.reserve(64)
        writer.write(";font-size:")
        writer.write(number: scene.font.size)
        writer.write("px")
        if case .peleVariables = paintTexts.colors {
            for (slot, color) in scene.seriesColors.colors.enumerated() {
                guard let color else { continue }
                writer.reserve(64)
                writer.write(";--pele-series-")
                writer.write(number: CGFloat(slot + 1))
                writer.write(":")
                writer.writeEscapedReserving(color.cssText)
            }
        }
        writer.reserve(64)
        writer.write("\" role=\"graphics-document document\" aria-roledescription=\"")
        writer.writeEscapedReserving(diagramType)
        writer.reserve(32)
        writer.write("\"")
        if isLabelled.byTitle { writeIdentifierAttribute("aria-labelledby", suffix: "-title") }
        if isLabelled.byDescription { writeIdentifierAttribute("aria-describedby", suffix: "-desc") }
        writer.reserve(1)
        writer.write(">")
    }

    /// The root style's colors and `font-family:` with the font's family, escaped once per font and kept in the scratch.
    private mutating func writeRootStyleAndFontFamily(_ font: DiagramFont) {
        let scratch = writer.scratch
        let isPeleVariables: Bool
        if case .peleVariables = paintTexts.colors { isPeleVariables = true } else { isPeleVariables = false }
        if !(scratch.hasCachedFont && scratch.cachedFontIsPeleVariables == isPeleVariables && scratch.cachedFontPostScriptName == font.postScriptName) {
            let family = font.postScriptName.map { name in "\"\(name.filter { character in character != "\"" && character != "\\" })\",sans-serif" }
                ?? "system-ui,-apple-system,sans-serif"
            let fontFamily = isPeleVariables ? "var(--pele-font,\(family))" : family
            let rootStyle = paintTexts.colors.rootStyle
            var escaped = DiagramSVGBuffer(reservingCapacity: 1_024)
            escaped.appendEscaped(rootStyle)
            escaped.append("font-family:")
            escaped.appendEscaped(fontFamily)
            scratch.cachedRootStyleAndFont = Array(escaped.text.utf8)
            scratch.hasCachedFont = true
            scratch.cachedFontIsPeleVariables = isPeleVariables
            scratch.cachedFontPostScriptName = font.postScriptName
        }
        scratch.cachedRootStyleAndFont.withUnsafeBufferPointer { bytes in
            writer.reserve(bytes.count)
            writer.write(bytes: bytes)
        }
    }

    private mutating func writeIdentifierAttribute(_ attribute: StaticString, suffix: StaticString) {
        writer.reserve(40)
        writer.write(" ")
        writer.write(attribute)
        writer.write("=\"")
        writer.writeReserving(identifierPrefix)
        writer.reserve(16)
        writer.write(suffix)
        writer.write("\"")
    }

    mutating func writeHeadElement(_ name: StaticString, suffix: StaticString, text: String) {
        writer.reserve(24)
        writer.write("<")
        writer.write(name)
        writer.write(" id=\"")
        writer.writeReserving(identifierPrefix)
        writer.reserve(24)
        writer.write(suffix)
        writer.write("\">")
        writer.writeEscapedReserving(text)
        writer.reserve(24)
        writer.write("</")
        writer.write(name)
        writer.write(">")
    }

    mutating func writeBackground(of scene: DiagramFlatScene) {
        let background = paintText(of: .background)
        writer.reserve(64)
        writer.write("<rect width=\"")
        writer.write(number: scene.size.width)
        writer.write("\" height=\"")
        writer.write(number: scene.size.height)
        writer.write("\" fill=\"")
        writer.writeReserving(background.color)
        writer.reserve(64)
        writer.write("\"")
        writeOpacity(background.opacity, attribute: " fill-opacity=\"")
        writer.write("/>")
    }

    // MARK: Shapes

    mutating func write(_ shape: DiagramFlatShape, verbs: UnsafePointer<DiagramPathVerb>, points: UnsafePointer<CGPoint>) {
        writer.reserve(48)
        writer.write("<path class=\"pele-")
        writer.writeReserving(shape.part.rawValue)
        writer.reserve(8)
        writer.write("\" d=\"")
        writer.writePathData(verbs: verbs, verbCount: Int(shape.verbCount), points: points)
        writer.reserve(Self.elementRoom)
        writer.write("\"")
        switch shape.painting {
        case .fill(let paint):
            writeFill(paintText(of: paint))
        case .stroke(let paint, let stroke):
            writer.write(" fill=\"none\"")
            writeStroke(paintText(of: paint), stroke)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            writeFill(paintText(of: fillPaint))
            writeStroke(paintText(of: strokePaint), stroke)
        case .gradientFill(let gradient):
            gradientCount += 1
            writer.write(" fill=\"url(#")
            writeGradientIdentifier(number: gradientCount)
            writer.write(")\"")
            writeOpacity(gradient.opacity, attribute: " fill-opacity=\"")
        }
        writer.reserve(2)
        writer.write("/>")
    }

    /// ` fill="…"` and its opacity; the room reserved by the caller.
    private mutating func writeFill(_ paint: DiagramSVGPaintText) {
        writer.write(" fill=\"")
        writer.writeReserving(paint.color)
        writer.reserve(Self.elementRoom)
        writer.write("\"")
        writeOpacity(paint.opacity, attribute: " fill-opacity=\"")
    }

    private mutating func writeStroke(_ paint: DiagramSVGPaintText, _ stroke: DiagramStroke) {
        writer.write(" stroke=\"")
        writer.writeReserving(paint.color)
        writer.reserve(Self.elementRoom)
        writer.write("\"")
        writeOpacity(paint.opacity, attribute: " stroke-opacity=\"")
        writer.write(" stroke-width=\"")
        writer.write(number: stroke.lineWidth)
        writer.write("\"")
        switch stroke.lineCap {
        case .round: writer.write(" stroke-linecap=\"round\"")
        case .square: writer.write(" stroke-linecap=\"square\"")
        default: break
        }
        switch stroke.lineJoin {
        case .round: writer.write(" stroke-linejoin=\"round\"")
        case .bevel: writer.write(" stroke-linejoin=\"bevel\"")
        default: break
        }
        if !stroke.dashLengths.isEmpty {
            writer.reserve(stroke.dashLengths.count * 17 + 24)
            writer.write(" stroke-dasharray=\"")
            for (index, length) in stroke.dashLengths.enumerated() {
                if index > 0 { writer.write(byte: UInt8(ascii: " ")) }
                writer.write(number: length)
            }
            writer.write("\"")
            writer.reserve(Self.elementRoom)
        }
    }

    /// ` <attribute>="0.4"`, or nothing at full opacity; `attribute` includes ` ` and `="`.
    @inline(__always)
    private mutating func writeOpacity(_ opacity: CGFloat, attribute: StaticString) {
        guard opacity < 1 else { return }
        writer.write(attribute)
        writer.write(number: max(0, opacity))
        writer.write("\"")
    }

    private mutating func writeGradientIdentifier(number: Int) {
        writer.writeReserving(identifierPrefix)
        writer.reserve(Self.elementRoom)
        writer.write("-gradient-")
        writer.write(number: CGFloat(number))
    }

    mutating func writeDefinitions(of scene: DiagramFlatScene) {
        var definitionCount = 0
        for item in scene.items where !item.isText {
            guard case .gradientFill(let gradient) = scene.shapes[Int(item.index)].painting else { continue }
            writer.reserve(8)
            if definitionCount == 0 { writer.write("<defs>") }
            definitionCount += 1
            let start = paintText(of: gradient.startPaint)
            let end = paintText(of: gradient.endPaint)
            writer.reserve(32)
            writer.write("<linearGradient id=\"")
            writeGradientIdentifier(number: definitionCount)
            writer.write("\" gradientUnits=\"userSpaceOnUse\" x1=\"")
            writer.write(number: gradient.startPoint.x)
            writer.write("\" y1=\"")
            writer.write(number: gradient.startPoint.y)
            writer.write("\" x2=\"")
            writer.write(number: gradient.endPoint.x)
            writer.write("\" y2=\"")
            writer.write(number: gradient.endPoint.y)
            writer.write("\"><stop offset=\"0\" stop-color=\"")
            writer.writeReserving(start.color)
            writer.reserve(Self.elementRoom)
            writer.write("\"")
            writeOpacity(start.opacity, attribute: " stop-opacity=\"")
            writer.write("/><stop offset=\"1\" stop-color=\"")
            writer.writeReserving(end.color)
            writer.reserve(Self.elementRoom)
            writer.write("\"")
            writeOpacity(end.opacity, attribute: " stop-opacity=\"")
            writer.write("/></linearGradient>")
        }
        writer.reserve(8)
        if definitionCount > 0 { writer.write("</defs>") }
    }

    // MARK: Text

    mutating func write(_ pointer: UnsafePointer<DiagramSceneText>) {
        write(pointer.pointee)
    }

    mutating func write(_ text: borrowing DiagramSceneText) {
        let paint = paintText(of: text.paint)
        if let outline = text.outline {
            let outlinePaint = paintText(of: outline.paint)
            writeTextOpening(text)
            writer.write(" fill=\"none\" xml:space=\"preserve\"")
            writeStroke(outlinePaint, DiagramStroke(lineWidth: outline.lineWidth, lineJoin: .round))
            writeTextRest(text)
            writeLines(of: text.block)
        }
        writeTextOpening(text)
        writer.write(" fill=\"")
        writer.writeReserving(paint.color)
        writer.reserve(Self.elementRoom)
        writer.write("\" xml:space=\"preserve\"")
        writeOpacity(paint.opacity, attribute: " fill-opacity=\"")
        writeTextRest(text)
        writeLines(of: text.block)
    }

    private mutating func writeTextOpening(_ text: DiagramSceneText) {
        writer.reserve(48)
        writer.write("<text class=\"pele-")
        writer.writeReserving(text.part.rawValue)
        writer.reserve(Self.elementRoom)
        writer.write("\" font-size=\"")
        writer.write(number: text.block.fontSize)
        writer.write("\"")
    }

    /// The emphasis and the rotation, after the painting.
    private mutating func writeTextRest(_ text: DiagramSceneText) {
        if text.isBold { writer.write(" font-weight=\"bold\"") }
        if text.isItalic { writer.write(" font-style=\"italic\"") }
        if text.isMonospaced { writeFontFamily() }
        if let rotation = text.rotation {
            let center = text.block.center
            writer.write(" transform=\"rotate(")
            writer.write(number: rotation * 180 / .pi)
            writer.write(byte: UInt8(ascii: " "))
            writer.write(number: center.x)
            writer.write(byte: UInt8(ascii: " "))
            writer.write(number: center.y)
            writer.write(")\"")
        }
    }

    private mutating func writeFontFamily() {
        writer.write(" font-family=\"")
        writer.write(monospacedFontFamily)
        writer.write("\"")
    }

    @inline(__always)
    private mutating func writePosition(ofLine index: Int, in block: DiagramTextBlock, top: CGFloat) {
        let middle = top + (CGFloat(index) + 0.5) * block.lineHeight
        writer.write(" x=\"")
        writer.write(number: block.center.x)
        writer.write("\" y=\"")
        writer.write(number: middle + block.fontSize * DiagramTextDrawing.baselineShiftRatio)
        writer.write("\"")
    }

    private mutating func writeLines(of block: DiagramTextBlock) {
        let top = block.center.y - CGFloat(block.lines.count) * block.lineHeight / 2
        if let lineRuns = block.lineRuns {
            writeLines(of: block, runs: lineRuns, top: top)
            return
        }
        if block.lines.count == 1 {
            writePosition(ofLine: 0, in: block, top: top)
            writer.write(" text-anchor=\"middle\">")
            writer.writeEscapedReserving(block.lines[0])
            writer.reserve(8)
            writer.write("</text>")
            return
        }
        writer.write(" text-anchor=\"middle\">")
        for (index, line) in block.lines.enumerated() {
            writer.reserve(64)
            writer.write("<tspan")
            writePosition(ofLine: index, in: block, top: top)
            writer.write(">")
            writer.writeEscapedReserving(line)
            writer.reserve(8)
            writer.write("</tspan>")
        }
        writer.reserve(8)
        writer.write("</text>")
    }

    private mutating func writeLines(of block: DiagramTextBlock, runs lineRuns: [[DiagramTextRun]], top: CGFloat) {
        writer.write(" text-anchor=\"middle\">")
        for lineIndex in block.lines.indices {
            let runs = lineRuns[lineIndex]
            guard !runs.isEmpty else {
                writer.reserve(64)
                writer.write("<tspan")
                writePosition(ofLine: lineIndex, in: block, top: top)
                writer.write("></tspan>")
                continue
            }
            for (index, run) in runs.enumerated() {
                writer.reserve(Self.elementRoom)
                writer.write("<tspan")
                if index == 0 { writePosition(ofLine: lineIndex, in: block, top: top) }
                if run.style.contains(.bold) { writer.write(" font-weight=\"bold\"") }
                if run.style.contains(.italic) { writer.write(" font-style=\"italic\"") }
                if run.style.contains(.monospaced) { writeFontFamily() }
                writer.write(">")
                writer.writeEscapedReserving(run.text)
                writer.reserve(8)
                writer.write("</tspan>")
            }
        }
        writer.reserve(8)
        writer.write("</text>")
    }
}
