/**
 * File: SequenceMeasurements.swift
 * --------------------------------
 * Layer: Core
 * Description: The gaps and text widths a sequence diagram is laid out with: Pele's, or the tight ones it takes for a
 *              container too narrow for the diagram.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// The measurements of a sequence diagram that its tight layout changes (sequence/render.ts `draw` with `tight`): the
/// gap between participants, the narrowest participant's box and the room beside its text, the width texts wrap at, and
/// the paddings of notes, boxes, messages and blocks. In a tight layout every text wraps (at the shared wrapping width
/// unless its room is given) and a line still wider than that, or than 120 points, is broken between characters.
struct SequenceMeasurements: Equatable {
    var isTight = false
    var participantGap = SequenceSpacing.participantGap
    var minimumParticipantWidth = SequenceParticipantGeometry.minimumBoxWidth
    var participantHorizontalPadding = SequenceParticipantGeometry.horizontalPadding
    /// The width a text that wraps wraps at, unless it is given its own room.
    var wrappingWidth = SequenceSpacing.wrappingWidth
    var notePadding = SequenceSpacing.notePadding
    var boxPadding = SequenceSpacing.boxPadding
    var messagePadding = SequenceSpacing.messagePadding
    var noteOverhang = SequenceSpacing.noteOverhang
    var framePadding = SequenceSpacing.framePadding
    var frameNesting = SequenceSpacing.frameNesting
    /// The width a block's text wraps at, at least.
    var frameTextWidth = SequenceSpacing.frameTextWidth

    /// The narrowest a tight layout wraps a text at, and the narrowest it breaks a line at.
    static let narrowestTightWrappingWidth: CGFloat = 32
    static let narrowestBreakingWidth: CGFloat = 120
    /// What a tight layout's wrapping width leaves of a participant's share of the container, beyond the gap.
    static let tightShareMargin: CGFloat = 24
    /// The container's width when none is given (Pele's `options.maxWidth ?? 320`).
    static let unmeasuredWidth: CGFloat = 320

    static let standard = SequenceMeasurements()

    /// Pele's tight measurements for a diagram of `participantCount` participants in a container `availableWidth` wide:
    /// participants 8 points apart and 48 wide at least with 8 points beside their text; notes and boxes padded by 6,
    /// messages by 6, notes over lifelines reaching 8 past them, blocks padded by 12 and nested 6 further in; and texts
    /// wrapped at each participant's share of the container less the gap and 24 points, not under 32 nor over 160.
    static func tight(participantCount: Int, availableWidth: CGFloat?) -> SequenceMeasurements {
        var tight = SequenceMeasurements()
        tight.isTight = true
        tight.participantGap = 8
        tight.minimumParticipantWidth = 48
        tight.participantHorizontalPadding = 8
        tight.notePadding = 6
        tight.boxPadding = 6
        tight.messagePadding = 6
        tight.noteOverhang = 8
        tight.framePadding = 12
        tight.frameNesting = 6
        let room = (DiagramWidthFitting.limit(availableWidth) ?? unmeasuredWidth) - 2 * SequenceSpacing.padding
        let share = room / CGFloat(max(1, participantCount)) - tight.participantGap - tightShareMargin
        tight.wrappingWidth = min(SequenceSpacing.wrappingWidth, max(narrowestTightWrappingWidth, share))
        tight.frameTextWidth = min(SequenceSpacing.frameTextWidth, tight.wrappingWidth)
        return tight
    }
}
