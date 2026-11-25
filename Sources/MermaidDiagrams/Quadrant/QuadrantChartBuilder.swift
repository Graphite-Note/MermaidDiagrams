/**
 * File: QuadrantChartBuilder.swift
 * --------------------------------
 * Layer: Core
 * Description: Collects a quadrant chart as its statements are read, as Mermaid's quadrant database does: titles, axes,
 *              quadrants, points with their coordinates and styles, and classes.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import Foundation

/// Collects a quadrant chart as its statements are read, as Mermaid's quadrant database does: a point's coordinates as
/// JavaScript's `Number` reads them, and its styles and a class's read and checked (`QuadrantChartPointStyleSyntax`).
/// The parser hands it texts without the spaces at their ends. Points and classes count against the node limit.
struct QuadrantChartBuilder {
    private(set) var chart = QuadrantChart()
    /// The bytes the texts' and coordinates' ranges are of.
    private let bytes: [UInt8]
    private let limits: MermaidDiagramLimits
    private var nodeCount = 0

    init(bytes: [UInt8], limits: MermaidDiagramLimits) {
        self.bytes = bytes
        self.limits = limits
    }

    /// A later `title` replaces an earlier one; one with nothing but spaces leaves none.
    mutating func setTitle(_ title: String) {
        let trimmed = FoundationTextOnBytes.trimmed(title, includingLineBreaks: true)
        chart.title = trimmed.isEmpty ? nil : trimmed
    }

    /// The text of quadrant `index + 1`; a later one replaces an earlier one.
    mutating func setQuadrantLabel(at index: Int, _ text: QuadrantChartText) {
        chart.quadrantLabels[index] = label(text)
    }

    /// An axis's texts; without a high end, the axis keeps the high end it had.
    mutating func setAxisLabels(low: QuadrantChartText, high: QuadrantChartText?, isHorizontal: Bool) {
        if isHorizontal {
            chart.xAxisLowLabel = label(low)
            if let high { chart.xAxisHighLabel = label(high) }
        } else {
            chart.yAxisLowLabel = label(low)
            if let high { chart.yAxisHighLabel = label(high) }
        }
    }

    /// A point, its styles the ranges `styles`.
    mutating func addPoint(_ point: QuadrantChartWrittenPoint, styles: [MermaidTextRange], line: Int) throws(MermaidDiagramReadError) {
        try countNode()
        let style = try bytes.withUnsafeBufferPointer { buffer throws(MermaidDiagramReadError) in
            try QuadrantChartPointStyleSyntax.style(from: styles, in: buffer, line: line)
        }
        chart.points.append(QuadrantChartPoint(label: label(point.label) ?? DiagramLabel(lines: []),
                                               xCoordinate: Self.coordinate(text(point.xCoordinate)), yCoordinate: Self.coordinate(text(point.yCoordinate)),
                                               className: point.className, style: style))
    }

    /// The text of `range`.
    private func text(_ range: MermaidTextRange) -> String {
        String(decoding: bytes[range.lowerBound..<range.upperBound], as: UTF8.self)
    }

    /// A coordinate as JavaScript's `Number` reads it. The lexer writes `1`, `0`, or `0`, a character and digits
    /// (`QuadrantChartPointSyntax`): `1`, `0` and `0.` with digits are read here, as `Number` reads them (the decimal
    /// correctly rounded, as `Double` reads it), the rest by `JavaScriptNumber`.
    private static func coordinate(_ written: String) -> Double? {
        let bytes = written.utf8
        guard let first = bytes.first else { return JavaScriptNumber.value(of: written[...]) }
        if bytes.count == 1, first == UInt8(ascii: "1") || first == UInt8(ascii: "0") { return first == UInt8(ascii: "1") ? 1 : 0 }
        let isDecimalFraction = bytes.count > 2 && first == UInt8(ascii: "0") && bytes.dropFirst().first == MermaidByte.period
            && bytes.dropFirst(2).allSatisfy(MermaidByte.isDigit)
        return isDecimalFraction ? Double(written) : JavaScriptNumber.value(of: written[...])
    }

    /// The styles of the class `name`; a later `classDef` of a name replaces an earlier one.
    mutating func addClass(_ name: String, styles: [MermaidTextRange], line: Int) throws(MermaidDiagramReadError) {
        try countNode()
        chart.classStyles[name] = try bytes.withUnsafeBufferPointer { buffer throws(MermaidDiagramReadError) in
            try QuadrantChartPointStyleSyntax.style(from: styles, in: buffer, line: line)
        }
    }

    mutating func apply(_ statement: MermaidAccessibilityStatement) {
        switch statement {
        case .title(let title): chart.accessibilityTitle = title
        case .description(let description): chart.accessibilityDescription = description
        }
    }

    private mutating func countNode() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += 1
    }

    /// A text as Pele draws it: a Markdown string without its emphasis markers, other text with `<br>` ending a line,
    /// tags dropped and entity codes read. Nil for empty text.
    private func label(_ text: QuadrantChartText) -> DiagramLabel? {
        guard !text.isEmpty else { return nil }
        let form: DiagramLabelDecoder.Form = text.isMarkdown ? .markdown : .plain
        if let written = text.text { return DiagramLabelDecoder.label(from: written, form: form) }
        let range = text.range
        return bytes.withUnsafeBufferPointer { buffer in
            DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: buffer[range.lowerBound..<range.upperBound]), form: form)
        }
    }
}
