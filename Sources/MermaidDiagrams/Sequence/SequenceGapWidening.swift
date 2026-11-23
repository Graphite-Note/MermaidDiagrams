/**
 * File: SequenceGapWidening.swift
 * -------------------------------
 * Layer: Core
 * Description: In a tight sequence diagram, the room the container has to spare given to the gaps that wrapped messages
 *              cross, when that wraps them on fewer lines, as Pele does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics

/// Pele's widening of a tight sequence diagram's gaps (sequence/render.ts, after `layout()`): the room the container
/// has beyond the diagram (less `hold`) is shared among the gaps crossed by messages that wrap on more lines than they
/// would unwrapped, evenly, or (when `byNeed` and several gaps are crossed) in proportion to what each gap lacks for its
/// widest message unwrapped when that wraps fewer of them; the widening is kept only when it wraps the messages on
/// fewer lines in all.
struct SequenceGapWidening<Measurer: DiagramTextMeasuring> {
    let diagram: SequenceDiagram
    let measurers: SequenceTextMeasurers<Measurer>

    /// The columns and extents after the widening, whether it wrapped the messages on fewer lines (`isGrown`), and
    /// whether it is the uneven share that did (`isUneven`).
    struct Result {
        let columns: SequenceColumns
        let extents: SequenceExtents
        let isGrown: Bool
        let isUneven: Bool
    }

    /// What can be given away, below which Pele rounds the share it gives in proportion to need.
    private static var roundingAllowance: CGFloat { 0.01 }

    /// The messages that wrap on more lines than they would unwrapped, how many lines they take in all, which gaps they
    /// cross, and the most each gap lacks, shared out over the gaps a message crosses, for its text unwrapped.
    private struct WrappedMessages {
        var eventIndices: [Int] = []
        var lineCount = 0
        var isCrossed: [Bool]
        var wanted: [CGFloat]

        var crossedCount: Int { isCrossed.filter { crossed in crossed }.count }
    }

    func widened(_ columns: SequenceColumns, availableWidth: CGFloat, hold: CGFloat, byNeed: Bool) -> Result {
        let extents = SequenceExtents(diagram: diagram, columns: columns, measurers: measurers)
        let unchanged = Result(columns: columns, extents: extents, isGrown: false, isUneven: false)
        let drawnWidth = (extents.maximumX - extents.minimumX + 2 * SequenceSpacing.padding).rounded(.up)
        let spare = availableWidth.rounded(.down) - drawnWidth - hold
        guard spare > 0 else { return unchanged }
        let wrapped = wrappedMessages(columns: columns, extents: extents)
        let crossedCount = wrapped.crossedCount
        guard crossedCount > 0 else { return unchanged }
        func spread(_ share: (Int) -> CGFloat) -> (columns: SequenceColumns, extents: SequenceExtents, counts: [Int]) {
            let respaced = columns.respaced(gaps: columns.gaps.indices.map { gapIndex in columns.gaps[gapIndex] + share(gapIndex) })
            let placed = SequenceExtents(diagram: diagram, columns: respaced, measurers: measurers)
            return (respaced, placed, wrapped.eventIndices.map { eventIndex in placed.eventTexts[eventIndex]?.lines.count ?? 0 })
        }
        func even(_ gapIndex: Int) -> CGFloat { wrapped.isCrossed[gapIndex] ? spare / CGFloat(crossedCount) : 0 }
        let missing = wrapped.wanted.reduce(0, +)
        func needed(_ gapIndex: Int) -> CGFloat { wrapped.wanted[gapIndex] * (spare - Self.roundingAllowance) / missing }
        var spreading = spread(even)
        var isUneven = false
        if byNeed, crossedCount > 1, missing > 0, columns.gaps.indices.contains(where: { gapIndex in needed(gapIndex) > even(gapIndex) }) {
            let first = spreading.counts
            let byNeedSpreading = spread(needed)
            isUneven = byNeedSpreading.counts.reduce(0, +) < first.reduce(0, +)
                && zip(byNeedSpreading.counts, first).allSatisfy { counts in counts.0 <= counts.1 }
            if isUneven { spreading = byNeedSpreading }
        }
        guard spreading.counts.reduce(0, +) < wrapped.lineCount else { return unchanged }
        return Result(columns: spreading.columns, extents: spreading.extents, isGrown: true, isUneven: isUneven)
    }

    /// The messages between two lifelines whose text `extents` wrapped on more lines than it takes unwrapped.
    private func wrappedMessages(columns: SequenceColumns, extents: SequenceExtents) -> WrappedMessages {
        let gapCount = columns.gaps.count
        var wrapped = WrappedMessages(isCrossed: Array(repeating: false, count: gapCount), wanted: Array(repeating: 0, count: gapCount))
        var stretch = [Int](repeating: 0, count: columns.centers.count + 1)
        let padding = measurers.measurements.messagePadding
        for (eventIndex, event) in diagram.events.enumerated() {
            guard case .message(let message) = event, message.sourceIndex != message.targetIndex, let text = extents.eventTexts[eventIndex] else { continue }
            let natural = measurers.unwrappedMessageBlock(message.text)
            guard text.lines.count > natural.lines.count else { continue }
            wrapped.eventIndices.append(eventIndex)
            wrapped.lineCount += text.lines.count
            let low = min(message.sourceIndex, message.targetIndex)
            let high = max(message.sourceIndex, message.targetIndex)
            stretch[low] += 1
            stretch[high] -= 1
            let short = (natural.size.width - (columns.centers[high] - columns.centers[low] - 2 * padding - SequenceSpacing.activationWidth))
                / CGFloat(high - low)
            for gapIndex in low..<high { wrapped.wanted[gapIndex] = max(wrapped.wanted[gapIndex], short) }
        }
        var active = 0
        for gapIndex in 0..<gapCount {
            active += stretch[gapIndex]
            wrapped.isCrossed[gapIndex] = active > 0
        }
        return wrapped
    }
}
