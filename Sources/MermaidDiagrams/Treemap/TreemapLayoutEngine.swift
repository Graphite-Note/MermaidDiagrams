/**
 * File: TreemapLayoutEngine.swift
 * -------------------------------
 * Layer: Core
 * Description: Lays a treemap out with Pele's measurements, as wide as the container when that is narrower.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation

/// Lays a treemap out in Pele's style: ten nodes across and ten down as Mermaid sizes it (640 by 400 points, `nodeWidth` and
/// `nodeHeight` times ten), the boxes squarified by value (`TreemapSquarifiedPlacement`) with a gap of 2 to 4 points and an
/// inset of 3 to 6 that shrink as the average leaf's area does, sections with a 28-point header band (18 when short) holding
/// their name and their total, leaves with their name and value centered, the title in bold above, 8 points of page around.
public enum TreemapLayoutEngine {
    /// Above a section's children when there is room, and the short band when there is not.
    static let header: CGFloat = TreemapBoxTextPlacement<CoreTextDiagramTextMeasurer>.fullHeader
    static let shortHeader: CGFloat = 18
    /// Between the title and the treemap.
    static let titleGap: CGFloat = 8
    /// The corners' radius of a box at most.
    static let cornerRadius: CGFloat = 4
    /// The area of a leaf below which the gap and the inset begin to shrink, in square points.
    private static let roomyLeafArea: Double = 800

    /// The narrowest a treemap is made for a narrow container (Pele's `least`).
    static let narrowestWidth: CGFloat = 200

    public static func layout(_ diagram: TreemapDiagram, typography: DiagramTypography) -> TreemapLayout {
        layout(diagram, text: typography.nodeText, boldText: typography.boldNodeText, font: typography.font)
    }

    /// The treemap for a container `availableWidth` wide (nil for none): as wide as the container less the page's
    /// padding when that is narrower than its own width, not under 200 points (Pele's `capWidth`), its height its own;
    /// the title wrapped to the container.
    public static func layout(_ diagram: TreemapDiagram, typography: DiagramTypography, availableWidth: CGFloat?) -> TreemapLayout {
        layout(diagram, text: typography.nodeText, boldText: typography.boldNodeText, font: typography.font, availableWidth: availableWidth)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: TreemapDiagram, text: Measurer, boldText: Measurer, font: DiagramFont,
                                                       availableWidth: CGFloat? = nil) -> TreemapLayout {
        let options = diagram.options
        let padding = options.diagramPadding
        let natural = CGFloat(options.nodeWidth) * 10
        let width = TreemapSquarifiedPlacement.rounded(Double(DiagramWidthFitting.capWidth(availableWidth: availableWidth, natural: natural,
                                                                                            least: narrowestWidth, around: 2 * padding)))
        let titleRoom = DiagramWidthFitting.titleRoom(availableWidth: availableWidth)
        let height = TreemapSquarifiedPlacement.rounded(Double(options.nodeHeight) * 10)
        let (boxes, placed) = TreemapSquarifiedPlacement.place(diagram.nodes, width: width, height: height, insets: insets(of: diagram, width: width, height: height))
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: boldText, maximumWidth: titleRoom)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let titleHeight = title.map { title in title.size.height + titleGap } ?? 0
        let origin = CGPoint(x: padding + max(0, ((title?.size.width ?? 0) - CGFloat(width)) / 2), y: padding + titleHeight)
        let format = TreemapValueFormat(specifier: options.valueFormat)
        var texts = TreemapBoxTextPlacement(text: text, boldText: boldText)
        let layoutBoxes = placed.map { index -> TreemapLayoutBox in
            let box = boxes[index]
            let node = diagram.nodes[box.nodeIndex]
            let frame = CGRect(x: origin.x + CGFloat(box.x), y: origin.y + CGFloat(box.y), width: CGFloat(box.width), height: CGFloat(box.height))
            let name = DiagramLabelDecoder.decodingEntities(node.name).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = options.showsValues ? format.text(box.value) : ""
            let textStyle = node.className.flatMap { name in diagram.classTextStyles[name] } ?? TreemapClassTextStyle()
            let written = node.isSection
                ? (box.isHeaded ? texts.headerTexts(name: name, value: value, frame: frame, header: CGFloat(box.header), textStyle: textStyle)
                    : TreemapBoxTexts(name: nil, value: nil))
                : texts.leafTexts(name: name, value: value, frame: frame, textStyle: textStyle)
            return TreemapLayoutBox(nodeIndex: box.nodeIndex, seriesIndex: box.series, frame: frame, isSection: node.isSection, hasHeader: box.isHeaded,
                                    cornerRadius: min(cornerRadius, min(frame.width, frame.height) / 4), name: written.name, value: written.value,
                                    style: node.className.flatMap { name in diagram.classStyles[name] } ?? DiagramElementStyle(), textStyle: textStyle)
        }
        let pageSize = CGSize(width: (max(CGFloat(width), title?.size.width ?? 0) + 2 * padding).rounded(.up),
                              height: (CGFloat(height) + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: pageSize.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        var layout = TreemapLayout(size: pageSize, font: font, boxes: layoutBoxes, title: placedTitle)
        layout.seriesColors = diagram.seriesColors
        return layout
    }

    /// The gap and the inset: the options' gap, else 2 to 4 points, and 3 to 6 points of inset, growing with the average
    /// leaf's area from 800 square points (where they are smallest) to 8,000 (largest).
    private static func insets(of diagram: TreemapDiagram, width: Double, height: Double) -> TreemapInsets {
        let leafCount = diagram.nodes.filter { node in node.size > 0 }.count
        let crowd = min(1, max(0, log10(width * height / Double(max(1, leafCount)) / roomyLeafArea)))
        return TreemapInsets(gap: diagram.options.boxGap.map { gap in Double(gap) } ?? TreemapSquarifiedPlacement.rounded(2 + 2 * crowd),
                             header: Double(header), shortHeader: Double(shortHeader), side: TreemapSquarifiedPlacement.rounded(3 + 3 * crowd))
    }
}
