/**
 * File: EventModelColumnLayout.swift
 * ----------------------------------
 * Layer: Core
 * Description: Lays an event model out down a narrow column as Pele does: a card per frame under its lane's name, one
 *              below the other, relations between neighbours straight down and the others on rails at the right.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// An event model down a column, as Pele's `verticalEventModel` lays it out: cards as wide as the column leaves beside
/// the rails (at least 120 points), each with its lane's name above it, broken to leave room for an arrow that passes
/// it, its name and its frame number at the top and its data below, 28 points apart; then the notes' and the
/// specifications' cards. Rails are never shared to save room: past what the width allows, the drawing is wider.
struct EventModelColumnLayout {
    typealias Engine = EventModelLayoutEngine

    let diagram: EventModelDiagram
    let font: DiagramFont
    let room: CGFloat
    let measurers: (title: CoreTextDiagramTextMeasurer, bold: CoreTextDiagramTextMeasurer, regular: CoreTextDiagramTextMeasurer,
                    data: CoreTextDiagramTextMeasurer)

    static let railGap: CGFloat = 8
    static let smallestCardWidth: CGFloat = 120
    /// The room an arrow passing a lane's name keeps beside it.
    static let arrowRoom: CGFloat = 20
    /// Between two frames' cards, and the room a card's name leaves for its number.
    static let frameGap: CGFloat = 28
    static let numberRoom: CGFloat = 36
    /// Below a lane's name, before its card.
    static let laneNameGap: CGFloat = 12
    /// The least width a column is laid out for.
    static let smallestRoom: CGFloat = 160

    init(diagram: EventModelDiagram, typography: DiagramTypography, columnWidth: CGFloat) {
        self.diagram = diagram
        font = typography.font
        room = max(Self.smallestRoom, columnWidth - 2 * Engine.padding)
        let small = (typography.font.size * 0.875).rounded()
        measurers = (typography.boldNodeText, typography.measurer(size: small, isBold: true), typography.measurer(size: small),
                     typography.measurer(size: (typography.font.size * 0.75).rounded(), isMonospaced: true))
    }

    /// A frame's card once placed: its box, and the width of its lane's name.
    private struct Card {
        let frame: CGRect
        let laneNameWidth: CGFloat
    }

    func layout() -> EventModelLayout {
        let rails = EventModelRelationRails(relations: diagram.relations)
        let gutter = 24 + Self.railGap * CGFloat(max(0, rails.railCount - 1))
        let cardWidth = max(Self.smallestCardWidth, room - gutter)
        let textRoom = cardWidth - 2 * Engine.boxHorizontalPadding
        let title = EventModelText.label(diagram.title, measurer: measurers.title, maximumWidth: room)
        var top = Engine.padding + (title.map { title in title.size.height + Engine.titleGap } ?? 0)
        var bottom = Engine.padding + (title?.size.height ?? 0)
        var width = max(title?.size.width ?? 0, cardWidth + gutter)
        var cards: [Card] = []
        var frames: [EventModelLayoutFrame] = []
        var laneNames: [DiagramTextBlock] = []
        for (index, frame) in diagram.frames.enumerated() {
            let laneRoom = rails.passedFrames.contains(index) ? textRoom - Self.arrowRoom : textRoom
            let laneName = EventModelText.broken(EventModelText.label(diagram.lanes[frame.laneIndex].label, measurer: measurers.bold, maximumWidth: laneRoom)
                                                 ?? EventModelText.block([], measurer: measurers.bold), measurer: measurers.bold, room: laneRoom)
            let laidOut = laidOutFrame(frame, top: top + laneName.size.height + Self.laneNameGap, cardWidth: cardWidth, textRoom: textRoom,
                                       laneNameWidth: laneName.size.width)
            laneNames += EventModelText.rows(laneName.lines, measurer: measurers.bold, left: Engine.padding + Engine.boxHorizontalPadding,
                                             firstMiddle: top + laneName.lineHeight / 2, step: laneName.lineHeight)
            frames.append(laidOut)
            cards.append(Card(frame: laidOut.frame, laneNameWidth: laneName.size.width))
            width = max(width, laidOut.frame.width + gutter)
            bottom = laidOut.frame.maxY
            top = bottom + Self.frameGap
        }
        let relations = diagram.relations.compactMap { relation in
            self.relation(relation, cards: cards, railX: Engine.padding + width - gutter + 12, rails: rails)
        }
        let notes = self.cards(from: &top, bottom: &bottom, width: &width, cardWidth: cardWidth, textRoom: textRoom)
        let size = CGSize(width: (width + 2 * Engine.padding).rounded(.up), height: (bottom + Engine.padding).rounded(.up))
        return EventModelLayout(size: size, font: font, runsDown: true,
                                title: title.map { title in EventModelText.placed(title, center: CGPoint(x: size.width / 2, y: Engine.padding + title.size.height / 2)) },
                                laneBands: [], laneNames: laneNames, relations: relations, frames: frames, cards: notes)
    }

    /// A frame's card at `top`: its name at the top left, its number at the top right in the muted color, its data
    /// below in lines that keep every character.
    private func laidOutFrame(_ frame: EventModelFrame, top: CGFloat, cardWidth: CGFloat, textRoom: CGFloat, laneNameWidth: CGFloat) -> EventModelLayoutFrame {
        let padding = Engine.boxHorizontalPadding
        let name = EventModelText.label(frame.name, measurer: measurers.bold, maximumWidth: textRoom - Self.numberRoom)
            ?? EventModelText.block([], measurer: measurers.bold)
        let data = frame.data.map { data in
            EventModelText.block(EventModelText.literalLines(DiagramLabelDecoder.decodingEntities(data), measurer: measurers.data, room: textRoom),
                                 measurer: measurers.data)
        }
        let width = max(cardWidth, laneNameWidth + 2 * padding, name.size.width + 2 * padding + Self.numberRoom, (data?.size.width ?? 0) + 2 * padding)
        let height = 2 * Engine.boxVerticalPadding + name.size.height + (data.map { data in data.size.height + Engine.dataGap } ?? 0)
        let box = CGRect(x: Engine.padding, y: top, width: width, height: height)
        let textTop = top + Engine.boxVerticalPadding
        let number = EventModelText.block([frame.identifier], measurer: measurers.data)
        let numberBaseline = textTop + measurers.bold.fontSize
        let dataLines = data.map { data in
            EventModelText.rows(data.lines, measurer: measurers.data, left: box.minX + padding,
                                firstMiddle: textTop + name.size.height + Engine.dataGap + data.lineHeight / 2, step: data.lineHeight)
        } ?? []
        return EventModelLayoutFrame(
            frame: box, kind: frame.kind, isReset: frame.isReset, seriesIndex: Engine.seriesIndex(of: frame.kind), isOutlinedInBorder: true,
            name: EventModelText.placed(name, center: CGPoint(x: box.minX + padding + name.size.width / 2, y: textTop + name.size.height / 2)),
            number: EventModelText.placed(number, center: CGPoint(x: box.maxX - padding - number.size.width / 2,
                                                                  y: numberBaseline - DiagramTextDrawing.baselineShiftRatio * number.fontSize)),
            dataLines: dataLines)
    }

    /// Between neighbouring cards, straight down or up beside the lower card's lane name; otherwise from the source's
    /// right side, out to the target's rail and back in to the target's right side, leaving above a card's middle and
    /// arriving below it, so that a card can send one relation and receive another.
    private func relation(_ relation: EventModelRelation, cards: [Card], railX: CGFloat, rails: EventModelRelationRails) -> EventModelLayoutRelation? {
        guard relation.sourceFrameIndex != relation.targetFrameIndex else { return nil }
        let source = cards[relation.sourceFrameIndex]
        let target = cards[relation.targetFrameIndex]
        let runsDown = target.frame.minY > source.frame.minY
        let direction: CGFloat = runsDown ? 1 : -1
        let trim = Engine.arrowTrim
        if abs(relation.sourceFrameIndex - relation.targetFrameIndex) == 1 {
            let lower = runsDown ? target : source
            let x = Engine.padding + max(min(source.frame.width, target.frame.width) / 2, Engine.boxHorizontalPadding + lower.laneNameWidth + 16)
            let start = CGPoint(x: x, y: runsDown ? source.frame.maxY : source.frame.minY)
            let tip = CGPoint(x: x, y: runsDown ? target.frame.minY : target.frame.maxY)
            return EventModelLayoutRelation(path: DiagramPath(start: start, segments: [.line(to: CGPoint(x: x, y: tip.y - direction * trim))]),
                                            arrow: Engine.arrow(at: tip, direction: CGVector(dx: 0, dy: direction)))
        }
        let rail = railX + Self.railGap * CGFloat(rails.railByTarget[relation.targetFrameIndex] ?? 0)
        let from = source.frame.midY - 5
        let to = target.frame.midY + 5
        let path = DiagramPath(start: CGPoint(x: source.frame.maxX, y: from), segments: [
            .line(to: CGPoint(x: rail, y: from)), .line(to: CGPoint(x: rail, y: to)), .line(to: CGPoint(x: target.frame.maxX + trim, y: to)),
        ])
        return EventModelLayoutRelation(path: path, arrow: Engine.arrow(at: CGPoint(x: target.frame.maxX, y: to), direction: CGVector(dx: -1, dy: 0)))
    }

    /// The notes' and specifications' cards from `top` down, each as wide as a frame's card at least.
    private func cards(from top: inout CGFloat, bottom: inout CGFloat, width: inout CGFloat, cardWidth: CGFloat,
                       textRoom: CGFloat) -> [EventModelLayoutCard] {
        Engine.cardTexts(of: diagram).map { card in
            let padding = Engine.boxHorizontalPadding
            let heading = EventModelText.label(card.heading, measurer: measurers.bold, maximumWidth: textRoom) ?? EventModelText.block([], measurer: measurers.bold)
            let body = EventModelText.block(EventModelText.literalLines(DiagramLabelDecoder.decodingEntities(card.rows.joined(separator: "\n")),
                                                                        measurer: measurers.regular, room: textRoom), measurer: measurers.regular)
            let cardFrame = CGRect(x: Engine.padding, y: top, width: max(cardWidth, heading.size.width + 2 * padding, body.size.width + 2 * padding),
                                   height: 2 * Engine.boxVerticalPadding + heading.size.height + body.size.height)
            let textTop = top + Engine.boxVerticalPadding
            bottom = cardFrame.maxY
            top = bottom + Engine.cardGap
            width = max(width, cardFrame.width)
            return EventModelLayoutCard(
                frame: cardFrame, isSpecification: card.isSpecification,
                heading: EventModelText.placed(heading, center: CGPoint(x: Engine.padding + padding + heading.size.width / 2, y: textTop + heading.size.height / 2)),
                lines: EventModelText.rows(body.lines, measurer: measurers.regular, left: Engine.padding + padding,
                                           firstMiddle: textTop + heading.size.height + body.lineHeight / 2, step: body.lineHeight))
        }
    }
}
