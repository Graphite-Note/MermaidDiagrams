/**
 * File: SequenceDrawingParts.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's geometry grouped by how it is painted, back to front as Pele draws it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
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
    public let lifelines: CGPath
    /// Activation bars, back to front, each filled with the surface and outlined in the border color.
    public let activations: [CGPath]
    /// The blocks' frames, stroked in the border color; their section lines, dashed.
    public let blockOutlines: CGPath
    public let blockSectionLines: CGPath
    /// The patches behind block texts a lifeline crosses, filled in the background color.
    public let blockTextPatches: CGPath
    /// The blocks' titles and section texts, in the muted color, or in the color `blockTextInks` gives one on a colored
    /// `rect` or box.
    public let blockTexts: [DiagramTextBlock]
    public let blockTextInks: [DiagramColor?]
    /// The tabs, filled with the surface and outlined in the border color, and their keywords, bold and muted.
    public let blockTabs: CGPath
    public let blockKeywords: [DiagramTextBlock]
    /// Messages' lines in the line color, one point wide with round caps; dotted ones dashed.
    public let solidMessageLines: CGPath
    public let dottedMessageLines: CGPath
    /// Arrowheads and solid half heads, filled in the line color; crosses, open heads and stick half heads, stroked one
    /// point wide with round joins.
    public let filledHeads: CGPath
    public let strokedHeads: CGPath
    /// Central connections' circles on the lifelines, filled in the line color.
    public let centralConnections: CGPath
    /// The lines, heads and circles of the messages over a colored `rect` or box, painted as those above but in the
    /// text color that contrasts with that color, one group per color.
    public let inkedMessageLines: [SequenceDrawingMessageLines]
    /// The crosses that end destroyed lifelines, stroked in the line color `destructionLineWidth` wide, round capped.
    public let destructions: CGPath
    /// The numbers' badges, filled in the line color, and the numbers on them, in the background color.
    public let numberBadges: CGPath
    public let numberTexts: [DiagramTextBlock]
    /// The patches behind messages' texts a lifeline crosses, in the background color, and the texts.
    public let messageTextPatches: CGPath
    public let messageTexts: [DiagramTextBlock]
    /// For each of `messageTexts`, the color it takes on a colored `rect` or box, or nil for the text color.
    public let messageTextInks: [DiagramColor?]
    /// Notes, filled with the second surface and outlined in the border color, and their text.
    public let notes: CGPath
    public let noteTexts: [DiagramTextBlock]
    /// Participants' shapes and figures' circles, filled with the surface and outlined in the border color; figures'
    /// lines (an actor's limbs, a boundary's bar, a control's arrowhead, an entity's base, a cylinder's rim), stroked in
    /// the border color; the front cards of collections, filled and outlined after them.
    public let participantShapes: CGPath
    public let participantFigureLines: CGPath
    public let participantFrontShapes: CGPath
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
        let paths = SequenceDrawingPaths(layout: layout, making: DiagramCoreGraphicsPaths())
        boxes = zip(layout.boxes, paths.boxes).map { box, path in
            SequenceDrawingBox(path: path.path, color: box.color, title: box.title, titleInk: SequenceTextInk.ink(on: box.color))
        }
        highlights = zip(layout.highlights, paths.highlights).map { highlight, path in SequenceDrawingHighlight(path: path.path, color: highlight.color) }
        lifelines = paths.lifelines.path
        activations = paths.activations.map(\.path)
        blockOutlines = paths.blockOutlines.path
        blockSectionLines = paths.blockSectionLines.path
        blockTextPatches = paths.blockTextPatches.path
        (blockTexts, blockTextInks) = Self.blockTextsAndInks(of: layout.blocks)
        blockTabs = paths.blockTabs.path
        blockKeywords = layout.blocks.map(\.keyword)
        solidMessageLines = paths.messages.lines.solidLines.path
        dottedMessageLines = paths.messages.lines.dottedLines.path
        filledHeads = paths.messages.lines.filledHeads.path
        strokedHeads = paths.messages.lines.strokedHeads.path
        centralConnections = paths.messages.lines.centralConnections.path
        inkedMessageLines = paths.messages.inkedLines.map(SequenceDrawingMessageLines.init)
        destructions = paths.destructions.path
        numberBadges = paths.messages.numberBadges.path
        numberTexts = layout.messages.compactMap { message in message.number?.text }
        messageTextPatches = paths.messages.textPatches.path
        messageTexts = layout.messages.compactMap(\.text)
        messageTextInks = layout.messages.compactMap { message in message.text.map { _ in SequenceTextInk.ink(on: message.textBackground) } }
        notes = paths.notes.path
        noteTexts = layout.notes.map(\.text)
        participantShapes = paths.participants.shapes.path
        participantFigureLines = paths.participants.lines.path
        participantFrontShapes = paths.participants.frontShapes.path
        participantTexts = layout.participants.map(\.text)
        participantTextInks = layout.participants.map(SequenceDrawingParts.participantTextInk)
        title = layout.title
    }

    /// The blocks' titles and section texts, block by block, with the color each takes on its background.
    private static func blockTextsAndInks(of blocks: [SequenceLayoutBlock]) -> ([DiagramTextBlock], [DiagramColor?]) {
        var texts: [DiagramTextBlock] = []
        var inks: [DiagramColor?] = []
        SequenceDrawingPaths<DiagramCoreGraphicsPath>.forEachBlockText(of: blocks) { text, ink in
            texts.append(text)
            inks.append(ink)
        }
        return (texts, inks)
    }

    /// The color a figure's text takes on its box's color, or nil for the text color.
    static func participantTextInk(_ participant: SequenceLayoutParticipant) -> DiagramColor? {
        participant.kind.isFigure ? SequenceTextInk.ink(on: participant.boxColor) : nil
    }
}

/// A `rect` background's shape and its color, or nil for the default shade.
public struct SequenceDrawingHighlight {
    public let path: CGPath
    public let color: SequenceHighlightColor?
}

/// A box's shape, its color (nil for the default shade), its title and the color Pele picks for the title on that color.
public struct SequenceDrawingBox {
    public let path: CGPath
    public let color: SequenceHighlightColor?
    public let title: DiagramTextBlock?
    /// The title's color on the box's color, or nil for the muted text color.
    public let titleInk: DiagramColor?
}
