/**
 * File: SequenceColumns.swift
 * ---------------------------
 * Layer: Core
 * Description: Where each sequence participant's lifeline runs across the page, as Pele places them: apart by their
 *              boxes, by the messages and notes between them, and by the boxes they are grouped in.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

/// Where each participant's lifeline runs across the page, as Pele places them: neighbours at least their boxes'
/// half widths and the participant gap apart (and a box's padding further for each in a box when their boxes differ),
/// and further where a message or a note between them needs the room. A message across several lifelines widens each
/// gap it crosses by an equal share of what is missing; a box whose title is wider than its participants pushes its
/// neighbours away.
struct SequenceColumns {
    let participantTexts: [DiagramTextBlock]
    let participantSizes: [CGSize]
    /// Each lifeline's x, the first at 0.
    private(set) var centers: [CGFloat]
    /// The gap between each two neighbouring lifelines, from which `centers` are placed.
    private(set) var gaps: [CGFloat]
    /// Each event's text when it is a message or a note, measured and wrapped as its text asks; nil otherwise.
    let eventTexts: [DiagramTextBlock?]
    /// Each event's number under `autonumber`, or nil.
    let numberTexts: [String?]
    /// The width of each event's number badge, or 0.
    let numberWidths: [CGFloat]
    /// The boxes' runs of participants, with how far each grows for its title.
    let boxRuns: SequenceBoxRuns

    init<Measurer>(diagram: SequenceDiagram, measurers: SequenceTextMeasurers<Measurer>) {
        participantTexts = diagram.participants.map { participant in measurers.participantBlock(participant.label) }
        let measurements = measurers.measurements
        participantSizes = zip(diagram.participants, participantTexts).map { participant, text in
            SequenceParticipantGeometry.size(of: participant.kind, textSize: text.size, fontSize: measurers.participantText.fontSize,
                                             minimumWidth: measurements.minimumParticipantWidth, horizontalPadding: measurements.participantHorizontalPadding)
        }
        numberTexts = SequenceMessageNumbers(events: diagram.events).numberTexts
        numberWidths = numberTexts.map { text in
            text.map { number in max(SequenceSpacing.numberHeight, measurers.smallestText.width(of: number) + SequenceSpacing.numberExtraWidth) } ?? 0
        }
        let (eventTexts, requirements) = Self.eventTexts(of: diagram, measurers: measurers, participantSizes: participantSizes, numberWidths: numberWidths)
        self.eventTexts = eventTexts
        let participants = diagram.participants
        var boxRuns = SequenceBoxRuns(diagram: diagram, measurers: measurers)
        var gaps = requirements.gaps(participantWidths: participantSizes.map(\.width)) { [boxRuns] gapIndex in
            boxRuns.room(between: participants[gapIndex], and: participants[gapIndex + 1])
        }
        boxRuns.widen(&gaps, centers: Self.centers(gaps: gaps, count: participants.count), sizes: participantSizes)
        self.boxRuns = boxRuns
        self.gaps = gaps
        centers = Self.centers(gaps: gaps, count: participants.count)
    }

    /// Each event's text when it is a message or a note, and what the messages and notes ask of the gaps.
    private static func eventTexts<Measurer>(of diagram: SequenceDiagram, measurers: SequenceTextMeasurers<Measurer>, participantSizes: [CGSize],
                                             numberWidths: [CGFloat]) -> ([DiagramTextBlock?], WidthRequirements) {
        let measurements = measurers.measurements
        var requirements = WidthRequirements(participantCount: diagram.participants.count, measurements: measurements)
        var eventTexts: [DiagramTextBlock?] = []
        eventTexts.reserveCapacity(diagram.events.count)
        for (eventIndex, event) in diagram.events.enumerated() {
            switch event {
            case .note(let note):
                let text = measurers.messageBlock(note.text, wraps: note.wrapsText)
                requirements.addNote(note.placement, width: text.size.width + 2 * measurements.notePadding)
                eventTexts.append(text)
            case .message(let message):
                let text = measurers.messageBlock(message.text, wraps: message.wrapsText)
                let createdHalfWidth = message.createsTarget ? participantSizes[message.targetIndex].width / 2 : 0
                let connectionsWidth = message.hasCentralConnectionAtSource || message.hasCentralConnectionAtTarget
                    ? 4 * SequenceSpacing.centralConnectionRadius : 0
                // A tight layout asks for no more room than its wrapping width less 16 points (at least 16) for a message's text.
                let tightTextWidth = min(text.size.width, max(Self.tightTextAllowance, measurements.wrappingWidth - Self.tightTextAllowance))
                requirements.addMessage(from: message.sourceIndex, to: message.targetIndex, textWidth: text.size.width,
                                        tightTextWidth: measurements.isTight ? tightTextWidth : text.size.width,
                                        extraWidth: numberWidths[eventIndex] + createdHalfWidth + connectionsWidth, numberWidth: numberWidths[eventIndex])
                eventTexts.append(text)
            case .activationStart, .activationEnd, .blockStart, .blockSection, .blockEnd, .numbering:
                eventTexts.append(nil)
            }
        }
        return (eventTexts, requirements)
    }

    /// The least room a tight layout asks for a message's text, and what it leaves of its wrapping width.
    static let tightTextAllowance: CGFloat = 16

    /// The columns with the lifelines placed by `gaps` instead.
    func respaced(gaps: [CGFloat]) -> SequenceColumns {
        var respaced = self
        respaced.gaps = gaps
        respaced.centers = Self.centers(gaps: gaps, count: centers.count)
        return respaced
    }

    /// Each lifeline's x from the gaps between neighbours, the first at 0.
    private static func centers(gaps: [CGFloat], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        var centers = [CGFloat(0)]
        centers.reserveCapacity(count)
        for gap in gaps { centers.append(centers[centers.count - 1] + gap) }
        return centers
    }

    /// The width each gap between lifelines, or each run of gaps, must have at least.
    private struct WidthRequirements {
        let participantCount: Int
        let measurements: SequenceMeasurements
        /// By the first and last lifeline of the run (`first * participantCount + last`).
        private var widthByRun: [Int: CGFloat] = [:]

        init(participantCount: Int, measurements: SequenceMeasurements) {
            self.participantCount = participantCount
            self.measurements = measurements
        }

        mutating func addNote(_ placement: SequenceNotePlacement, width: CGFloat) {
            let besideWidth = width + 2 * SequenceSpacing.noteGap + SequenceSpacing.activationWidth
            switch placement {
            case .leftOf(let index): require(from: index - 1, to: index, width: besideWidth)
            case .rightOf(let index): require(from: index, to: index + 1, width: besideWidth)
            case .over(let first, let last) where first == last:
                require(from: first - 1, to: first, width: width / 2 + SequenceSpacing.noteGap)
                require(from: first, to: first + 1, width: width / 2 + SequenceSpacing.noteGap)
            case .over(let first, let last):
                require(from: min(first, last), to: max(first, last), width: width - 2 * measurements.noteOverhang)
            }
        }

        /// A message's need: a loop's room beside its participant (for its whole text), or the text (`tightTextWidth` of
        /// it), padding, activation and `extraWidth` (the number, a created participant's half box, central connections'
        /// circles) between two lifelines.
        mutating func addMessage(from source: Int, to target: Int, textWidth: CGFloat, tightTextWidth: CGFloat, extraWidth: CGFloat,
                                 numberWidth: CGFloat) {
            if source == target {
                require(from: source, to: source + 1, width: SequenceSpacing.selfLoopWidth + SequenceSpacing.selfLoopTextGap + textWidth
                            + SequenceSpacing.selfLoopTextRoom + SequenceSpacing.activationWidth + numberWidth)
            } else {
                require(from: min(source, target), to: max(source, target),
                        width: tightTextWidth + 2 * measurements.messagePadding + SequenceSpacing.activationWidth + extraWidth)
            }
        }

        private mutating func require(from first: Int, to last: Int, width: CGFloat) {
            guard first >= 0, last < participantCount else { return }
            let key = first * participantCount + last
            widthByRun[key] = max(widthByRun[key] ?? 0, width)
        }

        /// Each gap between neighbours: the wider of its boxes' needs (with `boxRoom`) and its own requirement; then each
        /// run of several gaps, the narrowest runs first, shares out what it still lacks.
        func gaps(participantWidths: [CGFloat], boxRoom: (Int) -> CGFloat) -> [CGFloat] {
            guard participantCount > 1 else { return [] }
            var gaps = (0..<(participantCount - 1)).map { gapIndex in
                max(participantWidths[gapIndex] / 2 + participantWidths[gapIndex + 1] / 2 + measurements.participantGap + boxRoom(gapIndex),
                    widthByRun[gapIndex * participantCount + gapIndex + 1] ?? 0)
            }
            let runs = widthByRun.compactMap { key, width -> (first: Int, last: Int, width: CGFloat)? in
                let first = key / participantCount
                let last = key % participantCount
                return last - first > 1 ? (first, last, width) : nil
            }.sorted { left, right in
                left.last - left.first != right.last - right.first ? left.last - left.first < right.last - right.first : left.first < right.first
            }
            for run in runs {
                let total = gaps[run.first..<run.last].reduce(0, +)
                guard total < run.width else { continue }
                let share = (run.width - total) / CGFloat(run.last - run.first)
                for gapIndex in run.first..<run.last { gaps[gapIndex] += share }
            }
            return gaps
        }
    }
}
