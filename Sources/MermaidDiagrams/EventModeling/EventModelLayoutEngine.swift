/**
 * File: EventModelLayoutEngine.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays an event model out across as Pele does: frames along their lanes, each in a new lane starting under
 *              the end of the one before so that its arrow drops straight, relations straight or in an S between lanes,
 *              notes and specifications listed below.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

/// Lays an event model out as Pele's renderer does, in its measurements: across (`layout(_:typography:)`), or down a
/// column of a given width (`layout(_:typography:columnWidth:)`, `EventModelColumnLayout`), which a reader shows when
/// the model is wider than its column.
public enum EventModelLayoutEngine {
    /// Around a box's text, and the narrowest a box is.
    static let boxHorizontalPadding: CGFloat = 12
    static let boxVerticalPadding: CGFloat = 10
    static let smallestBoxWidth: CGFloat = 96
    /// Between two boxes of a lane, and how far back from the end of the frame before a frame in another lane starts.
    static let boxGap: CGFloat = 16
    static let stagger: CGFloat = 80
    /// Around a lane's content, and between two lanes.
    static let lanePadding: CGFloat = 12
    static let laneGap: CGFloat = 8
    /// The characters a data line and a note line hold before they are cut.
    static let dataColumns = 48
    static let noteColumns = 80
    /// Between the lanes and the first card, and between cards.
    static let cardGap: CGFloat = 8
    /// Between a box's name and its data.
    static let dataGap: CGFloat = 6
    /// Around the page, and below the title.
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// The widest a label is before it wraps: wide enough that it does not.
    static let unwrappedWidth: CGFloat = 4_000
    /// A data line's step, as a share of its size.
    static let dataLineStepRatio: CGFloat = 1.4

    /// The model across, time running to the right.
    public static func layout(_ diagram: EventModelDiagram, typography: DiagramTypography) -> EventModelLayout {
        EventModelAcrossLayout(diagram: diagram, typography: typography).layout()
    }

    /// The model down a column `columnWidth` points wide, a card per frame, as Pele turns it for a narrow host.
    public static func layout(_ diagram: EventModelDiagram, typography: DiagramTypography, columnWidth: CGFloat) -> EventModelLayout {
        EventModelColumnLayout(diagram: diagram, typography: typography, columnWidth: columnWidth).layout()
    }

    /// The text of each note's card and each specification's, by kind, heading and rows: `Note · 01 Name`, or `Given /
    /// When / Then · 01 Name` and its rows `Given  A, B`, `When  C` (only when it has a `when`), `Then  D`.
    static func cardTexts(of diagram: EventModelDiagram) -> [(isSpecification: Bool, heading: String, rows: [String])] {
        guard !diagram.notes.isEmpty || !diagram.specifications.isEmpty else { return [] }
        var names: [String: String] = [:]
        for frame in diagram.frames { names[frame.identifier] = frame.name }
        func heading(_ kind: String, _ frame: String) -> String {
            "\(kind) · \(frame)" + (names[frame].map { name in " " + name } ?? "")
        }
        let notes = diagram.notes.map { note in (false, heading("Note", note.frameIdentifier), [note.text]) }
        let specifications = diagram.specifications.map { specification in
            var rows = ["Given  " + specification.given.joined(separator: ", ")]
            if !specification.when.isEmpty { rows.append("When  " + specification.when.joined(separator: ", ")) }
            rows.append("Then  " + specification.then.joined(separator: ", "))
            return (true, heading("Given / When / Then", specification.frameIdentifier), rows)
        }
        return notes + specifications
    }

    /// Pele's series slot of each kind; a user interface has none and is drawn plain.
    static func seriesIndex(of kind: EventModelEntityKind) -> Int? {
        switch kind {
        case .command: 0
        case .event: 1
        case .readModel: 2
        case .processor: 6
        case .userInterface: nil
        }
    }

    /// An arrow whose tip is at `tip`, pointing along `direction`.
    static func arrow(at tip: CGPoint, direction: CGVector) -> DiagramEdgeMark {
        DiagramEdgeMark(arrowhead: .arrow, tip: tip, direction: direction)
    }

    /// How far before its tip a line ends into an arrow.
    static let arrowTrim = DiagramEdgeMark.lineTrim(for: .arrow)
}

/// The across layout of one model: the boxes placed along their lanes, then the bands, the relations and the cards.
private struct EventModelAcrossLayout {
    typealias Engine = EventModelLayoutEngine

    let diagram: EventModelDiagram
    let measurers: (title: CoreTextDiagramTextMeasurer, name: CoreTextDiagramTextMeasurer, laneName: CoreTextDiagramTextMeasurer,
                    row: CoreTextDiagramTextMeasurer, data: CoreTextDiagramTextMeasurer)
    let font: DiagramFont

    init(diagram: EventModelDiagram, typography: DiagramTypography) {
        self.diagram = diagram
        font = typography.font
        let size = typography.font.size
        measurers = (typography.boldNodeText, typography.measurer(size: (size * 0.875).rounded(), isBold: true),
                     typography.measurer(size: (size * 0.8125).rounded(), isBold: true), typography.measurer(size: (size * 0.8125).rounded()),
                     typography.measurer(size: (size * 0.75).rounded(), isMonospaced: true))
    }

    /// A box before it is placed in its band: across from the label column, its name and data measured.
    private struct Box {
        var frame: CGRect
        let name: DiagramTextBlock
        let data: [String]
    }

    func layout() -> EventModelLayout {
        let laneNames = diagram.lanes.map { lane in Engine.label(lane.label, measurers.laneName) }
        let labelColumn = (laneNames.map(\.size.width).max() ?? 0) + 2 * Engine.lanePadding
        var boxes = placedAlongLanes()
        let contentRight = boxes.map(\.frame.maxX).max() ?? 0
        let laneWidth = labelColumn + contentRight + Engine.lanePadding
        let title = EventModelText.label(diagram.title, measurer: measurers.title, maximumWidth: Engine.unwrappedWidth)
        let titleHeight = title.map { title in title.size.height + Engine.titleGap } ?? 0
        let left = Engine.padding
        var bandTop = Engine.padding + titleHeight
        var tallestByLane = [CGFloat](repeating: 0, count: diagram.lanes.count)
        for (frame, box) in zip(diagram.frames, boxes) { tallestByLane[frame.laneIndex] = max(tallestByLane[frame.laneIndex], box.frame.height) }
        var bands: [CGRect] = []
        for tallest in tallestByLane {
            bands.append(CGRect(x: left, y: bandTop, width: laneWidth, height: tallest + 2 * Engine.lanePadding))
            bandTop += tallest + 2 * Engine.lanePadding + Engine.laneGap
        }
        for index in boxes.indices {
            let band = bands[diagram.frames[index].laneIndex]
            boxes[index].frame.origin = CGPoint(x: boxes[index].frame.minX + left + labelColumn, y: band.minY + (band.height - boxes[index].frame.height) / 2)
        }
        var bottom = bands.last?.maxY ?? Engine.padding + titleHeight
        let cards = self.cards(below: &bottom, hasLanes: !bands.isEmpty)
        let width = max(bands.isEmpty ? 0 : laneWidth, cards.map(\.frame.width).max() ?? 0, title?.size.width ?? 0)
        let size = CGSize(width: (width + 2 * Engine.padding).rounded(.up), height: (bottom + Engine.padding).rounded(.up))
        return EventModelLayout(size: size, font: font, runsDown: false,
                                title: title.map { title in EventModelText.placed(title, center: CGPoint(x: size.width / 2, y: Engine.padding + title.size.height / 2)) },
                                laneBands: bands,
                                laneNames: zip(laneNames, bands).map { name, band in
                                    EventModelText.placed(name, center: CGPoint(x: band.minX + Engine.lanePadding + name.size.width / 2, y: band.midY))
                                },
                                relations: diagram.relations.compactMap { relation in self.relation(relation, boxes: boxes) },
                                frames: zip(diagram.frames, boxes).map(laidOutFrame), cards: cards)
    }

    /// Each box's size, and its place across from the label column: the first at zero, one in the same lane as the box
    /// before it a gap after its lane's last box, one in another lane under the end of the box before it (at least
    /// halfway along it, at most 80 points back from its end) and never over its own lane's last box.
    private func placedAlongLanes() -> [Box] {
        var boxes: [Box] = []
        boxes.reserveCapacity(diagram.frames.count)
        // Each lane's right end so far, nil before its first box.
        var laneRights = [CGFloat?](repeating: nil, count: diagram.lanes.count)
        for (index, frame) in diagram.frames.enumerated() {
            let name = Engine.label(frame.name, measurers.name)
            let data = frame.data.map { data in EventModelText.hardWrapped(data, columns: Engine.dataColumns) } ?? []
            let dataWidth = data.map { line in measurers.data.width(of: line) }.max() ?? 0
            let width = max(Engine.smallestBoxWidth, max(name.size.width, dataWidth) + 2 * Engine.boxHorizontalPadding)
            let height = 2 * Engine.boxVerticalPadding + name.size.height + (data.isEmpty ? 0 : Engine.dataGap + CGFloat(data.count) * dataStep)
            var x: CGFloat = 0
            if let previous = boxes.last {
                let laneRight = laneRights[frame.laneIndex].map { right in right + Engine.boxGap } ?? -.infinity
                let staggered = previous.frame.minX + max(previous.frame.width / 2, previous.frame.width - Engine.stagger)
                x = diagram.frames[index - 1].laneIndex == frame.laneIndex ? laneRight : max(staggered, laneRight)
            }
            laneRights[frame.laneIndex] = x + width
            boxes.append(Box(frame: CGRect(x: x, y: 0, width: width, height: height), name: name, data: data))
        }
        return boxes
    }

    private var dataStep: CGFloat { (measurers.data.fontSize * Engine.dataLineStepRatio).rounded() }

    private func laidOutFrame(_ frame: EventModelFrame, _ box: Box) -> EventModelLayoutFrame {
        let nameTop = box.frame.minY + Engine.boxVerticalPadding
        let name = EventModelText.placed(box.name, center: CGPoint(x: box.frame.midX, y: nameTop + box.name.size.height / 2))
        let firstData = nameTop + box.name.size.height + Engine.dataGap + dataStep / 2
        return EventModelLayoutFrame(frame: box.frame, kind: frame.kind, isReset: frame.isReset, seriesIndex: Engine.seriesIndex(of: frame.kind),
                                     isOutlinedInBorder: false, name: name, number: nil,
                                     dataLines: EventModelText.rows(box.data, measurer: measurers.data, left: box.frame.minX + Engine.boxHorizontalPadding,
                                                                    firstMiddle: firstData, step: dataStep))
    }

    /// Along a lane, from the side of one box to the side of the other; between lanes, straight down or up where the
    /// boxes overlap by 16 points, else in an S from near the source's end to near the target's start.
    private func relation(_ relation: EventModelRelation, boxes: [Box]) -> EventModelLayoutRelation? {
        guard relation.sourceFrameIndex != relation.targetFrameIndex else { return nil }
        let source = boxes[relation.sourceFrameIndex].frame
        let target = boxes[relation.targetFrameIndex].frame
        let trim = Engine.arrowTrim
        if diagram.frames[relation.sourceFrameIndex].laneIndex == diagram.frames[relation.targetFrameIndex].laneIndex {
            let isForward = target.minX >= source.minX
            let start = CGPoint(x: isForward ? source.maxX : source.minX, y: source.midY)
            let tip = CGPoint(x: isForward ? target.minX : target.maxX, y: target.midY)
            let direction: CGFloat = tip.x >= start.x ? 1 : -1
            return EventModelLayoutRelation(path: DiagramPath(start: start, segments: [.line(to: CGPoint(x: tip.x - direction * trim, y: tip.y))]),
                                            arrow: Engine.arrow(at: tip, direction: CGVector(dx: direction, dy: 0)))
        }
        let runsDown = target.minY > source.minY
        let overlapStart = max(source.minX, target.minX)
        let overlapEnd = min(source.maxX, target.maxX)
        func inset(_ width: CGFloat) -> CGFloat { min(24, width / 4) }
        let isOverlapping = overlapEnd - overlapStart >= 16
        let startX = isOverlapping ? (overlapStart + overlapEnd) / 2 : target.minX > source.minX ? source.maxX - inset(source.width) : source.minX + inset(source.width)
        let tipX = isOverlapping ? startX : target.minX > source.minX ? target.minX + inset(target.width) : target.maxX - inset(target.width)
        let start = CGPoint(x: startX, y: runsDown ? source.maxY : source.minY)
        let tip = CGPoint(x: tipX, y: runsDown ? target.minY : target.maxY)
        let direction: CGFloat = runsDown ? 1 : -1
        let end = CGPoint(x: tip.x, y: tip.y - direction * trim)
        let middle = (start.y + end.y) / 2
        let segment: DiagramPathSegment = start.x == end.x ? .line(to: end)
            : .curve(to: end, control1: CGPoint(x: start.x, y: middle), control2: CGPoint(x: end.x, y: middle))
        return EventModelLayoutRelation(path: DiagramPath(start: start, segments: [segment]), arrow: Engine.arrow(at: tip, direction: CGVector(dx: 0, dy: direction)))
    }

    /// The notes' and specifications' cards, one below the other from `bottom` (eight points below the lanes when there
    /// are any), which ends below the last.
    private func cards(below bottom: inout CGFloat, hasLanes: Bool) -> [EventModelLayoutCard] {
        let left = Engine.padding
        let rowStep = measurers.row.lineHeight
        return Engine.cardTexts(of: diagram).enumerated().map { index, card in
            let heading = Engine.label(card.heading, measurers.laneName)
            let rows = card.rows.flatMap { row in EventModelText.hardWrapped(row, columns: Engine.noteColumns) }
            let width = max(heading.size.width, rows.map { row in measurers.row.width(of: row) }.max() ?? 0) + 2 * Engine.boxHorizontalPadding
            let height = 2 * Engine.boxVerticalPadding + heading.size.height + CGFloat(rows.count) * rowStep
            let top = bottom + (index == 0 && !hasLanes ? 0 : Engine.cardGap)
            bottom = top + height
            let textTop = top + Engine.boxVerticalPadding
            return EventModelLayoutCard(
                frame: CGRect(x: left, y: top, width: width, height: height), isSpecification: card.isSpecification,
                heading: EventModelText.placed(heading, center: CGPoint(x: left + Engine.boxHorizontalPadding + heading.size.width / 2,
                                                                        y: textTop + heading.size.height / 2)),
                lines: EventModelText.rows(rows, measurer: measurers.row, left: left + Engine.boxHorizontalPadding,
                                           firstMiddle: textTop + heading.size.height + rowStep / 2, step: rowStep))
        }
    }
}

extension EventModelLayoutEngine {
    /// A label as Pele lays one out without wrapping it, or an empty block for empty text.
    static func label(_ text: String, _ measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        EventModelText.label(text, measurer: measurer, maximumWidth: unwrappedWidth) ?? EventModelText.block([], measurer: measurer)
    }
}
