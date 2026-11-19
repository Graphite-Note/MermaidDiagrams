/**
 * File: SequenceParticipantGeometry.swift
 * ---------------------------------------
 * Layer: Core
 * Description: The size of a sequence participant around its text and where its text goes, for each of Pele's shapes,
 *              and the actor's stick figure.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// The size of a participant around its text, and the stick figure of an actor, Pele's (`sequence/actors.ts`).
enum SequenceParticipantGeometry {
    /// Between a box's text and its sides.
    static let horizontalPadding: CGFloat = 16
    /// Between a box's text and its top and bottom.
    static let verticalPadding: CGFloat = 10
    static let minimumBoxWidth: CGFloat = 64
    /// What a box's height adds to one and a half lines of the participants' text: Mermaid's default height.
    static let boxHeightBeyondText: CGFloat = 20
    /// A figure's height, above its text.
    static let figureHeight: CGFloat = 34
    static let figureTextGap: CGFloat = 4
    static let minimumFigureWidth: CGFloat = 40
    /// How much wider than its text a figure is.
    static let figureExtraWidth: CGFloat = 8
    /// How far the back card of collections stands out to the right and above the front one.
    static let collectionsOffset: CGFloat = 5
    /// How far a queue's rounded ends reach in from its sides.
    static let queueCapWidth: CGFloat = 6

    /// The participant's size around text of `textSize`, its text in `fontSize`.
    static func size(of kind: SequenceParticipantKind, textSize: CGSize, fontSize: CGFloat) -> CGSize {
        if kind.isFigure {
            return CGSize(width: max(minimumFigureWidth, textSize.width + figureExtraWidth),
                          height: figureHeight + (textSize.height > 0 ? figureTextGap + textSize.height : 0))
        }
        let minimumHeight = (fontSize * CoreTextDiagramTextMeasurer.lineHeightRatio).rounded() + boxHeightBeyondText
        let extraWidth: CGFloat = kind == .collections ? collectionsOffset : kind == .queue ? 2 * queueCapWidth : 0
        return CGSize(width: max(minimumBoxWidth, textSize.width + 2 * horizontalPadding) + extraWidth,
                      height: max(minimumHeight, textSize.height + 2 * verticalPadding) + (kind == .collections ? collectionsOffset : 0))
    }

    /// Where the participant's text is centered in its frame: under a figure, in the front card of collections, left
    /// of a queue's right end, or in the middle of a box.
    static func textCenter(of kind: SequenceParticipantKind, in frame: CGRect, textHeight: CGFloat) -> CGPoint {
        if kind.isFigure { return CGPoint(x: frame.midX, y: frame.minY + figureHeight + figureTextGap + textHeight / 2) }
        switch kind {
        case .collections:
            return CGPoint(x: frame.minX + (frame.width - collectionsOffset) / 2, y: frame.minY + collectionsOffset + (frame.height - collectionsOffset) / 2)
        case .queue: return CGPoint(x: frame.midX - queueCapWidth / 2, y: frame.midY)
        default: return CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    /// How far from its center a message that creates the participant stops: 18 points for a figure, else half its
    /// width and a point.
    static func creatingMessageInset(of kind: SequenceParticipantKind, width: CGFloat) -> CGFloat {
        let figureInset: CGFloat = 18
        return kind.isFigure ? figureInset : width / 2 + 1
    }

    /// The figure's head, a circle of radius 6 centered 7 points under the top.
    static func figureHead(in frame: CGRect) -> CGRect {
        let radius: CGFloat = 6
        let headCenterDepth: CGFloat = 7
        return CGRect(x: frame.midX - radius, y: frame.minY + headCenterDepth - radius, width: 2 * radius, height: 2 * radius)
    }

    /// The figure's body, arms and legs, as lines from point to point.
    static func figureLimbs(in frame: CGRect) -> [[CGPoint]] {
        let centerX = frame.midX
        let top = frame.minY
        func point(_ horizontal: CGFloat, _ depth: CGFloat) -> CGPoint { CGPoint(x: centerX + horizontal, y: top + depth) }
        return [[point(0, 13), point(0, 24)], [point(-10, 17), point(10, 17)], [point(-8, 34), point(0, 24), point(8, 34)]]
    }
}
