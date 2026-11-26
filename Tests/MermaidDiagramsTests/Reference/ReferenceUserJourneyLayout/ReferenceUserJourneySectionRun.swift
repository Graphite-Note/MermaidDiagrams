/**
 * File: ReferenceUserJourneySectionRun.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's user journey sectionrun, frozen as main ba176e5 kept it (text blocks, paths and lists in each
 *              placed task), which the flat user journey layout is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams
/// A run of tasks written one after the other under sections of one name, which Pele draws under one band, as
/// Mermaid does: two sections of one name in a row make one band, and a section without tasks makes none.
struct ReferenceUserJourneySectionRun: Equatable {
    let firstTaskIndex: Int
    let taskCount: Int
    /// The sections' heading, or nil for the tasks written before the first section, which have no band.
    let heading: DiagramLabel?

    /// The runs of `diagram`'s tasks, in order. A task under the section of the task before it joins its run without
    /// its heading being compared.
    static func runs(of diagram: UserJourneyDiagram) -> [ReferenceUserJourneySectionRun] {
        var runs: [ReferenceUserJourneySectionRun] = []
        var lastSectionIndex: Int??
        for (index, task) in diagram.taskRecords.enumerated() {
            let heading = task.sectionIndex.map { section in diagram.sections[section] }
            defer { lastSectionIndex = task.sectionIndex }
            if let last = runs.last, lastSectionIndex == task.sectionIndex || last.heading == heading {
                runs[runs.count - 1] = ReferenceUserJourneySectionRun(firstTaskIndex: last.firstTaskIndex, taskCount: last.taskCount + 1, heading: heading)
            } else {
                runs.append(ReferenceUserJourneySectionRun(firstTaskIndex: index, taskCount: 1, heading: heading))
            }
        }
        return runs
    }
}
