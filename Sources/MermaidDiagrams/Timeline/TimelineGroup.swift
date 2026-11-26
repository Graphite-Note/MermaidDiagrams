/**
 * File: TimelineGroup.swift
 * -------------------------
 * Layer: Core
 * Description: The periods of one section of a timeline, or those written before its first section, as a run of its
 *              periods.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// The periods of one section, or the periods written before the first section, which lead. A period is written under
/// the section written last before it, so each group's periods are a run of the timeline's periods, in order.
struct TimelineGroup {
    let sectionIndex: Int?
    let firstPeriod: Int
    var periodCount: Int

    var periodIndices: Range<Int> { firstPeriod..<(firstPeriod + periodCount) }

    /// One group per section, in order, after a leading group of the periods before the first section when there are any.
    static func groups(of diagram: TimelineDiagram) -> [TimelineGroup] {
        let periods = diagram.periodRecords
        var groups: [TimelineGroup] = []
        groups.reserveCapacity(diagram.sectionTexts.count + 1)
        var next = 0
        while next < periods.count, periods[next].sectionIndex < 0 { next += 1 }
        if next > 0 { groups.append(TimelineGroup(sectionIndex: nil, firstPeriod: 0, periodCount: next)) }
        for section in diagram.sectionTexts.indices {
            let first = next
            while next < periods.count, periods[next].sectionIndex == section { next += 1 }
            groups.append(TimelineGroup(sectionIndex: section, firstPeriod: first, periodCount: next - first))
        }
        return groups
    }
}
