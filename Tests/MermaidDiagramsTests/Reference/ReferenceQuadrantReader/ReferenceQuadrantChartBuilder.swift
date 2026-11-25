/**
 * File: ReferenceQuadrantChartBuilder.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's quadrant reader (its builder), frozen as main dad6fb8 had it: the
 *              reference the quadrant reader is proven against (QuadrantChartReaderEquivalenceTests).
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// Collects a quadrant chart as its statements are read, as Mermaid's quadrant database does: a point's coordinates as
/// JavaScript's `Number` reads them, and its styles and a class's read and checked (`ReferenceQuadrantChartPointStyleSyntax`).
/// The parser hands it texts without the spaces at their ends. Points and classes count against the node limit.
struct ReferenceQuadrantChartBuilder {
    private(set) var chart = QuadrantChart()
    private let limits: MermaidDiagramLimits
    private var nodeCount = 0

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// A later `title` replaces an earlier one; one with nothing but spaces leaves none.
    mutating func setTitle(_ title: String) {
        let trimmed = FoundationTextOnBytes.trimmed(title, includingLineBreaks: true)
        chart.title = trimmed.isEmpty ? nil : trimmed
    }

    /// The text of quadrant `index + 1`; a later one replaces an earlier one.
    mutating func setQuadrantLabel(at index: Int, _ text: ReferenceQuadrantChartText) {
        chart.quadrantLabels[index] = Self.label(text)
    }

    /// An axis's texts; without a high end, the axis keeps the high end it had.
    mutating func setAxisLabels(low: ReferenceQuadrantChartText, high: ReferenceQuadrantChartText?, isHorizontal: Bool) {
        if isHorizontal {
            chart.xAxisLowLabel = Self.label(low)
            if let high { chart.xAxisHighLabel = Self.label(high) }
        } else {
            chart.yAxisLowLabel = Self.label(low)
            if let high { chart.yAxisHighLabel = Self.label(high) }
        }
    }

    mutating func addPoint(_ point: ReferenceQuadrantChartWrittenPoint, line: Int) throws(MermaidDiagramReadError) {
        try countNode()
        let style = try ReferenceQuadrantChartPointStyleSyntax.style(from: point.styles, line: line)
        chart.points.append(QuadrantChartPoint(label: Self.label(point.label) ?? DiagramLabel(lines: []),
                                               xCoordinate: Self.coordinate(point.xCoordinate), yCoordinate: Self.coordinate(point.yCoordinate),
                                               className: point.className, style: style))
    }

    /// A coordinate as JavaScript's `Number` reads it. The lexer writes `1`, `0`, or `0`, a character and digits
    /// (`ReferenceQuadrantChartPointSyntax`): `1`, `0` and `0.` with digits are read here, as `Number` reads them (the decimal
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
    mutating func addClass(_ name: String, styles: [String], line: Int) throws(MermaidDiagramReadError) {
        try countNode()
        chart.classStyles[name] = try ReferenceQuadrantChartPointStyleSyntax.style(from: styles, line: line)
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
    private static func label(_ text: ReferenceQuadrantChartText) -> DiagramLabel? {
        guard !text.text.isEmpty else { return nil }
        return DiagramLabelDecoder.label(from: text.text, form: text.isMarkdown ? .markdown : .plain)
    }
}
