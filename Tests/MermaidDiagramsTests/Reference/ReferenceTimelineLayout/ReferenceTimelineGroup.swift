/**
 * File: ReferenceTimelineGroup.swift
 * ----------------------------------
 * Layer: Tests
 * Description: 0.7.0's timeline Group, frozen as main ba176e5 kept it (labels and text blocks in lists), which the
 *              flat timeline is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams
/// The periods of one section, or the periods written before the first section, which lead.
struct ReferenceTimelineGroup {
    let sectionIndex: Int?
    var periodIndices: [Int]

    /// One group per section, in order, after a leading group of the periods before the first section when there are any.
    static func groups(of diagram: ReferenceTimelineDiagram) -> [ReferenceTimelineGroup] {
        var sections = diagram.sections.indices.map { section in ReferenceTimelineGroup(sectionIndex: section, periodIndices: []) }
        var leading = ReferenceTimelineGroup(sectionIndex: nil, periodIndices: [])
        for (index, period) in diagram.periods.enumerated() {
            if let section = period.sectionIndex { sections[section].periodIndices.append(index) } else { leading.periodIndices.append(index) }
        }
        return leading.periodIndices.isEmpty ? sections : [leading] + sections
    }
}
