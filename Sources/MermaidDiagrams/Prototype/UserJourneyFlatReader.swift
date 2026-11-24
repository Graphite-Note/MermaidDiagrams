/**
 * File: UserJourneyFlatReader.swift
 * ---------------------------------
 * Layer: Core (prototype of the slow-types redesign, not for merging as is)
 * Description: Reads a user journey into a flat model of byte ranges of the source, numbers and interned actors, as
 *              UserJourneyParser and UserJourneyDiagramBuilder read it, without a string, a label or an array of its
 *              own per task; text it does not take yet (accessibility statements, bytes past ASCII where it trims, a
 *              score that is not a plain integer) is left to the full reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A range of the source's bytes.
struct FlatTextRange: Equatable {
    var start: Int32
    var end: Int32

    static let none = FlatTextRange(start: -1, end: -1)
    var isNone: Bool { start < 0 }
}

struct UserJourneyFlatTask {
    var label: FlatTextRange
    var score: Double
    var hasScore: Bool
    var firstActorMention: Int32
    var actorMentionCount: Int32
    var sectionIndex: Int32
}

/// A user journey as flat lists, reused from diagram to diagram (`removeAll` keeps their room).
struct UserJourneyFlatDiagram {
    var title = FlatTextRange.none
    var sections: [FlatTextRange] = []
    var tasks: [UserJourneyFlatTask] = []
    /// Each task's actors, as indices into `actorNames`, in the order written.
    var actorMentions: [Int32] = []
    /// Each actor once, in the order first named.
    var actorNames: [FlatTextRange] = []

    mutating func removeAll() {
        title = .none
        sections.removeAll(keepingCapacity: true)
        tasks.removeAll(keepingCapacity: true)
        actorMentions.removeAll(keepingCapacity: true)
        actorNames.removeAll(keepingCapacity: true)
    }
}

enum UserJourneyFlatReader {
    enum Outcome { case read, fullReaderNeeded, failed }

    /// Reads the statements after the `journey` keyword, from `start`.
    static func read(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, limits: MermaidDiagramLimits, into diagram: inout UserJourneyFlatDiagram) -> Outcome {
        var reader = Reader(bytes: bytes, position: start, limits: limits)
        return reader.readStatements(into: &diagram)
    }

    private struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>
        var position: Int
        let limits: MermaidDiagramLimits
        var nodeCount = 0

        init(bytes: UnsafeBufferPointer<UInt8>, position: Int, limits: MermaidDiagramLimits) {
            self.bytes = bytes
            self.position = position
            self.limits = limits
        }

        @inline(__always) func peek(_ offset: Int = 0) -> UInt8? {
            position + offset < bytes.count ? bytes[position + offset] : nil
        }

        mutating func skipToEndOfLine() {
            while position < bytes.count, bytes[position] != MermaidByte.newline { position += 1 }
        }

        static func isSpace(_ byte: UInt8) -> Bool {
            byte == 32 || byte == 9 || byte == 13 || byte == 11 || byte == 12
        }

        mutating func skipSpacesAndComments() {
            while let byte = peek() {
                if byte == MermaidByte.percent, peek(1) != MermaidByte.openingBrace {
                    skipToEndOfLine()
                } else if byte != MermaidByte.closingBrace, peek(1) == MermaidByte.percent, peek(2) == MermaidByte.percent {
                    position += 3
                    skipToEndOfLine()
                } else if byte == MermaidByte.newline {
                    return
                } else if Self.isSpace(byte) {
                    position += 1
                } else if byte == 35 {
                    skipToEndOfLine()
                } else {
                    return
                }
            }
        }

        func hasCaseInsensitivePrefix(_ literal: StaticString) -> Bool {
            let count = literal.utf8CodeUnitCount
            guard position + count <= bytes.count else { return false }
            let literalBytes = literal.utf8Start
            for offset in 0..<count where MermaidByte.lowercased(bytes[position + offset]) != literalBytes[offset] { return false }
            return true
        }

        func isAtJourneyKeyword() -> Bool {
            guard hasCaseInsensitivePrefix("journey") else { return false }
            guard let next = peek(7) else { return true }
            return !(MermaidByte.isLetter(next) || MermaidByte.isDigit(next) || next == MermaidByte.underscore)
        }

        mutating func skipText(endsAtColon: Bool) {
            while position < bytes.count {
                let byte = bytes[position]
                if byte == 35 || byte == MermaidByte.semicolon || byte == MermaidByte.newline || (endsAtColon && byte == MermaidByte.colon) { return }
                position += 1
            }
        }

        func trimmed(_ start: Int, _ end: Int) -> FlatTextRange {
            var first = start
            var last = end
            while first < last, MermaidByte.isWhitespace(bytes[first]) { first += 1 }
            while last > first, MermaidByte.isWhitespace(bytes[last - 1]) { last -= 1 }
            return FlatTextRange(start: Int32(first), end: Int32(last))
        }

        /// `keyword` and a space or line break, then text; nil (and nothing read) when there is no text.
        mutating func readKeywordText(_ keyword: StaticString, endsAtColon: Bool) -> FlatTextRange? {
            let count = keyword.utf8CodeUnitCount
            guard hasCaseInsensitivePrefix(keyword), let separator = peek(count), Self.isSpace(separator) || separator == MermaidByte.newline else { return nil }
            let saved = position
            position += count + 1
            let start = position
            skipText(endsAtColon: endsAtColon)
            guard position > start else {
                position = saved
                return nil
            }
            return trimmed(start, position)
        }

        mutating func countNode() -> Bool {
            guard nodeCount < limits.maximumNodeCount else { return false }
            nodeCount += 1
            return true
        }

        mutating func readStatements(into diagram: inout UserJourneyFlatDiagram) -> Outcome {
            while true {
                skipSpacesAndComments()
                guard let byte = peek() else { return .read }
                if byte == MermaidByte.newline {
                    position += 1
                } else if isAtJourneyKeyword() || byte == MermaidByte.colon || byte == MermaidByte.semicolon {
                    return .failed
                } else if let title = readKeywordText("title", endsAtColon: false) {
                    // Foundation's trimming of Unicode spaces is left to the full reader.
                    for index in Int(title.start)..<Int(title.end) where bytes[index] >= 0x80 { _ = index; return .fullReaderNeeded }
                    diagram.title = title.start == title.end ? .none : title
                } else if hasCaseInsensitivePrefix("acc") {
                    return .fullReaderNeeded
                } else if let section = readKeywordText("section", endsAtColon: true) {
                    guard countNode() else { return .failed }
                    diagram.sections.append(section)
                } else {
                    let outcome = readTask(into: &diagram)
                    guard case .read = outcome else { return outcome }
                }
            }
        }

        mutating func readTask(into diagram: inout UserJourneyFlatDiagram) -> Outcome {
            let start = position
            position += 1
            skipText(endsAtColon: true)
            let label = trimmed(start, position)
            skipSpacesAndComments()
            guard peek() == MermaidByte.colon else { return .failed }
            let dataStart = position
            position += 1
            skipText(endsAtColon: false)
            guard position > dataStart + 1 else { return .failed }
            guard countNode() else { return .failed }
            // The data after its colon, split at the next two colons: the score, the actors, the rest left.
            let dataEnd = position
            var scoreEnd = dataStart + 1
            while scoreEnd < dataEnd, bytes[scoreEnd] != MermaidByte.colon { scoreEnd += 1 }
            guard let score = Self.integerScore(bytes, dataStart + 1, scoreEnd) else { return .fullReaderNeeded }
            var task = UserJourneyFlatTask(label: label, score: score, hasScore: true, firstActorMention: Int32(diagram.actorMentions.count),
                                           actorMentionCount: 0, sectionIndex: Int32(diagram.sections.count - 1))
            if scoreEnd < dataEnd {
                var actorsEnd = scoreEnd + 1
                while actorsEnd < dataEnd, bytes[actorsEnd] != MermaidByte.colon { actorsEnd += 1 }
                var actorStart = scoreEnd + 1
                while true {
                    var actorEnd = actorStart
                    while actorEnd < actorsEnd, bytes[actorEnd] != MermaidByte.comma { actorEnd += 1 }
                    guard let name = asciiTrimmed(actorStart, actorEnd) else { return .fullReaderNeeded }
                    guard diagram.actorMentions.count < limits.maximumEdgeCount else { return .failed }
                    diagram.actorMentions.append(Self.interned(name, in: &diagram.actorNames, bytes: bytes))
                    task.actorMentionCount += 1
                    if actorEnd >= actorsEnd { break }
                    actorStart = actorEnd + 1
                }
            }
            diagram.tasks.append(task)
            return .read
        }

        /// The range trimmed of ASCII white space as Unicode's properties have it; nil with a byte past ASCII.
        func asciiTrimmed(_ start: Int, _ end: Int) -> FlatTextRange? {
            for index in start..<end where bytes[index] >= 0x80 { _ = index; return nil }
            var first = start
            var last = end
            while first < last, (bytes[first] >= 9 && bytes[first] <= 13) || bytes[first] == 32 { first += 1 }
            while last > first, (bytes[last - 1] >= 9 && bytes[last - 1] <= 13) || bytes[last - 1] == 32 { last -= 1 }
            return FlatTextRange(start: Int32(first), end: Int32(last))
        }

        /// JavaScript's `Number` of a plain integer of at most 15 digits between ASCII white space; nil for anything else.
        static func integerScore(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Double? {
            var first = start
            var last = end
            while first < last, (bytes[first] >= 9 && bytes[first] <= 13) || bytes[first] == 32 { first += 1 }
            while last > first, (bytes[last - 1] >= 9 && bytes[last - 1] <= 13) || bytes[last - 1] == 32 { last -= 1 }
            guard first < last, last - first <= 15 else { return nil }
            var value = 0
            for index in first..<last {
                let digit = Int(bytes[index]) &- 48
                guard digit >= 0, digit <= 9 else { return nil }
                value = value * 10 + digit
            }
            return Double(value)
        }

        /// The index of the actor named by the bytes of `name`, added when first named.
        static func interned(_ name: FlatTextRange, in names: inout [FlatTextRange], bytes: UnsafeBufferPointer<UInt8>) -> Int32 {
            let length = Int(name.end - name.start)
            for (index, known) in names.enumerated() where Int(known.end - known.start) == length {
                if memcmp(bytes.baseAddress! + Int(known.start), bytes.baseAddress! + Int(name.start), length) == 0 { return Int32(index) }
            }
            names.append(name)
            return Int32(names.count - 1)
        }
    }
}

import Foundation
