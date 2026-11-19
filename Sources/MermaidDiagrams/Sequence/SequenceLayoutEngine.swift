/**
 * File: SequenceLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays a sequence diagram out in Pele's style and assembles the page: boxes, participants above and below
 *              their lifelines, rows of events, the title and the padding.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
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
        try layout(diagram, participantText: typography.nodeText, messageText: typography.edgeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: SequenceDiagram, participantText: Measurer, messageText: Measurer,
                                                       font: DiagramFont) throws(SequenceLayoutError) -> SequenceLayout {
        guard diagram.statementsNotLaidOut.isEmpty else { throw .statementsNotLaidOut(diagram.statementsNotLaidOut) }
        let measurers = SequenceTextMeasurers(participantText: participantText, messageText: messageText)
        let columns = SequenceColumns(diagram: diagram, measurers: measurers)
        let extents = SequenceExtents(diagram: diagram, columns: columns, measurers: measurers)
        var rows = SequenceRows(diagram: diagram, columns: columns, extents: extents, measurers: measurers)
        rows.placeEvents()
        return assemble(rows, title: diagram.title.map { title in measurers.participantBlock(DiagramLabel(title)) }, font: font)
    }

    /// The participants above and below their lifelines, the boxes behind them, the title centered above everything,
    /// and the whole moved onto a page with Pele's padding around it.
    private static func assemble<Measurer>(_ rows: SequenceRows<Measurer>, title: DiagramTextBlock?, font: DiagramFont) -> SequenceLayout {
        var rows = rows
        let columns = rows.columns
        let lastRow = rows.y
        let footerHeight = columns.participantSizes.indices.filter { index in rows.lifelineEnds[index] == nil }
            .map { index in columns.participantSizes[index].height }.max() ?? 0
        let boxPadding = columns.boxRuns.runs.isEmpty ? 0 : SequenceSpacing.boxPadding
        if rows.extents.minimumX > rows.extents.maximumX { rows.extend(from: 0, to: max(title?.size.width ?? 0, emptyDiagramWidth)) }
        var topOfPage: CGFloat = 0
        var placedTitle = title.flatMap { block in block.lines.isEmpty ? nil : block }
        if let size = placedTitle?.size {
            let centerX = (rows.extents.minimumX + rows.extents.maximumX) / 2
            rows.extend(from: centerX - size.width / 2, to: centerX + size.width / 2)
            topOfPage = -size.height - SequenceSpacing.titleGap
            placedTitle?.center = CGPoint(x: centerX, y: topOfPage + size.height / 2)
        }
        let offset = CGVector(dx: SequenceSpacing.padding - rows.extents.minimumX, dy: SequenceSpacing.padding - topOfPage)
        let size = CGSize(width: (rows.extents.maximumX - rows.extents.minimumX + 2 * SequenceSpacing.padding).rounded(.up),
                          height: (lastRow + footerHeight + boxPadding - topOfPage + 2 * SequenceSpacing.padding).rounded(.up))
        return SequenceLayout(size: size, font: font, boxes: boxes(rows, bottom: lastRow + footerHeight).map { box in box.translated(by: offset) },
                              participants: participants(rows, footerTop: lastRow).map { participant in participant.translated(by: offset) },
                              lifelines: columns.centers.indices.map { index in
                                  SequenceLayoutLifeline(x: columns.centers[index], top: rows.lifelineStarts[index],
                                                         bottom: rows.lifelineEnds[index] ?? lastRow).translated(by: offset)
                              },
                              highlights: rows.highlights.reversed().map { highlight in highlight.translated(by: offset) },
                              activations: rows.activations.reversed().map { activation in activation.offsetBy(dx: offset.dx, dy: offset.dy) },
                              blocks: rows.blocks.map { block in block.translated(by: offset) },
                              messages: rows.messages.map { message in message.translated(by: offset) },
                              destructions: rows.destructions.map { center in center.translated(by: offset) },
                              notes: rows.notes.map { note in note.translated(by: offset) },
                              title: placedTitle?.translated(by: offset))
    }

    /// Each participant above its lifeline, bottoms in line (a created one where its message put it), then each not
    /// destroyed below it from `footerTop`.
    private static func participants<Measurer>(_ rows: SequenceRows<Measurer>, footerTop: CGFloat) -> [SequenceLayoutParticipant] {
        let columns = rows.columns
        let participants = rows.diagram.participants
        let boxes = rows.diagram.boxes
        func placed(_ index: Int, top: CGFloat) -> SequenceLayoutParticipant {
            let size = columns.participantSizes[index]
            let kind = participants[index].kind
            let frame = CGRect(x: columns.centers[index] - size.width / 2, y: top, width: size.width, height: size.height)
            var text = columns.participantTexts[index]
            text.center = SequenceParticipantGeometry.textCenter(of: kind, in: frame, textHeight: text.size.height)
            return SequenceLayoutParticipant(participantIndex: index, kind: kind, frame: frame, text: text,
                                             boxColor: participants[index].boxIndex.flatMap { boxIndex in boxes[boxIndex].color })
        }
        let headers = participants.indices.map { index in placed(index, top: rows.participantTops[index]) }
        return headers + participants.indices.filter { index in rows.lifelineEnds[index] == nil }.map { index in placed(index, top: footerTop) }
    }

    /// Each box run from the top of the page to a padding below `bottom`, its title centered at its top.
    private static func boxes<Measurer>(_ rows: SequenceRows<Measurer>, bottom: CGFloat) -> [SequenceLayoutBox] {
        let columns = rows.columns
        return columns.boxRuns.runs.map { run in
            let edges = columns.boxRuns.edges(of: run, centers: columns.centers, sizes: columns.participantSizes)
            var title = run.title.flatMap { block in block.lines.isEmpty ? nil : block }
            if let height = title?.size.height {
                title?.center = CGPoint(x: (edges.left + edges.right) / 2, y: SequenceSpacing.boxPadding / 2 + SequenceSpacing.boxTitleDepth + height / 2)
            }
            return SequenceLayoutBox(frame: CGRect(x: edges.left, y: 0, width: edges.right - edges.left, height: bottom + SequenceSpacing.boxPadding),
                                     color: rows.diagram.boxes[run.boxIndex].color, title: title)
        }
    }

    /// The width of a diagram with nothing in it, so that its title or its empty page has some room.
    private static var emptyDiagramWidth: CGFloat { 40 }
}
