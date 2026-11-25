/**
 * File: ReferenceUserJourneyDiagramBuilder.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's user journey builder, frozen as main dad6fb8 read a task's score and actors on its
 *              Strings, which the journey reader is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// Collects a user journey as its statements are read: each task under the section written last, its score and its
/// actors read from the text after its first colon as Mermaid's database reads them. Sections and tasks count against
/// the node limit, and each actor named on a task against the edge limit: a task joins its actors.
struct ReferenceUserJourneyDiagramBuilder {
    private var title: String?
    private var sections: [DiagramLabel] = []
    private var tasks: [UserJourneyTask] = []
    private var accessibilityTitle: String?
    private var accessibilityDescription: String?
    private let limits: MermaidDiagramLimits
    private var nodeCount = 0
    private var actorMentionCount = 0

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The journey read so far, made through the model's own initializer, which works out what it derives from the tasks.
    var diagram: UserJourneyDiagram {
        UserJourneyDiagram(title: title, sections: sections, tasks: tasks, accessibilityTitle: accessibilityTitle,
                           accessibilityDescription: accessibilityDescription)
    }

    /// A later `title` replaces an earlier one; one with nothing but spaces leaves none.
    mutating func setTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmed.isEmpty ? nil : trimmed
    }

    mutating func addSection(_ label: DiagramLabel) throws(MermaidDiagramReadError) {
        try countNode()
        sections.append(label)
    }

    /// A task whose text is `label` and whose data is what follows its first colon, the colon included: `:score` or
    /// `:score:actor, actor`. Text after a third colon is left, as in Mermaid.
    mutating func addTask(_ label: DiagramLabel, data: Substring) throws(MermaidDiagramReadError) {
        try countNode()
        let pieces = data.dropFirst().split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        let writtenActors = pieces.count > 1 ? pieces[1] : nil
        let actorCount = writtenActors.map { actors in actors.utf8.reduce(1) { count, byte in byte == MermaidByte.comma ? count + 1 : count } } ?? 0
        guard actorMentionCount + actorCount <= limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        actorMentionCount += actorCount
        let actors = writtenActors.map { actors in actors.split(separator: ",", omittingEmptySubsequences: false).map(Self.trimmed) } ?? []
        tasks.append(UserJourneyTask(label: label, score: JavaScriptNumber.value(of: pieces[0]), actors: actors,
                                             sectionIndex: sections.isEmpty ? nil : sections.count - 1))
    }

    mutating func apply(_ statement: MermaidAccessibilityStatement) {
        switch statement {
        case .title(let title): accessibilityTitle = title
        case .description(let description): accessibilityDescription = description
        }
    }

    private mutating func countNode() throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += 1
    }

    /// An actor's name without the spaces and line breaks at its ends, as JavaScript's `trim` leaves it. A name of ASCII
    /// alone is trimmed on its bytes: the ASCII characters with Unicode's White_Space property are the tab to the carriage
    /// return and the space.
    static func trimmed(_ name: Substring) -> String {
        let bytes = name.utf8
        if bytes.allSatisfy({ byte in byte < 0x80 }) {
            func isWhiteSpace(_ byte: UInt8) -> Bool { (byte >= 0x09 && byte <= 0x0D) || byte == 0x20 }
            var start = bytes.startIndex
            var end = bytes.endIndex
            while start < end, isWhiteSpace(bytes[start]) { start = bytes.index(after: start) }
            while end > start, isWhiteSpace(bytes[bytes.index(before: end)]) { end = bytes.index(before: end) }
            return String(name[start..<end])
        }
        return trimmedScalarByScalar(name)
    }

    /// `trimmed(_:)` scalar by scalar through Unicode's White_Space property, for any name.
    static func trimmedScalarByScalar(_ name: Substring) -> String {
        var scalars = name.unicodeScalars
        while let first = scalars.first, first.properties.isWhitespace { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.properties.isWhitespace { scalars = scalars.dropLast() }
        return String(Substring(scalars))
    }
}
