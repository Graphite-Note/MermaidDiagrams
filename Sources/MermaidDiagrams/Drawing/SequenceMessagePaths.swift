/**
 * File: SequenceMessagePaths.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's messages as paths: lines by stroke, heads, central connections' circles,
 *              grouped by the color Pele paints them in, and the number badges and text patches.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The lines, heads and central connections' circles of messages painted in one color: the line color (`ink` nil), or
/// the text color Pele picks on the colored `rect` or box under them.
public struct SequenceDrawingMessageLines {
    public let ink: DiagramColor?
    /// Stroked one point wide with round caps; dotted ones dashed.
    public let solidLines: CGPath
    public let dottedLines: CGPath
    /// Arrowheads and solid half heads, filled; crosses, open heads and stick half heads, stroked.
    public let filledHeads: CGPath
    public let strokedHeads: CGPath
    /// Filled.
    public let centralConnections: CGPath

    init(_ lines: SequenceMessageLinePaths<DiagramCoreGraphicsPath>) {
        ink = lines.ink
        solidLines = lines.solidLines.path
        dottedLines = lines.dottedLines.path
        filledHeads = lines.filledHeads.path
        strokedHeads = lines.strokedHeads.path
        centralConnections = lines.centralConnections.path
    }
}

/// The paths of `SequenceDrawingMessageLines`, recorded into the paths a maker makes.
struct SequenceMessageLinePaths<Path: DiagramPathRecording> {
    let ink: DiagramColor?
    let solidLines: Path
    let dottedLines: Path
    let filledHeads: Path
    let strokedHeads: Path
    let centralConnections: Path

    init<Maker: DiagramPathMaking>(ink: DiagramColor?, making maker: Maker) where Maker.Path == Path {
        self.ink = ink
        solidLines = maker.makePath()
        dottedLines = maker.makePath()
        filledHeads = maker.makePath()
        strokedHeads = maker.makePath()
        centralConnections = maker.makePath()
    }

    func add<Maker: DiagramPathMaking>(_ message: SequenceLayoutMessage, making maker: Maker) where Maker.Path == Path {
        switch message.stroke {
        case .solid: maker.addEdgeLine(message.path, to: solidLines)
        case .dotted: maker.addEdgeLine(message.path, to: dottedLines)
        }
        for head in message.heads { addHead(head) }
        let radius = SequenceSpacing.centralConnectionRadius
        for center in message.centralConnections {
            centralConnections.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
    }

    /// An arrow and a cross as a flowchart's edges draw them; an open head as two strokes back from the tip; a half head
    /// as the half of an arrowhead on its barb's side (filled) or its one barb (stroked).
    private func addHead(_ head: SequenceLayoutArrowhead) {
        let length = DiagramEdgeMark.arrowLength
        let back = CGPoint(x: head.tip.x - head.direction.dx * length, y: head.tip.y - head.direction.dy * length)
        switch head.kind {
        case .none: return
        case .arrow, .cross:
            let arrowhead: FlowchartArrowhead = head.kind == .arrow ? .arrow : .cross
            DiagramEdgeDrawing.addMark(DiagramEdgeMark(arrowhead: arrowhead, tip: head.tip, direction: head.direction), filled: filledHeads,
                                       stroked: strokedHeads)
        case .open:
            let normal = CGVector(dx: -head.direction.dy, dy: head.direction.dx)
            let halfHeight = SequenceDrawingParts.openHeadHalfHeight
            strokedHeads.addLines(between: [CGPoint(x: back.x + normal.dx * halfHeight, y: back.y + normal.dy * halfHeight), head.tip,
                                            CGPoint(x: back.x - normal.dx * halfHeight, y: back.y - normal.dy * halfHeight)])
        case .solidHalf:
            let depth = SequenceDrawingParts.openHeadHalfHeight
            filledHeads.addLines(between: [head.tip, CGPoint(x: back.x + head.barbDirection.dx * depth, y: back.y + head.barbDirection.dy * depth), back])
            filledHeads.closeSubpath()
        case .stickHalf:
            let depth = SequenceDrawingParts.stickHalfHeadDepth
            strokedHeads.addLines(between: [head.tip, CGPoint(x: back.x + head.barbDirection.dx * depth, y: back.y + head.barbDirection.dy * depth)])
        }
    }
}

/// Every message's paths: those in the line color, those over colored backgrounds by color in the order they appear,
/// and the number badges and text patches, which keep their colors on any background.
struct SequenceMessagePaths<Path: DiagramPathRecording> {
    let lines: SequenceMessageLinePaths<Path>
    private(set) var inkedLines: [SequenceMessageLinePaths<Path>] = []
    let numberBadges: Path
    let textPatches: Path

    init<Maker: DiagramPathMaking>(messages: [SequenceLayoutMessage], making maker: Maker) where Maker.Path == Path {
        lines = SequenceMessageLinePaths(ink: nil, making: maker)
        numberBadges = maker.makePath()
        textPatches = maker.makePath()
        let radius = SequenceDrawingParts.cornerRadius
        for message in messages {
            if let ink = SequenceTextInk.ink(on: message.lineBackground) {
                if let group = inkedLines.first(where: { group in group.ink == ink }) {
                    group.add(message, making: maker)
                } else {
                    let group = SequenceMessageLinePaths(ink: ink, making: maker)
                    group.add(message, making: maker)
                    inkedLines.append(group)
                }
            } else {
                lines.add(message, making: maker)
            }
            if let number = message.number {
                let badgeRadius = number.frame.height / 2
                maker.addMadeRoundedRectangle(number.frame, cornerWidth: badgeRadius, cornerHeight: badgeRadius, to: numberBadges)
            }
            if let patch = message.textPatch { maker.addMadeRoundedRectangle(patch, cornerWidth: radius, cornerHeight: radius, to: textPatches) }
        }
    }
}
