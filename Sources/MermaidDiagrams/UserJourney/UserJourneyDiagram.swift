/**
 * File: UserJourneyDiagram.swift
 * ------------------------------
 * Layer: Core
 * Description: A user journey as its text describes it: sections, tasks with their scores and actors, the actors once
 *              each in Mermaid's order, and which of them each task names.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A Mermaid user journey (`journey`) as its text describes it: tasks in the order they are written, each with its
/// score and the actors who take part in it, under the sections written before them.
public struct UserJourneyDiagram: Equatable, Sendable {
    /// `title …` in the diagram, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// The `section …` headings, in the order they are written.
    public internal(set) var sections: [DiagramLabel]
    /// The tasks in the order they are written; the reader adds them with the actors they name (`init(title:sections:...)`
    /// works those out once for tasks given whole).
    public private(set) var tasks: [UserJourneyTask]
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    /// Everyone named on a task, once each, in the order of their names' UTF-16 code units, as Mermaid sorts them:
    /// an actor's place in this list picks its series color. A nameless actor (`Task: 5:`) is left out, as Pele draws
    /// none. Worked out once, as the tasks are read.
    public private(set) var actorNames: [String]
    /// For each actor written on a task, the tasks' in order, its index in `actorNames`, or -1 for a nameless one:
    /// task `k`'s from `firstActorMentions[k]` to `firstActorMentions[k + 1]`.
    private(set) var actorMentions: [Int32]
    /// Where each task's actors start in `actorMentions`, and their end after the last task's: one more than the tasks.
    private(set) var firstActorMentions: [Int32]

    /// A journey of `tasks` given whole, whose actors' names and indices are worked out from them as Mermaid sorts them.
    init(title: String? = nil, sections: [DiagramLabel] = [], tasks: [UserJourneyTask] = [], accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil) {
        let names = Set(tasks.flatMap(\.actors)).subtracting([""]).sorted { first, second in first.utf16.lexicographicallyPrecedes(second.utf16) }
        let indexByName = Dictionary(uniqueKeysWithValues: names.enumerated().map { index, name in (name, Int32(index)) })
        var mentions: [Int32] = []
        var firstMentions: [Int32] = [0]
        for task in tasks {
            for name in task.actors { mentions.append(indexByName[name] ?? -1) }
            firstMentions.append(Int32(mentions.count))
        }
        self.init(title: title, sections: sections, tasks: tasks, actorNames: names, actorMentions: mentions, firstActorMentions: firstMentions,
                  accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription)
    }

    /// A journey whose actors the reader has already interned and sorted.
    init(title: String?, sections: [DiagramLabel], tasks: [UserJourneyTask], actorNames: [String], actorMentions: [Int32],
         firstActorMentions: [Int32], accessibilityTitle: String?, accessibilityDescription: String?) {
        precondition(firstActorMentions.count == tasks.count + 1 && firstActorMentions.last.map(Int.init) == actorMentions.count,
                     "every task's actors are in the mentions")
        self.title = title
        self.sections = sections
        self.tasks = tasks
        self.actorNames = actorNames
        self.actorMentions = actorMentions
        self.firstActorMentions = firstActorMentions
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }

    /// The indices in `actorNames` of the actors task `index` names, in the order they are written, -1 for a nameless one.
    func actorIndices(ofTask index: Int) -> ArraySlice<Int32> {
        actorMentions[Int(firstActorMentions[index])..<Int(firstActorMentions[index + 1])]
    }
}

/// A step of a user journey: what the user does, how it felt, and who takes part.
public struct UserJourneyTask: Equatable, Sendable {
    public let label: DiagramLabel
    /// The score as written, read as JavaScript's `Number` reads it, as Mermaid does: any number, unbounded, or nil
    /// when it is not one (`Task: x`).
    public let score: Double?
    /// The actors written after the score, separated by commas, each without the spaces at its ends: an empty name
    /// is kept, as in Mermaid (`Task: 5:` names one actor without a name).
    public let actors: [String]
    /// The index in `UserJourneyDiagram.sections` of the section the task is written under, or nil for a task
    /// written before the first section.
    public let sectionIndex: Int?

    /// The lowest and highest places on a user journey's scale, and the middle a task without a score takes.
    public static let lowestLevel = 1.0
    public static let highestLevel = 5.0
    public static let middleLevel = 3.0

    init(label: DiagramLabel, score: Double?, actors: [String], sectionIndex: Int?) {
        self.label = label
        self.score = score
        self.actors = actors
        self.sectionIndex = sectionIndex
    }

    /// Where the task's face sits on the scale from 1 to 5: its score kept within the scale, or the middle without one.
    public var level: Double {
        guard let score else { return Self.middleLevel }
        return min(Self.highestLevel, max(Self.lowestLevel, score))
    }

    /// The face the task's score shows: happy above the middle, sad below it, neutral at it or without a score.
    public var mood: UserJourneyMood {
        guard let score else { return .neutral }
        if score > Self.middleLevel { return .happy }
        return score < Self.middleLevel ? .sad : .neutral
    }
}

/// The face a task's score shows, as Pele draws it.
public enum UserJourneyMood: Equatable, Sendable, CaseIterable {
    case happy
    case neutral
    case sad
}
