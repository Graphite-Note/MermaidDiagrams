/**
 * File: SequenceBoxRuns.swift
 * ---------------------------
 * Layer: Core
 * Description: Where a sequence diagram's boxes reach across the page: each run of neighbouring participants in one box,
 *              padded, and widened for its title, as Pele places them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Neighbouring participants in the same box, drawn as one box behind them. A box whose participants are not next to
/// each other is drawn once for each run, each with its title, as in Pele.
struct SequenceBoxRun {
    let boxIndex: Int
    let firstParticipantIndex: Int
    var lastParticipantIndex: Int
    /// The box's title, measured in the messages' text and wrapped when it asks to; nil when the box has none.
    let title: DiagramTextBlock?
    /// How far the box reaches past its participants on each side, beyond its padding, for a title wider than them.
    var growth: CGFloat = 0
}

/// The runs of a sequence diagram's boxes, Pele's `BoxRun`s.
struct SequenceBoxRuns {
    private(set) var runs: [SequenceBoxRun] = []
    /// The tallest title's height, 0 without titles.
    let titleHeight: CGFloat

    init<Measurer>(diagram: SequenceDiagram, measurers: SequenceTextMeasurers<Measurer>) {
        for (index, participant) in diagram.participants.enumerated() {
            guard let boxIndex = participant.boxIndex else { continue }
            if let last = runs.last, last.boxIndex == boxIndex, last.lastParticipantIndex == index - 1 {
                runs[runs.count - 1].lastParticipantIndex = index
                continue
            }
            let box = diagram.boxes[boxIndex]
            let title = box.title.map { label in measurers.messageBlock(label, wrappingWidth: box.wrapsTitle ? SequenceSpacing.wrappingWidth : nil) }
            runs.append(SequenceBoxRun(boxIndex: boxIndex, firstParticipantIndex: index, lastParticipantIndex: index, title: title))
        }
        titleHeight = runs.compactMap { run in run.title.map { title in title.lines.isEmpty ? 0 : title.size.height } }.max() ?? 0
    }

    /// The room above the participants' boxes: the padding and the tallest title with its gap, or nothing without boxes.
    var topRoom: CGFloat {
        guard !runs.isEmpty else { return 0 }
        return SequenceSpacing.boxPadding + (titleHeight > 0 ? titleHeight + SequenceSpacing.boxTitleGap : 0)
    }

    /// What the boxes add to the gap between two neighbouring participants: a padding for each that is in a box, when
    /// their boxes differ.
    static func room(between left: SequenceParticipant, and right: SequenceParticipant) -> CGFloat {
        guard left.boxIndex != right.boxIndex else { return 0 }
        return (left.boxIndex == nil ? 0 : SequenceSpacing.boxPadding) + (right.boxIndex == nil ? 0 : SequenceSpacing.boxPadding)
    }

    /// Widens the gaps around each run whose title is wider than its participants, by half the difference on each side,
    /// the participants placed at `centers`.
    mutating func widen(_ gaps: inout [CGFloat], centers: [CGFloat], sizes: [CGSize]) {
        for runIndex in runs.indices {
            let run = runs[runIndex]
            let inner = centers[run.lastParticipantIndex] + sizes[run.lastParticipantIndex].width / 2
                - (centers[run.firstParticipantIndex] - sizes[run.firstParticipantIndex].width / 2)
            let growth = max(0, ((run.title?.size.width ?? 0) - inner) / 2)
            runs[runIndex].growth = growth
            guard growth > 0 else { continue }
            if run.firstParticipantIndex > 0 { gaps[run.firstParticipantIndex - 1] += growth }
            if run.lastParticipantIndex < gaps.count { gaps[run.lastParticipantIndex] += growth }
        }
    }

    /// The run's left and right edges, the participants placed at `centers`.
    func edges(of run: SequenceBoxRun, centers: [CGFloat], sizes: [CGSize]) -> (left: CGFloat, right: CGFloat) {
        (centers[run.firstParticipantIndex] - sizes[run.firstParticipantIndex].width / 2 - SequenceSpacing.boxPadding - run.growth,
         centers[run.lastParticipantIndex] + sizes[run.lastParticipantIndex].width / 2 + SequenceSpacing.boxPadding + run.growth)
    }
}
