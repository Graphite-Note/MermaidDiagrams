/**
 * File: ReferenceTreeViewLayout.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's tree view layout, frozen as main ba176e5 laid a tree out: rows measured as text blocks from the
 *              entries' Strings, guide lines as paths, and the tight layout for a narrow width, which the layout of flat
 *              records is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's `TreeViewLayout`: its rows and guides as it kept them.
struct ReferenceTreeViewLayout: Equatable {
    let size: CGSize
    let font: DiagramFont
    let title: DiagramTextBlock?
    let guides: [DiagramPath]
    let guideLineWidth: CGFloat
    let rows: [TreeViewLayoutRow]

    /// What the layout of flat records gives when read.
    init(_ layout: TreeViewLayout) {
        self.init(size: layout.size, font: layout.font, title: layout.title, guides: layout.guides, guideLineWidth: layout.guideLineWidth, rows: layout.rows)
    }

    init(size: CGSize, font: DiagramFont, title: DiagramTextBlock?, guides: [DiagramPath], guideLineWidth: CGFloat, rows: [TreeViewLayoutRow]) {
        self.size = size
        self.font = font
        self.title = title
        self.guides = guides
        self.guideLineWidth = guideLineWidth
        self.rows = rows
    }
}

enum ReferenceTreeViewLayoutEngine {
    static let iconGap: CGFloat = 6
    static let descriptionGap: CGFloat = 16
    static let guideInset: CGFloat = 7
    static let elbowRadius: CGFloat = 4
    static let highlightOverhang: CGFloat = 4
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12

    static func layout(_ diagram: ReferenceTreeViewDiagram, typography: DiagramTypography, maximumWidth: CGFloat? = nil) -> ReferenceTreeViewLayout {
        layout(diagram, measurers: DiagramTextMeasurerSet(typography: typography), font: typography.font, maximumWidth: maximumWidth)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: ReferenceTreeViewDiagram, measurers: DiagramTextMeasurerSet<Measurer>, font: DiagramFont,
                                                       maximumWidth: CGFloat?) -> ReferenceTreeViewLayout {
        let limit = maximumWidth.flatMap { width in width > 0 && width.isFinite ? width : nil }
        let loose = laidOut(diagram, measurers: measurers, font: font, tightWidth: nil)
        guard let limit, loose.size.width > limit else { return loose }
        let tight = laidOut(diagram, measurers: measurers, font: font, tightWidth: limit)
        return tight.size.width < loose.size.width ? tight : loose
    }

    /// The tree laid out loose, or tight for `tightWidth`.
    private static func laidOut<Measurer: DiagramTextMeasuring>(_ diagram: ReferenceTreeViewDiagram, measurers: DiagramTextMeasurerSet<Measurer>,
                                                                font: DiagramFont, tightWidth: CGFloat?) -> ReferenceTreeViewLayout {
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.bold, maximumWidth: tightWidth.map { width in max(80, width - 2 * padding) } ?? 4_000)
        }
        let titleHeight = title.map { title in title.lineCount == 0 ? 0 : title.size.height + titleGap } ?? 0
        let rows = ReferenceTreeViewRowPlacement(diagram, measurers: measurers, tightWidth: tightWidth)
        let width = max(rows.width, title?.size.width ?? 0)
        let inset = padding + (rows.hasHighlight ? highlightOverhang : 0)
        let origin = CGPoint(x: inset, y: padding + titleHeight)
        let size = CGSize(width: (width + 2 * inset).rounded(.up), height: (origin.y + rows.height + padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        return ReferenceTreeViewLayout(size: size, font: font, title: placedTitle, guides: rows.guides(diagram, origin: origin),
                              guideLineWidth: CGFloat(diagram.options.lineThickness),
                              rows: rows.placedRows(origin: origin, pageWidth: size.width))
    }
}

/// A tree view's rows measured and stacked, before they are moved inside the page's padding and below its title.
struct ReferenceTreeViewRowPlacement {
    struct Row {
        let entryIndex: Int
        let isFolder: Bool
        let isHighlighted: Bool
        let glyph: TreeViewGlyph?
        /// Where the row's icon starts and where its name starts, from the tree's left.
        let left: CGFloat
        let nameLeft: CGFloat
        let top: CGFloat
        let height: CGFloat
        /// The middle of the row's first line, where its icon is centered.
        let middle: CGFloat
        let name: DiagramTextBlock
        let description: DiagramTextBlock?
    }

    private(set) var rows: [Row] = []
    /// Each entry's row.
    private var rowIndexByEntry: [Int]
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0
    private(set) var hasHighlight = false
    private let step: CGFloat
    private let paddingAcross: CGFloat
    private let paddingDown: CGFloat
    private let isTight: Bool

    init<Measurer: DiagramTextMeasuring>(_ diagram: ReferenceTreeViewDiagram, measurers: DiagramTextMeasurerSet<Measurer>, tightWidth: CGFloat?) {
        let options = diagram.options
        paddingAcross = CGFloat(options.paddingAcross)
        paddingDown = CGFloat(options.paddingDown)
        isTight = tightWidth != nil
        let looseStep = CGFloat(options.rowIndent) + paddingAcross
        let deepest = diagram.entries.map(\.depth).max() ?? 0
        step = tightWidth.map { width in min(looseStep, max(2, (width - 120) / CGFloat(max(1, deepest)))) } ?? looseStep
        rowIndexByEntry = Array(repeating: 0, count: diagram.entries.count)
        var pending: [(entryIndex: Int, leavesIconRoom: Bool)] = []
        func push(_ siblings: [Int]) {
            let leavesIconRoom = siblings.contains { index in TreeViewGlyph(entry: diagram.entries[index], showsIcons: options.showsIcons, iconMaps: options.iconMaps) != nil }
            for index in siblings.reversed() { pending.append((index, leavesIconRoom)) }
        }
        push(diagram.topLevelIndices)
        var namesRight: CGFloat = 0
        while let (entryIndex, leavesIconRoom) = pending.popLast() {
            let row = row(of: diagram, entryIndex: entryIndex, leavesIconRoom: leavesIconRoom, measurers: measurers, tightWidth: tightWidth)
            namesRight = max(namesRight, row.nameLeft + row.name.size.width)
            rowIndexByEntry[entryIndex] = rows.count
            rows.append(row)
            hasHighlight = hasHighlight || row.isHighlighted
            height += row.height
            push(diagram.entries[entryIndex].childIndices)
        }
        width = namesRight
        let descriptionsLeft = namesRight + ReferenceTreeViewLayoutEngine.descriptionGap
        for row in rows {
            guard let description = row.description else { continue }
            width = max(width, (isTight ? row.nameLeft : descriptionsLeft) + description.size.width)
        }
    }

    /// An entry's row below the rows so far: set in its step, its name after its icon's room when its siblings leave one,
    /// one row high, or in a tight layout as high as its name and its description under it.
    private func row<Measurer: DiagramTextMeasuring>(of diagram: ReferenceTreeViewDiagram, entryIndex: Int, leavesIconRoom: Bool,
                                                     measurers: DiagramTextMeasurerSet<Measurer>, tightWidth: CGFloat?) -> Row {
        let entry = diagram.entries[entryIndex]
        let iconSide = measurers.regular.fontSize
        let rowHeight = measurers.regular.lineHeight + 2 * paddingDown
        let left = CGFloat(entry.depth) * step
        let nameLeft = left + (leavesIconRoom ? iconSide + ReferenceTreeViewLayoutEngine.iconGap : 0)
        let room = tightWidth.map { width in max(40, width - 2 * ReferenceTreeViewLayoutEngine.padding - 2 * ReferenceTreeViewLayoutEngine.highlightOverhang - nameLeft) }
        let name = Self.block(DiagramLabelDecoder.decodingEntities(entry.name), measurer: entry.isFolder ? measurers.bold : measurers.regular, room: room)
        let description = entry.description.map { description in
            Self.block(DiagramLabelDecoder.decodingEntities(description), measurer: measurers.regular, room: room)
        }
        let rowHeightHere = isTight ? max(rowHeight, name.size.height + (description?.size.height ?? 0) + 2 * paddingDown) : rowHeight
        let middle = height + (isTight ? paddingDown + max(iconSide, name.size.height) / 2 : rowHeightHere / 2)
        return Row(entryIndex: entryIndex, isFolder: entry.isFolder, isHighlighted: entry.isHighlighted,
                   glyph: TreeViewGlyph(entry: entry, showsIcons: diagram.options.showsIcons, iconMaps: diagram.options.iconMaps), left: left, nameLeft: nameLeft, top: height,
                   height: rowHeightHere, middle: middle, name: name, description: description)
    }

    /// One line as written, or for a tight layout literal lines that fit `room`.
    private static func block(_ text: String, measurer: some DiagramTextMeasuring, room: CGFloat?) -> DiagramTextBlock {
        if let room { return DiagramTextBlock(literal: text, measurer: measurer, room: room) }
        guard !text.isEmpty else { return DiagramTextBlock(lines: [], lineWidths: [], fontSize: measurer.fontSize, lineHeight: measurer.lineHeight) }
        return DiagramTextBlock(lines: [text], lineWidths: [measurer.width(of: text)], fontSize: measurer.fontSize, lineHeight: measurer.lineHeight)
    }

    /// Each folder's guide: from just under its row down to its last entry's middle, turning there with a rounded elbow
    /// to the step's end, and a line across to each other entry.
    func guides(_ diagram: ReferenceTreeViewDiagram, origin: CGPoint) -> [DiagramPath] {
        var paths: [DiagramPath] = []
        for row in rows {
            let children = diagram.entries[row.entryIndex].childIndices
            guard let lastChild = children.last else { continue }
            let across = origin.x + row.left + ReferenceTreeViewLayoutEngine.guideInset
            let tick = max(across, origin.x + row.left + step - paddingAcross)
            let lastMiddle = origin.y + rows[rowIndexByEntry[lastChild]].middle
            let radius = min(ReferenceTreeViewLayoutEngine.elbowRadius, tick - across)
            var segments: [DiagramPathSegment] = [.line(to: CGPoint(x: across, y: lastMiddle - radius))]
            if radius > 0 {
                // Pele's quadratic elbow, as the cubic that draws it.
                let elbowStart = CGPoint(x: across, y: lastMiddle - radius)
                let corner = CGPoint(x: across, y: lastMiddle)
                let elbowEnd = CGPoint(x: across + radius, y: lastMiddle)
                segments.append(.curve(to: elbowEnd, control1: CGPoint(x: elbowStart.x + 2 / 3 * (corner.x - elbowStart.x), y: elbowStart.y + 2 / 3 * (corner.y - elbowStart.y)),
                                       control2: CGPoint(x: elbowEnd.x + 2 / 3 * (corner.x - elbowEnd.x), y: elbowEnd.y)))
                segments.append(.line(to: CGPoint(x: tick, y: lastMiddle)))
            }
            paths.append(DiagramPath(start: CGPoint(x: across, y: origin.y + row.top + row.height - 2), segments: segments))
            for child in children.dropLast() where tick > across {
                let middle = origin.y + rows[rowIndexByEntry[child]].middle
                paths.append(DiagramPath(start: CGPoint(x: across, y: middle), segments: [.line(to: CGPoint(x: tick, y: middle))]))
            }
        }
        return paths
    }

    func placedRows(origin: CGPoint, pageWidth: CGFloat) -> [TreeViewLayoutRow] {
        let descriptionsLeft = rows.reduce(CGFloat(0)) { right, row in max(right, row.nameLeft + row.name.size.width) } + ReferenceTreeViewLayoutEngine.descriptionGap
        return rows.map { row in
            let iconSide = row.name.fontSize
            let highlightLeft = origin.x + row.left - ReferenceTreeViewLayoutEngine.highlightOverhang
            let highlight = row.isHighlighted ? CGRect(x: highlightLeft, y: origin.y + row.top + 1,
                                                       width: pageWidth - origin.x + ReferenceTreeViewLayoutEngine.highlightOverhang - highlightLeft,
                                                       height: row.height - 2) : nil
            let nameTop = isTight ? origin.y + row.top + paddingDown : origin.y + row.middle - row.name.lineHeight / 2
            let names = row.name.placedLines(left: origin.x + row.nameLeft, top: nameTop)
            let descriptions = row.description.map { description in
                isTight ? description.placedLines(left: origin.x + row.nameLeft, top: nameTop + row.name.size.height)
                    : description.placedLines(left: origin.x + descriptionsLeft, top: origin.y + row.middle - description.lineHeight / 2)
            } ?? []
            return TreeViewLayoutRow(entryIndex: row.entryIndex, isFolder: row.isFolder, highlight: highlight, glyph: row.glyph,
                                     glyphFrame: CGRect(x: origin.x + row.left, y: origin.y + row.middle - iconSide / 2, width: iconSide, height: iconSide),
                                     nameLines: names, descriptionLines: descriptions)
        }
    }
}
