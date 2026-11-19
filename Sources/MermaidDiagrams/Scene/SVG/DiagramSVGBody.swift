/**
 * File: DiagramSVGBody.swift
 * --------------------------
 * Layer: Core
 * Description: Writes a scene's items as SVG elements: a path per shape (one for a fill and its stroke), a text per placed
 *              text, and the gradients they name.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// The elements of an SVG document's body, written item by item, and the gradients they name.
struct DiagramSVGBody {
    let colors: DiagramSVGColors
    let identifierPrefix: String
    var content = ""
    var definitions = ""
    private var gradientCount = 0

    init(colors: DiagramSVGColors, identifierPrefix: String) {
        self.colors = colors
        self.identifierPrefix = identifierPrefix
    }

    mutating func add(_ item: DiagramSceneItem) {
        switch item {
        case .shape(let shape): add(shape)
        case .text(let text): add(text)
        }
    }

    private mutating func add(_ shape: DiagramSceneShape) {
        let data = DiagramSVGSyntax.pathData(shape.path)
        let painting: String
        switch shape.painting {
        case .fill(let paint):
            let fill = colors.text(of: paint)
            painting = " fill=\"\(fill.color)\"" + DiagramSVGWriter.opacity(fill.opacity, "fill-opacity")
        case .stroke(let paint, let stroke):
            painting = " fill=\"none\"" + Self.strokeAttributes(colors.text(of: paint), stroke)
        case .fillAndStroke(let fillPaint, let strokePaint, let stroke):
            let fill = colors.text(of: fillPaint)
            painting = " fill=\"\(fill.color)\"" + DiagramSVGWriter.opacity(fill.opacity, "fill-opacity")
                + Self.strokeAttributes(colors.text(of: strokePaint), stroke)
        case .gradientFill(let gradient):
            gradientCount += 1
            let identifier = "\(identifierPrefix)-gradient-\(gradientCount)"
            definitions += gradientDefinition(gradient, identifier: identifier)
            painting = " fill=\"url(#\(identifier))\"" + DiagramSVGWriter.opacity(gradient.opacity, "fill-opacity")
        }
        content += "<path class=\"pele-\(shape.part.rawValue)\" d=\"\(data)\"\(painting)/>"
    }

    private static func strokeAttributes(_ paint: DiagramSVGPaintText, _ stroke: DiagramStroke) -> String {
        var attributes = " stroke=\"\(paint.color)\"" + DiagramSVGWriter.opacity(paint.opacity, "stroke-opacity")
        attributes += " stroke-width=\"\(DiagramSVGSyntax.number(stroke.lineWidth))\""
        switch stroke.lineCap {
        case .round: attributes += " stroke-linecap=\"round\""
        case .square: attributes += " stroke-linecap=\"square\""
        default: break
        }
        switch stroke.lineJoin {
        case .round: attributes += " stroke-linejoin=\"round\""
        case .bevel: attributes += " stroke-linejoin=\"bevel\""
        default: break
        }
        if !stroke.dashLengths.isEmpty {
            attributes += " stroke-dasharray=\"\(stroke.dashLengths.map(DiagramSVGSyntax.number).joined(separator: " "))\""
        }
        return attributes
    }

    /// A gradient across the page between its two points, the end colors carried on beyond them (SVG's `pad`).
    private func gradientDefinition(_ gradient: DiagramLinearGradient, identifier: String) -> String {
        let start = colors.text(of: gradient.startPaint)
        let end = colors.text(of: gradient.endPaint)
        let number = DiagramSVGSyntax.number
        return "<linearGradient id=\"\(identifier)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(number(gradient.startPoint.x))\" "
            + "y1=\"\(number(gradient.startPoint.y))\" x2=\"\(number(gradient.endPoint.x))\" y2=\"\(number(gradient.endPoint.y))\">"
            + "<stop offset=\"0\" stop-color=\"\(start.color)\"\(DiagramSVGWriter.opacity(start.opacity, "stop-opacity"))/>"
            + "<stop offset=\"1\" stop-color=\"\(end.color)\"\(DiagramSVGWriter.opacity(end.opacity, "stop-opacity"))/></linearGradient>"
    }

    /// One `text` per placed text, centered on each line's middle; several lines in `tspan`s. Each keeps its spaces
    /// (`xml:space="preserve"`), as Core Text measured and drew them: SVG would otherwise run several into one and drop
    /// those at a line's ends, which moves centered text.
    private mutating func add(_ text: DiagramSceneText) {
        let paint = colors.text(of: text.paint)
        let number = DiagramSVGSyntax.number
        let head = " class=\"pele-\(text.part.rawValue)\" font-size=\"\(number(text.block.fontSize))\""
        var tail = ""
        if text.isBold { tail += " font-weight=\"bold\"" }
        if text.isItalic { tail += " font-style=\"italic\"" }
        if let rotation = text.rotation {
            let center = text.block.center
            tail += " transform=\"rotate(\(number(rotation * 180 / .pi)) \(number(center.x)) \(number(center.y)))\""
        }
        let lines = text.lines
        if let outline = text.outline {
            // The outline is a text of its own under the text, as Pele writes it: no fill, the stroke in the outline's paint.
            let stroke = Self.strokeAttributes(colors.text(of: outline.paint), DiagramStroke(lineWidth: outline.lineWidth, lineJoin: .round))
            addLines(lines, attributes: head + " fill=\"none\" xml:space=\"preserve\"" + stroke + tail)
        }
        addLines(lines, attributes: head + " fill=\"\(paint.color)\" xml:space=\"preserve\"" + DiagramSVGWriter.opacity(paint.opacity, "fill-opacity") + tail)
    }

    /// The `text` of `lines` with `attributes`: one `text` for one line, `tspan`s for several.
    private mutating func addLines(_ lines: [DiagramSceneTextLine], attributes: String) {
        let number = DiagramSVGSyntax.number
        if lines.count == 1, let line = lines.first {
            content += "<text\(attributes) x=\"\(number(line.center.x))\" y=\"\(number(line.baselineStart.y))\" text-anchor=\"middle\">"
                + DiagramSVGSyntax.escaped(line.text) + "</text>"
            return
        }
        content += "<text\(attributes) text-anchor=\"middle\">"
        for line in lines {
            content += "<tspan x=\"\(number(line.center.x))\" y=\"\(number(line.baselineStart.y))\">\(DiagramSVGSyntax.escaped(line.text))</tspan>"
        }
        content += "</text>"
    }
}
