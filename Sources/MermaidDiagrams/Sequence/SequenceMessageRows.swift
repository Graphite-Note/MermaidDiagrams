/**
 * File: SequenceMessageRows.swift
 * -------------------------------
 * Layer: Core
 * Description: How a sequence diagram's rows place a message, as Pele draws it: a line between lifelines or a loop back
 *              to its own, its heads, number, central connections and text, the participant it creates and the
 *              lifelines it ends.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

/// How `SequenceRows` places a message: a straight line from the source's lifeline, or the edge of its activation, to
/// the target's, its text above it; or, to the participant itself, a loop out to the right and back, its text beside it.
extension SequenceRows {
    mutating func placeMessage(_ message: SequenceMessage, at eventIndex: Int) {
        let startingActivationCount = activationsStarting(after: eventIndex, for: message.targetIndex)
        let placed = message.sourceIndex == message.targetIndex
            ? placeLoop(message, at: eventIndex, startingActivationCount: startingActivationCount)
            : placeLine(message, at: eventIndex, startingActivationCount: startingActivationCount)
        messages.append(placed.message)
        moveDown(to: placed.bottom)
        if message.destroysSource || (message.destroysTarget && message.targetIndex == message.sourceIndex) {
            destroy(message.sourceIndex, under: placed.lineY)
        }
        if message.destroysTarget, message.targetIndex != message.sourceIndex { destroy(message.targetIndex, under: placed.lineY) }
    }

    /// How many activations of `participantIndex` the events right after a message start: a `+` belongs to the
    /// message, so its arrow stops at the new activation's edge.
    private func activationsStarting(after eventIndex: Int, for participantIndex: Int) -> Int {
        var count = 0
        for event in diagram.events[(eventIndex + 1)...] {
            switch event {
            case .activationStart(let index): if index == participantIndex { count += 1 }
            case .activationEnd: continue
            case .message, .note, .blockStart, .blockSection, .blockEnd, .numbering: return count
            }
        }
        return count
    }

    /// A message between two lifelines. One that creates its target ends at the created participant's box, which is
    /// centered on its line; a central connection's circle sits on the lifeline and the line stops at it; the number
    /// sits at the tail, past a circle there.
    private mutating func placeLine(_ message: SequenceMessage, at eventIndex: Int,
                                    startingActivationCount: Int) -> (message: SequenceLayoutMessage, bottom: CGFloat, lineY: CGFloat) {
        let text = extents.eventTexts[eventIndex]
        let textHeight = text.map { block in block.lineCount == 0 ? 0 : block.size.height } ?? 0
        let target = message.targetIndex
        let createdHalfHeight = message.createsTarget ? columns.participantSizes[target].height / 2 : 0
        let lineY = y + SequenceSpacing.messageGap + max(textHeight > 0 ? textHeight + SequenceSpacing.textRoom : SequenceSpacing.messageWithoutTextHeight,
                                                         message.createsTarget ? createdHalfHeight - SequenceSpacing.messageGap + SequenceSpacing.creationRoom : 0)
        let sourceX = columns.centers[message.sourceIndex]
        let targetX = columns.centers[target]
        let direction: CGFloat = targetX > sourceX ? 1 : -1
        if message.createsTarget { placeCreatedParticipant(target, centeredAt: lineY) }
        var (start, end, connections) = lineEnds(of: message, at: lineY, direction: direction, startingActivationCount: startingActivationCount)
        let number = placeNumber(at: eventIndex, start: &start, end: &end, lineY: lineY, direction: direction, message: message)
        let ends = SequenceMessageEnds(arrow: message.arrow, start: CGPoint(x: start, y: lineY), end: CGPoint(x: end, y: lineY),
                                       startDirection: CGVector(dx: -direction, dy: 0), endDirection: CGVector(dx: direction, dy: 0),
                                       startBarb: Self.barb(message.arrow, along: direction), endBarb: Self.barb(message.arrow, along: direction))
        let path = DiagramPath(start: ends.lineStart, segments: [.line(to: ends.lineEnd)])
        var placedText: DiagramTextBlock?
        var patch: CGRect?
        if var block = text, block.size.width > 0 {
            block.center = CGPoint(x: (start + end) / 2, y: lineY - SequenceSpacing.messageTextGap - block.size.height / 2)
            extend(from: block.frame.minX, to: block.frame.maxX)
            patch = textPatch(around: block.center, size: block.size)
            placedText = block
        }
        let textBackground = placedText.flatMap { block in patch == nil ? colorUnder(from: block.frame.minX, to: block.frame.maxX) : nil }
        let placed = SequenceLayoutMessage(stroke: message.arrow.stroke, path: path, heads: ends.heads, text: placedText, textPatch: patch, number: number,
                                           centralConnections: connections, lineBackground: colorUnder(from: min(sourceX, targetX), to: max(sourceX, targetX)),
                                           textBackground: textBackground)
        let bottom = message.createsTarget ? lineY + createdHalfHeight - SequenceSpacing.creationRoom : lineY
        return (placed, max(lineY, bottom), lineY)
    }

    /// Where a line between two lifelines starts and ends: at the edges of the activations, at a created participant's
    /// box, or at central connections' circles, which it returns.
    private func lineEnds(of message: SequenceMessage, at lineY: CGFloat, direction: CGFloat,
                          startingActivationCount: Int) -> (start: CGFloat, end: CGFloat, connections: [CGPoint]) {
        let target = message.targetIndex
        let sourceX = columns.centers[message.sourceIndex]
        let targetX = columns.centers[target]
        var start = direction > 0 ? rightEdge(of: message.sourceIndex) : leftEdge(of: message.sourceIndex)
        var end = direction > 0 ? leftEdge(of: target, extra: startingActivationCount) : rightEdge(of: target, extra: startingActivationCount)
        if message.createsTarget {
            end = targetX - direction * SequenceParticipantGeometry.creatingMessageInset(of: diagram.participants[target].kind,
                                                                                         width: columns.participantSizes[target].width)
        }
        var connections: [CGPoint] = []
        let radius = SequenceSpacing.centralConnectionRadius
        if message.hasCentralConnectionAtSource {
            connections.append(CGPoint(x: sourceX, y: lineY))
            start = sourceX + direction * radius
        }
        if message.hasCentralConnectionAtTarget {
            connections.append(CGPoint(x: targetX, y: lineY))
            end = targetX - direction * radius
        }
        return (start, end, connections)
    }

    /// The number's badge on a line, at its tail: where it starts, or where it ends for an arrow written backwards,
    /// past a central connection's circle there; the line then starts or ends past the badge.
    private func placeNumber(at eventIndex: Int, start: inout CGFloat, end: inout CGFloat, lineY: CGFloat, direction: CGFloat,
                             message: SequenceMessage) -> SequenceLayoutNumber? {
        let width = columns.numberWidths[eventIndex]
        guard columns.numberTexts[eventIndex] != nil else { return nil }
        let gap = width / 2 + SequenceSpacing.centralConnectionNumberGap
        if message.arrow.isTailAtTarget {
            let center = message.hasCentralConnectionAtTarget ? end - direction * gap : end
            end = center - direction * width / 2
            return numberBadge(at: eventIndex, center: CGPoint(x: center, y: lineY))
        }
        let center = message.hasCentralConnectionAtSource ? start + direction * gap : start
        start = center + direction * width / 2
        return numberBadge(at: eventIndex, center: CGPoint(x: center, y: lineY))
    }

    /// A message to the participant itself: out to the right of its activations at the top, down, and back in with
    /// rounded corners at the bottom; the text beside the loop, and the next row under the loop or the text. A central
    /// connection's circle sits on the lifeline at the loop's top or bottom, the loop starting or ending at its edge.
    private mutating func placeLoop(_ message: SequenceMessage, at eventIndex: Int,
                                    startingActivationCount: Int) -> (message: SequenceLayoutMessage, bottom: CGFloat, lineY: CGFloat) {
        let text = extents.eventTexts[eventIndex]
        let textSize = text?.size ?? .zero
        let top = y + SequenceSpacing.messageGap + max(0, (textSize.height - SequenceSpacing.selfLoopHeight) / 2)
        let bottom = top + SequenceSpacing.selfLoopHeight
        let lifelineX = columns.centers[message.sourceIndex]
        let radius = SequenceSpacing.centralConnectionRadius
        var start = message.hasCentralConnectionAtSource ? lifelineX + radius : rightEdge(of: message.sourceIndex)
        var end = message.hasCentralConnectionAtTarget ? lifelineX + radius : rightEdge(of: message.sourceIndex, extra: startingActivationCount)
        let numberWidth = columns.numberWidths[eventIndex]
        let outside = max(start, end) + SequenceSpacing.selfLoopWidth + numberWidth / 2
        var connections: [CGPoint] = []
        if message.hasCentralConnectionAtSource { connections.append(CGPoint(x: lifelineX, y: top)) }
        if message.hasCentralConnectionAtTarget { connections.append(CGPoint(x: lifelineX, y: bottom)) }
        let isTailAtEnd = message.arrow.isTailAtTarget
        let number = numberBadge(at: eventIndex, center: isTailAtEnd ? CGPoint(x: end, y: bottom) : CGPoint(x: start, y: top))
        if isTailAtEnd { end += numberWidth / 2 } else { start += numberWidth / 2 }
        let leftward = CGVector(dx: -1, dy: 0)
        let side = Self.barb(message.arrow, along: 1)
        let ends = SequenceMessageEnds(arrow: message.arrow, start: CGPoint(x: start, y: top), end: CGPoint(x: end, y: bottom),
                                       startDirection: leftward, endDirection: leftward, startBarb: side, endBarb: CGVector(dx: 0, dy: -side.dy))
        let path = Self.loopPath(from: ends.lineStart, outsideX: outside, bottom: bottom, endX: ends.lineEnd.x)
        let textLeft = outside + SequenceSpacing.selfLoopTextGap
        extend(from: lifelineX, to: textLeft + textSize.width)
        var placedText: DiagramTextBlock?
        if var block = text, textSize.width > 0 {
            block.center = CGPoint(x: textLeft + textSize.width / 2, y: (top + bottom) / 2)
            placedText = block
        }
        let placed = SequenceLayoutMessage(stroke: message.arrow.stroke, path: path, heads: ends.heads, text: placedText, textPatch: nil, number: number,
                                           centralConnections: connections, lineBackground: colorUnder(from: lifelineX, to: outside),
                                           textBackground: placedText.flatMap { block in colorUnder(from: block.frame.minX, to: block.frame.maxX) })
        let lineY = max(bottom, (top + bottom) / 2 + textSize.height / 2)
        return (placed, lineY, lineY)
    }

    /// The side a half head's barb is on, for a message heading `direction` across the page: the top is above the line
    /// of a message to the right.
    private static func barb(_ arrow: SequenceArrow, along direction: CGFloat) -> CGVector {
        guard arrow.head == .solidHalf || arrow.head == .stickHalf else { return .zero }
        return CGVector(dx: 0, dy: (arrow.halfHeadSide == .bottom ? 1 : -1) * direction)
    }

    /// The loop's path: right along the top, a quarter circle down, down the side, a quarter circle back, and left
    /// along the bottom. Quarter circles are cubic curves.
    private static func loopPath(from start: CGPoint, outsideX: CGFloat, bottom: CGFloat, endX: CGFloat) -> DiagramPath {
        let radius = SequenceSpacing.selfLoopCornerRadius
        let control = radius * quarterCircleControlRatio
        let top = start.y
        return DiagramPath(start: start, segments: [
            .line(to: CGPoint(x: outsideX - radius, y: top)),
            .curve(to: CGPoint(x: outsideX, y: top + radius), control1: CGPoint(x: outsideX - radius + control, y: top),
                   control2: CGPoint(x: outsideX, y: top + radius - control)),
            .line(to: CGPoint(x: outsideX, y: bottom - radius)),
            .curve(to: CGPoint(x: outsideX - radius, y: bottom), control1: CGPoint(x: outsideX, y: bottom - radius + control),
                   control2: CGPoint(x: outsideX - radius + control, y: bottom)),
            .line(to: CGPoint(x: endX, y: bottom)),
        ])
    }

    /// The message's number badge centered at `center`, or nil when it shows no number.
    private func numberBadge(at eventIndex: Int, center: CGPoint) -> SequenceLayoutNumber? {
        guard let number = columns.numberTexts[eventIndex] else { return nil }
        let width = columns.numberWidths[eventIndex]
        var text = measurers.smallestBlock(number)
        text.center = center
        let height = SequenceSpacing.numberHeight
        return SequenceLayoutNumber(frame: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), text: text)
    }

    /// The control-point distance, as a fraction of the radius, that makes a cubic curve follow a quarter circle.
    private static var quarterCircleControlRatio: CGFloat { 0.5523 }
}

/// A message's heads at its two ends, as its arrow puts them, and where its line starts and ends, short of a head by
/// as much of the line as the head takes.
struct SequenceMessageEnds {
    let heads: [SequenceLayoutArrowhead]
    let lineStart: CGPoint
    let lineEnd: CGPoint

    /// The ends at `start` and `end`; each head points along its direction (away from the line), its barb, for a half
    /// head, toward its barb's side.
    init(arrow: SequenceArrow, start: CGPoint, end: CGPoint, startDirection: CGVector, endDirection: CGVector, startBarb: CGVector,
         endBarb: CGVector) {
        let trim = Self.lineTrim(for: arrow.head)
        var heads: [SequenceLayoutArrowhead] = []
        var lineStart = start
        var lineEnd = end
        if arrow.hasHeadAtSource {
            heads.append(SequenceLayoutArrowhead(kind: arrow.head, tip: start, direction: startDirection, barbDirection: startBarb))
            lineStart = CGPoint(x: start.x - startDirection.dx * trim, y: start.y - startDirection.dy * trim)
        }
        if arrow.hasHeadAtTarget {
            heads.append(SequenceLayoutArrowhead(kind: arrow.head, tip: end, direction: endDirection, barbDirection: endBarb))
            lineEnd = CGPoint(x: end.x - endDirection.dx * trim, y: end.y - endDirection.dy * trim)
        }
        self.heads = heads
        self.lineStart = lineStart
        self.lineEnd = lineEnd
    }

    /// How much of the line a head takes, Pele's: an arrow all but a point of its length, a cross up to its center,
    /// nothing for the open and half heads.
    static func lineTrim(for head: SequenceArrowhead) -> CGFloat {
        switch head {
        case .none, .open, .solidHalf, .stickHalf: 0
        case .arrow: DiagramEdgeMark.lineTrim(for: .arrow)
        case .cross: DiagramEdgeMark.lineTrim(for: .cross)
        }
    }
}
