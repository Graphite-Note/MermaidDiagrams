/**
 * File: UserJourneyDiagramBuilder.swift
 * -------------------------------------
 * Layer: Core
 * Description: Collects a user journey as its statements are read: sections, tasks with their scores and actors read
 *              on the bytes after a task's colon, the actors interned once each, and the title and accessibility text.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import Foundation

/// Collects a user journey as its statements are read: each task under the section written last, its score and its
/// actors read from the text after its first colon as Mermaid's database reads them. Sections and tasks count against
/// the node limit, and each actor named on a task against the edge limit: a task joins its actors. Each actor is named
/// once in a table as it is first met, so that the diagram's sorted names and each task's indices into them cost one
/// sort of the distinct names.
struct UserJourneyDiagramBuilder {
    private let limits: MermaidDiagramLimits
    private var nodeCount = 0
    private var actorMentionCount = 0
    private var title: String?
    private var sections: [DiagramLabel] = []
    private var tasks: [UserJourneyTaskRecord] = []
    private var accessibilityTitle: String?
    private var accessibilityDescription: String?
    /// Each named actor's place in `actorNamesInFirstNamedOrder`, once there are more than `mostActorsSearched`: fewer
    /// are found by comparing the names one by one, which costs less than hashing.
    private var actorIndexByName: [String: Int32] = [:]
    private var actorNamesInFirstNamedOrder: [String] = []
    /// The actors of the tasks so far, each as its place in `actorNamesInFirstNamedOrder`, -1 for a nameless one.
    private var actorMentions: [Int32] = []
    private var firstActorMentions: [Int32] = [0]

    /// The most distinct actors looked up by comparing their names in turn.
    private static let mostActorsSearched = 8
    /// The room the tasks' lists are first made with, so that a short journey's grow once.
    private static let firstTaskCapacity = 16

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
        tasks.reserveCapacity(Self.firstTaskCapacity)
        actorMentions.reserveCapacity(Self.firstTaskCapacity)
        firstActorMentions.reserveCapacity(Self.firstTaskCapacity + 1)
    }

    /// The journey read, its actors sorted by their names' UTF-16 code units, as Mermaid sorts them, and each task's
    /// indices made indices into that order.
    var diagram: UserJourneyDiagram {
        let sortedPlaces = actorNamesInFirstNamedOrder.indices.sorted { first, second in
            actorNamesInFirstNamedOrder[first].utf16.lexicographicallyPrecedes(actorNamesInFirstNamedOrder[second].utf16)
        }
        var sortedIndexByPlace = [Int32](repeating: 0, count: sortedPlaces.count)
        for (sortedIndex, place) in sortedPlaces.enumerated() { sortedIndexByPlace[place] = Int32(sortedIndex) }
        return UserJourneyDiagram(title: title, sections: sections, taskRecords: tasks,
                                  actorNames: sortedPlaces.map { place in actorNamesInFirstNamedOrder[place] },
                                  actorMentions: actorMentions.map { place in place < 0 ? place : sortedIndexByPlace[Int(place)] },
                                  firstActorMentions: firstActorMentions, accessibilityTitle: accessibilityTitle,
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

    /// A task whose text is `label` and whose data, `data`, is what follows its first colon, the colon included:
    /// `:score` or `:score:actor, actor`. Text after a third colon is left, as in Mermaid. Data of ASCII alone, as nearly
    /// all is, is split, trimmed and read on its bytes; any other is read as Swift's characters split it
    /// (`addTask(_:writtenData:)`), as a character past ASCII may join a colon or a comma into one.
    mutating func addTask(_ label: DiagramLabel, data: UnsafeBufferPointer<UInt8>) throws(MermaidDiagramReadError) {
        precondition(data.first == MermaidByte.colon, "a task's data starts at its colon")
        guard Self.isASCII(data) else { return try addTask(label, writtenData: Substring(String(decoding: data, as: UTF8.self))) }
        try countNode()
        var scoreEnd = data.count
        var actorsEnd = data.count
        if let colon = Self.index(of: MermaidByte.colon, in: data, from: 1) {
            scoreEnd = colon
            actorsEnd = Self.index(of: MermaidByte.colon, in: data, from: colon + 1) ?? data.count
        }
        let hasActors = scoreEnd < data.count
        let actorCount = hasActors ? Self.count(of: MermaidByte.comma, in: data, from: scoreEnd + 1, to: actorsEnd) + 1 : 0
        guard actorMentionCount + actorCount <= limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        actorMentionCount += actorCount
        if hasActors {
            var start = scoreEnd + 1
            while true {
                let end = Self.index(of: MermaidByte.comma, in: data, from: start, to: actorsEnd) ?? actorsEnd
                let name = UnsafeBufferPointer(rebasing: data[Self.trimmedASCII(data, start, end)])
                actorMentions.append(name.isEmpty ? -1 : place(ofActorWritten: name))
                guard end < actorsEnd else { break }
                start = end + 1
            }
        }
        firstActorMentions.append(Int32(actorMentions.count))
        tasks.append(UserJourneyTaskRecord(label: label, score: Self.score(UnsafeBufferPointer(rebasing: data[1..<scoreEnd])),
                                           sectionIndex: sections.isEmpty ? nil : sections.count - 1))
    }

    /// `addTask(_:data:)` for data with a character past ASCII, split and trimmed on Swift's characters and scalars.
    private mutating func addTask(_ label: DiagramLabel, writtenData data: Substring) throws(MermaidDiagramReadError) {
        try countNode()
        let pieces = data.dropFirst().split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        let writtenActors = pieces.count > 1 ? pieces[1] : nil
        let actorCount = writtenActors.map { actors in actors.utf8.reduce(1) { count, byte in byte == MermaidByte.comma ? count + 1 : count } } ?? 0
        guard actorMentionCount + actorCount <= limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        actorMentionCount += actorCount
        let actors = writtenActors.map { actors in actors.split(separator: ",", omittingEmptySubsequences: false).map(Self.trimmed) } ?? []
        for name in actors { actorMentions.append(name.isEmpty ? -1 : place(ofActor: name)) }
        firstActorMentions.append(Int32(actorMentions.count))
        tasks.append(UserJourneyTaskRecord(label: label, score: JavaScriptNumber.value(of: pieces[0]), sectionIndex: sections.isEmpty ? nil : sections.count - 1))
    }

    /// The place of the actor whose ASCII name is `name`, compared on its bytes while there are few actors, so that a
    /// name already met makes no text.
    private mutating func place(ofActorWritten name: UnsafeBufferPointer<UInt8>) -> Int32 {
        if actorNamesInFirstNamedOrder.count <= Self.mostActorsSearched,
           let place = actorNamesInFirstNamedOrder.firstIndex(where: { known in known.utf8.elementsEqual(name) }) {
            return Int32(place)
        }
        return place(ofActor: String(decoding: name, as: UTF8.self))
    }

    /// `name`'s place among the actors in the order they were first named, added when it is new: looked up by comparing
    /// names while there are few, then in a table made of them once.
    private mutating func place(ofActor name: String) -> Int32 {
        if actorNamesInFirstNamedOrder.count <= Self.mostActorsSearched {
            if let place = actorNamesInFirstNamedOrder.firstIndex(of: name) { return Int32(place) }
        } else if let place = actorIndexByName[name] {
            return place
        }
        let place = Int32(actorNamesInFirstNamedOrder.count)
        actorNamesInFirstNamedOrder.append(name)
        if actorNamesInFirstNamedOrder.count > Self.mostActorsSearched {
            if actorIndexByName.isEmpty {
                for (index, earlier) in actorNamesInFirstNamedOrder.enumerated() { actorIndexByName[earlier] = Int32(index) }
            } else {
                actorIndexByName[name] = place
            }
        }
        return place
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

    // MARK: Bytes

    private static func isASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var combined: UInt8 = 0
        for byte in bytes { combined |= byte }
        return combined < 0x80
    }

    private static func index(of target: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int? = nil) -> Int? {
        var index = start
        let end = end ?? bytes.count
        while index < end {
            if bytes[index] == target { return index }
            index += 1
        }
        return nil
    }

    private static func count(of target: UInt8, in bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Int {
        var count = 0
        for index in start..<end where bytes[index] == target { count += 1 }
        return count
    }

    /// The ASCII characters with Unicode's White_Space property, which `trimmed(_:)` trims: the tab to the carriage return
    /// and the space. JavaScript's white space is the same within ASCII.
    private static func isASCIIWhiteSpace(_ byte: UInt8) -> Bool {
        (byte >= 0x09 && byte <= 0x0D) || byte == 0x20
    }

    /// `start..<end` without the ASCII white space at its ends.
    private static func trimmedASCII(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Range<Int> {
        var first = start
        var last = end
        while first < last, isASCIIWhiteSpace(bytes[first]) { first += 1 }
        while last > first, isASCIIWhiteSpace(bytes[last - 1]) { last -= 1 }
        return first..<last
    }

    /// The most digits a whole number may have to be read here, exactly: below 2^53, so that adding digits up gives the
    /// value `Double(_:)` reads.
    private static let mostExactDigits = 15

    /// An ASCII score as `JavaScriptNumber.value(of:)` reads it: a whole number of at most fifteen digits, as written
    /// nearly always, between white space, added up on its bytes; anything else through `JavaScriptNumber`.
    private static func score(_ written: UnsafeBufferPointer<UInt8>) -> Double? {
        let digits = trimmedASCII(written, 0, written.count)
        if !digits.isEmpty, digits.count <= mostExactDigits {
            var value = 0.0
            var isWholeNumber = true
            for index in digits {
                let digit = written[index] &- UInt8(ascii: "0")
                guard digit < 10 else {
                    isWholeNumber = false
                    break
                }
                value = value * 10 + Double(digit)
            }
            if isWholeNumber { return value }
        }
        return JavaScriptNumber.value(of: Substring(String(decoding: written, as: UTF8.self)))
    }

    /// An actor's name without the spaces and line breaks at its ends, as JavaScript's `trim` leaves it. A name of ASCII
    /// alone is trimmed on its bytes: the ASCII characters with Unicode's White_Space property are the tab to the carriage
    /// return and the space.
    static func trimmed(_ name: Substring) -> String {
        let bytes = name.utf8
        if bytes.allSatisfy({ byte in byte < 0x80 }) {
            var start = bytes.startIndex
            var end = bytes.endIndex
            while start < end, isASCIIWhiteSpace(bytes[start]) { start = bytes.index(after: start) }
            while end > start, isASCIIWhiteSpace(bytes[bytes.index(before: end)]) { end = bytes.index(before: end) }
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
