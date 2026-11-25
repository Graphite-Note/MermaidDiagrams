/**
 * File: UserJourneySectionRun.swift
 * ---------------------------------
 * Layer: Core
 * Description: The runs of a user journey's tasks under sections of one name, which Pele draws under one band.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// A run of tasks written one after the other under sections of one name, which Pele draws under one band, as
/// Mermaid does: two sections of one name in a row make one band, and a section without tasks makes none.
struct UserJourneySectionRun: Equatable {
    let firstTaskIndex: Int
    let taskCount: Int
    /// The sections' heading, or nil for the tasks written before the first section, which have no band.
    let heading: DiagramLabel?

    /// The runs of `diagram`'s tasks, in order. A task under the section of the task before it joins its run without
    /// its heading being compared.
    static func runs(of diagram: UserJourneyDiagram) -> [UserJourneySectionRun] {
        var runs: [UserJourneySectionRun] = []
        var lastSectionIndex: Int??
        for (index, task) in diagram.taskRecords.enumerated() {
            let heading = task.sectionIndex.map { section in diagram.sections[section] }
            defer { lastSectionIndex = task.sectionIndex }
            if let last = runs.last, lastSectionIndex == task.sectionIndex || last.heading == heading {
                runs[runs.count - 1] = UserJourneySectionRun(firstTaskIndex: last.firstTaskIndex, taskCount: last.taskCount + 1, heading: heading)
            } else {
                runs.append(UserJourneySectionRun(firstTaskIndex: index, taskCount: 1, heading: heading))
            }
        }
        return runs
    }
}
