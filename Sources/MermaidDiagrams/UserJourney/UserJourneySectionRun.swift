/**
 * File: UserJourneySectionRun.swift
 * ---------------------------------
 * Layer: Core
 * Description: The runs of a user journey's tasks under sections of one name, which Pele draws under one band, found
 *              from the tasks' section indices without copying the tasks.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// A run of tasks written one after the other under sections of one heading (or under none), drawn under one band.
struct UserJourneySectionRun: Equatable {
    let firstTaskIndex: Int
    var taskCount: Int
    /// The section of the run's last task, whose heading the band shows, or nil for tasks before the first section.
    var headingSection: Int?

    /// The runs, in order: a task joins the run before it when its section's heading is that run's (two sections of one
    /// name written one after the other share a band), compared only when their sections differ.
    static func runs(of diagram: UserJourneyDiagram) -> [UserJourneySectionRun] {
        var runs: [UserJourneySectionRun] = []
        let sections = diagram.sections
        runs.reserveCapacity(sections.count + 1)
        for (index, task) in diagram.taskRecords.enumerated() {
            let section = task.sectionIndex
            if let last = runs.last, last.headingSection == section || Self.heading(last.headingSection, in: sections) == Self.heading(section, in: sections) {
                runs[runs.count - 1].taskCount += 1
                runs[runs.count - 1].headingSection = section
            } else {
                runs.append(UserJourneySectionRun(firstTaskIndex: index, taskCount: 1, headingSection: section))
            }
        }
        return runs
    }

    private static func heading(_ section: Int?, in sections: [DiagramLabel]) -> DiagramLabel? {
        section.map { section in sections[section] }
    }
}
