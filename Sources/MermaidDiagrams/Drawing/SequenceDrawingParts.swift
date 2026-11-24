/**
 * File: SequenceDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's geometry grouped by how it is painted, back to front as Pele draws it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

/// A laid-out sequence diagram's geometry grouped by how it is painted, so that drawing it in any colors is a handful
/// of fills and strokes, by Core Graphics (`SequenceRenderer`) or by a view's own shapes. Back to front, as Pele
/// draws: the boxes, the highlights, the lifelines, the activations, the block frames, the messages with their central
/// connections and numbers, the crosses of destroyed lifelines, the messages' texts, the notes, the participants, the
/// title. Besides `DiagramPalette`'s roles, Pele paints with a
/// muted text color and a second surface, which sit between the background and the foreground (`mutedShare`,
/// `surfaceAlternateShare`).
public struct SequenceDrawingParts {
    /// The boxes behind their participants, each filled with its color (or the second surface at half opacity) and
    /// outlined in the border color, its title in the text color that contrasts with the color, else muted.
    public let boxes: [SequenceDrawingBox]
    /// The `rect` backgrounds, back to front, each with its color or nil for the default shade: the second surface at
    /// half opacity.
    public let highlights: [SequenceDrawingHighlight]
    /// Stroked one point wide in the border color.
    public var lifelines: CGPath { lifelinesScenePath.coreGraphicsPath }
    let lifelinesScenePath: DiagramScenePath
    /// Activation bars, back to front, each filled with the surface and outlined in the border color.
    public var activations: [CGPath] { activationsScenePaths.map(\.coreGraphicsPath) }
    let activationsScenePaths: [DiagramScenePath]
    /// The blocks' frames, stroked in the border color; their section lines, dashed.
    public var blockOutlines: CGPath { blockOutlinesScenePath.coreGraphicsPath }
    let blockOutlinesScenePath: DiagramScenePath
    public var blockSectionLines: CGPath { blockSectionLinesScenePath.coreGraphicsPath }
    let blockSectionLinesScenePath: DiagramScenePath
    /// The patches behind block texts a lifeline crosses, filled in the background color.
    public var blockTextPatches: CGPath { blockTextPatchesScenePath.coreGraphicsPath }
    let blockTextPatchesScenePath: DiagramScenePath
    /// The blocks' titles and section texts, in the muted color, or in the color `blockTextInks` gives one on a colored
    /// `rect` or box.
    public let blockTexts: [DiagramTextBlock]
    public let blockTextInks: [DiagramColor?]
    /// The tabs, filled with the surface and outlined in the border color, and their keywords, bold and muted.
    public var blockTabs: CGPath { blockTabsScenePath.coreGraphicsPath }
    let blockTabsScenePath: DiagramScenePath
    public let blockKeywords: [DiagramTextBlock]
    /// Messages' lines in the line color, one point wide with round caps; dotted ones dashed.
    public var solidMessageLines: CGPath { solidMessageLinesScenePath.coreGraphicsPath }
    let solidMessageLinesScenePath: DiagramScenePath
    public var dottedMessageLines: CGPath { dottedMessageLinesScenePath.coreGraphicsPath }
    let dottedMessageLinesScenePath: DiagramScenePath
    /// Arrowheads and solid half heads, filled in the line color; crosses, open heads and stick half heads, stroked one
    /// point wide with round joins.
    public var filledHeads: CGPath { filledHeadsScenePath.coreGraphicsPath }
    let filledHeadsScenePath: DiagramScenePath
    public var strokedHeads: CGPath { strokedHeadsScenePath.coreGraphicsPath }
    let strokedHeadsScenePath: DiagramScenePath
    /// Central connections' circles on the lifelines, filled in the line color.
    public var centralConnections: CGPath { centralConnectionsScenePath.coreGraphicsPath }
    let centralConnectionsScenePath: DiagramScenePath
    /// The lines, heads and circles of the messages over a colored `rect` or box, painted as those above but in the
    /// text color that contrasts with that color, one group per color.
    public let inkedMessageLines: [SequenceDrawingMessageLines]
    /// The crosses that end destroyed lifelines, stroked in the line color `destructionLineWidth` wide, round capped.
    public var destructions: CGPath { destructionsScenePath.coreGraphicsPath }
    let destructionsScenePath: DiagramScenePath
    /// The numbers' badges, filled in the line color, and the numbers on them, in the background color.
    public var numberBadges: CGPath { numberBadgesScenePath.coreGraphicsPath }
    let numberBadgesScenePath: DiagramScenePath
    public let numberTexts: [DiagramTextBlock]
    /// The patches behind messages' texts a lifeline crosses, in the background color, and the texts.
    public var messageTextPatches: CGPath { messageTextPatchesScenePath.coreGraphicsPath }
    let messageTextPatchesScenePath: DiagramScenePath
    public let messageTexts: [DiagramTextBlock]
    /// For each of `messageTexts`, the color it takes on a colored `rect` or box, or nil for the text color.
    public let messageTextInks: [DiagramColor?]
    /// Notes, filled with the second surface and outlined in the border color, and their text.
    public var notes: CGPath { notesScenePath.coreGraphicsPath }
    let notesScenePath: DiagramScenePath
    public let noteTexts: [DiagramTextBlock]
    /// Participants' shapes and figures' circles, filled with the surface and outlined in the border color; figures'
    /// lines (an actor's limbs, a boundary's bar, a control's arrowhead, an entity's base, a cylinder's rim), stroked in
    /// the border color; the front cards of collections, filled and outlined after them.
    public var participantShapes: CGPath { participantShapesScenePath.coreGraphicsPath }
    let participantShapesScenePath: DiagramScenePath
    public var participantFigureLines: CGPath { participantFigureLinesScenePath.coreGraphicsPath }
    let participantFigureLinesScenePath: DiagramScenePath
    public var participantFrontShapes: CGPath { participantFrontShapesScenePath.coreGraphicsPath }
    let participantFrontShapesScenePath: DiagramScenePath
    public let participantTexts: [DiagramTextBlock]
    /// For each of `participantTexts`, the color a figure's text takes on its box's color, or nil for the text color.
    public let participantTextInks: [DiagramColor?]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let destructionLineWidth: CGFloat = 1.5
    /// Dotted messages and block sections: dashes of 4, gaps of 4.
    public static let dashLengths: [CGFloat] = [4, 4]
    /// Pele's muted text (#6e6e6e) and second surface (#e6e6e6), as shares of the way from its white page to its
    /// #1f1f1f text.
    public static let mutedShare: CGFloat = 145.0 / 224.0
    public static let surfaceAlternateShare: CGFloat = 25.0 / 224.0
    /// The opacity of a highlight without a color of its own.
    public static let defaultHighlightOpacity: CGFloat = 0.5
    /// Pele's `--pele-radius`, the corners of frames, tabs, notes, boxes and highlights; activations have smaller ones.
    static let cornerRadius: CGFloat = 4
    static let activationCornerRadius: CGFloat = 2
    /// An open head's half height, and a solid half head's, Pele's; a stick half head's barb reaches 5 points out.
    static let openHeadHalfHeight: CGFloat = 4.5
    static let stickHalfHeadDepth: CGFloat = 5

    public init(layout: SequenceLayout) {
        boxes = layout.boxes.map { box in
            SequenceDrawingBox(pathScenePath: Self.roundedRectangle(box.frame), color: box.color, title: box.title, titleInk: SequenceTextInk.ink(on: box.color))
        }
        highlights = layout.highlights.map { highlight in SequenceDrawingHighlight(pathScenePath: Self.roundedRectangle(highlight.frame), color: highlight.color) }
        lifelinesScenePath = Self.lifelinePath(layout.lifelines)
        activationsScenePaths = layout.activations.map { activation in
            DiagramScenePath(roundedRect: activation, cornerWidth: Self.activationCornerRadius, cornerHeight: Self.activationCornerRadius)
        }
        let blocks = BlockPaths(blocks: layout.blocks)
        blockOutlinesScenePath = blocks.outlines
        blockSectionLinesScenePath = blocks.sectionLines
        blockTextPatchesScenePath = blocks.textPatches
        blockTexts = blocks.texts
        blockTextInks = blocks.textInks
        blockTabsScenePath = blocks.tabs
        blockKeywords = layout.blocks.map(\.keyword)
        let messages = SequenceMessagePaths(messages: layout.messages)
        solidMessageLinesScenePath = messages.lines.solidLinesScenePath
        dottedMessageLinesScenePath = messages.lines.dottedLinesScenePath
        filledHeadsScenePath = messages.lines.filledHeadsScenePath
        strokedHeadsScenePath = messages.lines.strokedHeadsScenePath
        centralConnectionsScenePath = messages.lines.centralConnectionsScenePath
        inkedMessageLines = messages.inkedLines
        destructionsScenePath = Self.crosses(at: layout.destructions)
        numberBadgesScenePath = messages.numberBadges
        numberTexts = layout.messages.compactMap { message in message.number?.text }
        messageTextPatchesScenePath = messages.textPatches
        messageTexts = layout.messages.compactMap(\.text)
        messageTextInks = layout.messages.compactMap { message in message.text.map { _ in SequenceTextInk.ink(on: message.textBackground) } }
        notesScenePath = Self.roundedRectangles(layout.notes.map(\.frame))
        noteTexts = layout.notes.map(\.text)
        let participants = SequenceParticipantShapeDrawing(participants: layout.participants)
        participantShapesScenePath = participants.shapes
        participantFigureLinesScenePath = participants.lines
        participantFrontShapesScenePath = participants.frontShapes
        participantTexts = layout.participants.map(\.text)
        participantTextInks = layout.participants.map { participant in participant.kind.isFigure ? SequenceTextInk.ink(on: participant.boxColor) : nil }
        title = layout.title
    }

    static func roundedRectangle(_ frame: CGRect) -> DiagramScenePath {
        DiagramScenePath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
    }

    private static func roundedRectangles(_ frames: [CGRect]) -> DiagramScenePath {
        var path = DiagramScenePath()
        for frame in frames { path.addPathOfRoundedRect(frame, cornerWidth: SequenceDrawingParts.cornerRadius, cornerHeight: SequenceDrawingParts.cornerRadius) }
        return path
    }

    /// Each lifeline that runs down at all, as a vertical line.
    private static func lifelinePath(_ lifelines: [SequenceLayoutLifeline]) -> DiagramScenePath {
        var path = DiagramScenePath()
        for lifeline in lifelines where lifeline.bottom > lifeline.top {
            path.move(to: CGPoint(x: lifeline.x, y: lifeline.top))
            path.addLine(to: CGPoint(x: lifeline.x, y: lifeline.bottom))
        }
        return path
    }

    /// A cross of two diagonals at each center, `SequenceSpacing.destructionHalfSize` from it each way.
    private static func crosses(at centers: [CGPoint]) -> DiagramScenePath {
        var path = DiagramScenePath()
        let halfSize = SequenceSpacing.destructionHalfSize
        for center in centers {
            path.addLines(between: [CGPoint(x: center.x - halfSize, y: center.y - halfSize), CGPoint(x: center.x + halfSize, y: center.y + halfSize)])
            path.addLines(between: [CGPoint(x: center.x + halfSize, y: center.y - halfSize), CGPoint(x: center.x - halfSize, y: center.y + halfSize)])
        }
        return path
    }

    /// The blocks' frames, section lines, text patches and tabs, and their titles and section texts with their colors.
    private struct BlockPaths {
        var outlines = DiagramScenePath()
        var sectionLines = DiagramScenePath()
        var textPatches = DiagramScenePath()
        var tabs = DiagramScenePath()
        private(set) var texts: [DiagramTextBlock] = []
        private(set) var textInks: [DiagramColor?] = []

        init(blocks: [SequenceLayoutBlock]) {
            for block in blocks {
                if let title = block.title {
                    texts.append(title)
                    textInks.append(SequenceTextInk.ink(on: block.titleBackground))
                }
                for section in block.sections {
                    guard let text = section.text else { continue }
                    texts.append(text)
                    textInks.append(SequenceTextInk.ink(on: section.textBackground))
                }
                outlines.addPathOfRoundedRect(block.frame, cornerWidth: SequenceDrawingParts.cornerRadius, cornerHeight: SequenceDrawingParts.cornerRadius)
                for section in block.sections {
                    sectionLines.move(to: CGPoint(x: block.frame.minX, y: section.lineY))
                    sectionLines.addLine(to: CGPoint(x: block.frame.maxX, y: section.lineY))
                }
                for patch in block.textPatches { textPatches.addPathOfRoundedRect(patch, cornerWidth: SequenceDrawingParts.cornerRadius, cornerHeight: SequenceDrawingParts.cornerRadius) }
                tabs.addPathOfRoundedRect(block.tab, cornerWidth: SequenceDrawingParts.cornerRadius, cornerHeight: SequenceDrawingParts.cornerRadius)
            }
        }
    }
}

/// A `rect` background's shape and its color, or nil for the default shade.
public struct SequenceDrawingHighlight {
    public var path: CGPath { pathScenePath.coreGraphicsPath }
    let pathScenePath: DiagramScenePath
    public let color: SequenceHighlightColor?
}

/// A box's shape, its color (nil for the default shade), its title and the color Pele picks for the title on that color.
public struct SequenceDrawingBox {
    public var path: CGPath { pathScenePath.coreGraphicsPath }
    let pathScenePath: DiagramScenePath
    public let color: SequenceHighlightColor?
    public let title: DiagramTextBlock?
    /// The title's color on the box's color, or nil for the muted text color.
    public let titleInk: DiagramColor?
}
