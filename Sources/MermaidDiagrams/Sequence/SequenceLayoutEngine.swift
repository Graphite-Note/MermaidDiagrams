/**
 * File: SequenceLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays a sequence diagram out in Pele's style and assembles the page: boxes, participants above and below
 *              their lifelines, rows of events, the title and the padding.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.7
 * Date: 25/11/2026
 */

import CoreGraphics

/// Lays a sequence diagram out in Pele's style: the participants side by side in the order they appear, as far apart
/// as the messages and notes between them and their boxes need, each above its lifeline and again below it; then every
/// message, note, block and activation in a row of its own, top to bottom; the boxes behind their participants and the
/// title above.
public enum SequenceLayoutEngine {
    /// Lays the diagram out. It throws nothing any more (every statement read is laid out); the error type is kept for
    /// callers that handle it.
    public static func layout(_ diagram: SequenceDiagram, typography: DiagramTypography) throws(SequenceLayoutError) -> SequenceLayout {
        let keywordSize = SequenceTextMeasurers.smallestTextSize(participantText: typography.nodeText)
        return try layout(diagram, participantText: typography.nodeText, messageText: typography.edgeText,
                          boldSmallestText: typography.measurer(size: keywordSize, isBold: true), font: typography.font)
    }

    /// The diagram for a container `availableWidth` wide (nil for none), as Pele fits it (sequence/render.ts): laid out
    /// with Pele's tight measurements (`SequenceMeasurements.tight`) when it does not fit and that is narrower
    /// (`tighten`), the room the container then has to spare given to the gaps wrapped messages cross
    /// (`SequenceGapWidening`).
    public static func layout(_ diagram: SequenceDiagram, typography: DiagramTypography,
                              availableWidth: CGFloat?) throws(SequenceLayoutError) -> SequenceLayout {
        let keywordSize = SequenceTextMeasurers.smallestTextSize(participantText: typography.nodeText)
        let boldSmallestText = typography.measurer(size: keywordSize, isBold: true)
        return try DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: SequenceLayout) in layout.size.width }) { isTight throws(SequenceLayoutError) in
            try layout(diagram, participantText: typography.nodeText, messageText: typography.edgeText, boldSmallestText: boldSmallestText,
                       font: typography.font,
                       measurements: isTight ? .tight(participantCount: diagram.participants.count, availableWidth: availableWidth) : .standard,
                       availableWidth: isTight ? availableWidth : nil)
        }
    }

    /// The most times a tight diagram is laid out again, holding back room its widened gaps took past the container.
    private static var tightAttemptLimit: Int { 4 }

    /// `measurements`: Pele's or its tight ones; `availableWidth`: in a tight layout, the container whose spare room
    /// widens the gaps wrapped messages cross. A widened diagram wider than the container is laid out again with that
    /// room held back, as Pele draws it again (`hold`).
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: SequenceDiagram, participantText: Measurer, messageText: Measurer,
                                                       boldSmallestText: Measurer? = nil, font: DiagramFont,
                                                       measurements: SequenceMeasurements = .standard,
                                                       availableWidth: CGFloat? = nil) throws(SequenceLayoutError) -> SequenceLayout {
        guard diagram.statementsNotLaidOut.isEmpty else { throw .statementsNotLaidOut(diagram.statementsNotLaidOut) }
        let measurers = SequenceTextMeasurers(participantText: participantText, messageText: messageText, boldSmallestText: boldSmallestText,
                                              measurements: measurements)
        let columns = SequenceColumns(diagram: diagram, measurers: measurers)
        let title = diagram.title.map { title in titleBlock(DiagramLabel(title), measurer: participantText, measurements: measurements, availableWidth: availableWidth) }
        guard measurements.isTight, let available = DiagramWidthFitting.limit(availableWidth) else {
            let extents = SequenceExtents(diagram: diagram, columns: columns, measurers: measurers)
            var rows = SequenceRows(diagram: diagram, columns: columns, extents: extents, measurers: measurers)
            rows.placeEvents()
            return assemble(consume rows, title: title, font: font)
        }
        let widening = SequenceGapWidening(diagram: diagram, measurers: measurers)
        var hold: CGFloat = 0
        var byNeed = true
        var attempt = 1
        while true {
            let widened = widening.widened(columns, availableWidth: available, hold: hold, byNeed: byNeed)
            var rows = SequenceRows(diagram: diagram, columns: widened.columns, extents: widened.extents, measurers: measurers)
            rows.placeEvents()
            let laidOut = assemble(consume rows, title: title, font: font)
            guard widened.isGrown, laidOut.size.width > available, attempt < tightAttemptLimit else { return laidOut }
            hold = widened.isUneven ? hold : hold > 0 ? .infinity : laidOut.size.width - available.rounded(.down)
            byNeed = false
            attempt += 1
        }
    }

    /// The title: unwrapped, or in a tight layout wrapped to the container less its padding and each line still wider
    /// than that, or than 120 points, broken between characters (Pele's `titleRoom` and `breakLabel`).
    private static func titleBlock<Measurer: DiagramTextMeasuring>(_ title: DiagramLabel, measurer: Measurer, measurements: SequenceMeasurements,
                                                                   availableWidth: CGFloat?) -> DiagramTextBlock {
        guard measurements.isTight else { return DiagramTextBlock(label: title, measurer: measurer, maximumWidth: .greatestFiniteMagnitude) }
        let room = DiagramWidthFitting.titleRoom(availableWidth: availableWidth)
        return DiagramTextBlock(label: title, measurer: measurer, wrappingWidth: room, breakingWidth: max(SequenceMeasurements.narrowestBreakingWidth, room))
    }

    /// The participants above and below their lifelines, the boxes behind them, the title centered above everything,
    /// and the whole moved onto a page with Pele's padding around it.
    private static func assemble<Measurer>(_ rows: consuming SequenceRows<Measurer>, title: DiagramTextBlock?, font: DiagramFont) -> SequenceLayout {
        let columns = rows.columns
        let lastRow = rows.y
        let footerHeight = columns.participantSizes.indices.filter { index in rows.lifelineEnds[index] == nil }
            .map { index in columns.participantSizes[index].height }.max() ?? 0
        let boxPadding = columns.boxRuns.runs.isEmpty ? 0 : columns.boxRuns.padding
        if rows.extents.minimumX > rows.extents.maximumX { rows.extend(from: 0, to: max(title?.size.width ?? 0, emptyDiagramWidth)) }
        var topOfPage: CGFloat = 0
        var placedTitle = title.flatMap { block in block.lineCount == 0 ? nil : block }
        if let size = placedTitle?.size {
            let centerX = (rows.extents.minimumX + rows.extents.maximumX) / 2
            rows.extend(from: centerX - size.width / 2, to: centerX + size.width / 2)
            topOfPage = -size.height - SequenceSpacing.titleGap
            placedTitle?.center = CGPoint(x: centerX, y: topOfPage + size.height / 2)
        }
        let offset = CGVector(dx: SequenceSpacing.padding - rows.extents.minimumX, dy: SequenceSpacing.padding - topOfPage)
        let size = CGSize(width: (rows.extents.maximumX - rows.extents.minimumX + 2 * SequenceSpacing.padding).rounded(.up),
                          height: (lastRow + footerHeight + boxPadding - topOfPage + 2 * SequenceSpacing.padding).rounded(.up))
        // The messages and the other placed lists taken out of the rows, which then hold them no more, so that each is
        // moved onto the page in its own lists, where it stands, instead of made again.
        var messages = rows.messages
        rows.messages = []
        for index in messages.indices { messages[index].translate(by: offset) }
        var placed = rows.takePlaced()
        placed.highlights.reverse()
        for index in placed.highlights.indices { placed.highlights[index].translate(by: offset) }
        placed.activations.reverse()
        for index in placed.activations.indices { placed.activations[index] = placed.activations[index].offsetBy(dx: offset.dx, dy: offset.dy) }
        for index in placed.blocks.indices { placed.blocks[index].translate(by: offset) }
        for index in placed.destructions.indices { placed.destructions[index] = placed.destructions[index].translated(by: offset) }
        for index in placed.notes.indices { placed.notes[index].translate(by: offset) }
        return SequenceLayout(size: size, font: font, boxes: boxes(rows, bottom: lastRow + footerHeight, offset: offset),
                              participants: participants(rows, footerTop: lastRow, offset: offset),
                              lifelines: columns.centers.indices.map { index in
                                  SequenceLayoutLifeline(x: columns.centers[index], top: rows.lifelineStarts[index],
                                                         bottom: rows.lifelineEnds[index] ?? lastRow).translated(by: offset)
                              },
                              highlights: placed.highlights, activations: placed.activations, blocks: placed.blocks, messages: messages,
                              destructions: placed.destructions, notes: placed.notes, title: placedTitle?.translated(by: offset))
    }

    /// Each participant above its lifeline, bottoms in line (a created one where its message put it), then each not
    /// destroyed below it from `footerTop`, all moved by `offset` onto the page, into one list.
    private static func participants<Measurer>(_ rows: SequenceRows<Measurer>, footerTop: CGFloat, offset: CGVector) -> [SequenceLayoutParticipant] {
        let columns = rows.columns
        let participants = rows.diagram.participants
        let boxes = rows.diagram.boxes
        func placed(_ index: Int, top: CGFloat) -> SequenceLayoutParticipant {
            let size = columns.participantSizes[index]
            let kind = participants[index].kind
            let frame = CGRect(x: columns.centers[index] - size.width / 2, y: top, width: size.width, height: size.height)
            var text = columns.participantTexts[index]
            text.center = SequenceParticipantGeometry.textCenter(of: kind, in: frame, textHeight: text.size.height)
            var participant = SequenceLayoutParticipant(participantIndex: index, kind: kind, frame: frame, text: text,
                                                        boxColor: participants[index].boxIndex.flatMap { boxIndex in boxes[boxIndex].color })
            participant.translate(by: offset)
            return participant
        }
        var placedParticipants: [SequenceLayoutParticipant] = []
        placedParticipants.reserveCapacity(2 * participants.count)
        for index in participants.indices { placedParticipants.append(placed(index, top: rows.participantTops[index])) }
        for index in participants.indices where rows.lifelineEnds[index] == nil { placedParticipants.append(placed(index, top: footerTop)) }
        return placedParticipants
    }

    /// Each box run from the top of the page to a padding below `bottom`, its title centered at its top, moved by `offset`
    /// onto the page.
    private static func boxes<Measurer>(_ rows: SequenceRows<Measurer>, bottom: CGFloat, offset: CGVector) -> [SequenceLayoutBox] {
        let columns = rows.columns
        return columns.boxRuns.runs.map { run in
            let edges = columns.boxRuns.edges(of: run, centers: columns.centers, sizes: columns.participantSizes)
            var title = run.title.flatMap { block in block.lineCount == 0 ? nil : block }
            if let height = title?.size.height {
                title?.center = CGPoint(x: (edges.left + edges.right) / 2, y: columns.boxRuns.padding / 2 + SequenceSpacing.boxTitleDepth + height / 2)
            }
            var box = SequenceLayoutBox(frame: CGRect(x: edges.left, y: 0, width: edges.right - edges.left, height: bottom + columns.boxRuns.padding),
                                        color: rows.diagram.boxes[run.boxIndex].color, title: title)
            box.translate(by: offset)
            return box
        }
    }

    /// The width of a diagram with nothing in it, so that its title or its empty page has some room.
    private static var emptyDiagramWidth: CGFloat { 40 }
}
