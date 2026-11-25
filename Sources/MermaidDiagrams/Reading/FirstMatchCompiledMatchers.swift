/**
 * File: FirstMatchCompiledMatchers.swift
 * --------------------------------------
 * Layer: Core
 * Description: A tokenizer's matchers compiled into flat records, their literals in one block of bytes, and matched in
 *              one switch over the record's operation instead of a closure per rule.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A tokenizer's matchers, one record per rule in the rules' order. A record names its operation, its byte classes and
/// flag, and where its literal (and a block comment's closing) is in `literals`; a type's own pattern is kept apart and
/// called as before. Matching gives what the 0.7.0 closures gave, byte for byte (`FirstMatchTokenizerEquivalenceTests`).
struct FirstMatchCompiledMatchers: Sendable {
    private enum Operation: UInt8 {
        case literal, keyword, name, quoted, percentComment, directive, frontMatterFence, blockComment, lineComment, whitespace, lineStatement
        case accessibilityTitle, custom
    }

    private struct Record {
        var operation: Operation
        var firstClass = FirstMatchByteClass.letter
        var restClass = FirstMatchByteClass.letter
        var flag = false
        var literalStart = 0
        var literalCount = 0
        /// A block comment's closing, as an index into `closings`; a type's own pattern, as an index into `customs`.
        var otherIndex = 0
    }

    private let records: [Record]
    private let literals: [UInt8]
    private let closings: [[UInt8]]
    private let customs: [FirstMatchTokenPattern]

    init(_ matchers: [FirstMatchTokenMatcher]) {
        var literals: [UInt8] = []
        var closings: [[UInt8]] = []
        var customs: [FirstMatchTokenPattern] = []
        records = matchers.map { matcher in Self.record(of: matcher, literals: &literals, closings: &closings, customs: &customs) }
        self.literals = literals
        self.closings = closings
        self.customs = customs
    }

    /// The record of `matcher`, its literal appended to `literals`, a block comment's closing to `closings`, a type's
    /// own pattern to `customs`.
    private static func record(of matcher: FirstMatchTokenMatcher, literals: inout [UInt8], closings: inout [[UInt8]],
                               customs: inout [FirstMatchTokenPattern]) -> Record {
        func record(_ operation: Operation, literal: [UInt8] = []) -> Record {
            defer { literals += literal }
            return Record(operation: operation, literalStart: literals.count, literalCount: literal.count)
        }
        var made: Record
        switch matcher {
        case .literal(let text): made = record(.literal, literal: text)
        case .keyword(let word): made = record(.keyword, literal: word)
        case .name(let first, let rest):
            made = record(.name)
            (made.firstClass, made.restClass) = (first, rest)
        case .quoted: made = record(.quoted)
        case .percentComment: made = record(.percentComment)
        case .directive: made = record(.directive)
        case .frontMatterFence: made = record(.frontMatterFence)
        case .blockComment(let opening, let closing):
            made = record(.blockComment, literal: opening)
            made.otherIndex = closings.count
            closings.append(closing)
        case .lineComment(let opening): made = record(.lineComment, literal: opening)
        case .whitespace(let isJavaScriptWhitespace):
            made = record(.whitespace)
            made.flag = isJavaScriptWhitespace
        case .lineStatement(let keyword, let leadingBlanks, let continuesName):
            made = record(.lineStatement, literal: keyword)
            made.flag = leadingBlanks
            made.restClass = continuesName
        case .accessibilityTitle(let leadingBlanks):
            made = record(.accessibilityTitle)
            made.flag = leadingBlanks
        case .custom(let pattern):
            made = record(.custom)
            made.otherIndex = customs.count
            customs.append(pattern)
        }
        return made
    }

    /// What rule `index`'s matcher finds at `position`.
    func match(_ index: Int, in text: inout FirstMatchTokenizerText, at position: Int) -> FirstMatchTokenMatch {
        let record = records[index]
        let bytes = text.bytes
        switch record.operation {
        case .literal:
            return startsWithLiteral(bytes, at: position, record) ? .matched(end: position + record.literalCount) : .none
        case .keyword:
            let end = position + record.literalCount
            guard startsWithLiteral(bytes, at: position, record), FirstMatchTokenPatterns.isAtEndOfWord(bytes, end) else { return .none }
            return .matched(end: end)
        case .name:
            guard record.firstClass.contains(bytes[position]) else { return .none }
            var end = position + 1
            while end < bytes.count, record.restClass.contains(bytes[end]) { end += 1 }
            return .matched(end: end)
        case .quoted: return Self.quoted(bytes, at: position)
        case .percentComment:
            let start = FirstMatchTokenPatterns.endOfBlanks(bytes, from: position)
            guard FirstMatchTokenPatterns.starts(bytes, at: start, with: FirstMatchTokenPatterns.percentSigns) else { return .none }
            return .matched(end: FirstMatchTokenPatterns.endOfLine(bytes, from: start))
        case .directive: return Self.directive(&text, at: position)
        case .frontMatterFence: return Self.frontMatterFence(&text, at: position)
        case .blockComment:
            guard startsWithLiteral(bytes, at: position, record) else { return .none }
            let closing = closings[record.otherIndex]
            guard let end = text.firstOccurrence(of: closing, from: position + record.literalCount) else { return .noneFurtherOn }
            return .matched(end: end + closing.count)
        case .lineComment:
            return startsWithLiteral(bytes, at: position, record) ? .matched(end: FirstMatchTokenPatterns.endOfLine(bytes, from: position)) : .none
        case .whitespace:
            if record.flag { return .matched(end: JavaScriptWhitespace.endOfRun(in: bytes, from: position)) }
            var end = position
            while end < bytes.count, MermaidByte.isWhitespace(bytes[end]) { end += 1 }
            return .matched(end: end)
        case .lineStatement: return lineStatement(bytes, at: position, record)
        case .accessibilityTitle: return Self.accessibilityTitle(bytes, at: position, leadingBlanks: record.flag)
        case .custom: return customs[record.otherIndex](&text, position)
        }
    }

    @inline(__always)
    private func startsWithLiteral(_ bytes: [UInt8], at position: Int, _ record: Record) -> Bool {
        guard position + record.literalCount <= bytes.count else { return false }
        for offset in 0..<record.literalCount where bytes[position + offset] != literals[record.literalStart + offset] { return false }
        return true
    }

    private func lineStatement(_ bytes: [UInt8], at position: Int, _ record: Record) -> FirstMatchTokenMatch {
        let start = record.flag ? FirstMatchTokenPatterns.endOfBlanks(bytes, from: position) : position
        guard startsWithLiteral(bytes, at: start, record) else { return .none }
        let afterKeyword = start + record.literalCount
        if afterKeyword < bytes.count, MermaidByte.isSpace(bytes[afterKeyword]) {
            return .matched(end: FirstMatchTokenPatterns.endBeforeComment(bytes, from: afterKeyword))
        }
        if afterKeyword < bytes.count, record.restClass.contains(bytes[afterKeyword]) { return .none }
        return .matched(end: afterKeyword)
    }

    private static func quoted(_ bytes: [UInt8], at position: Int) -> FirstMatchTokenMatch {
        let quote = bytes[position]
        guard quote == MermaidByte.quotationMark || quote == FirstMatchTokenPatterns.apostrophe else { return .none }
        var index = position + 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote { return .matched(end: index + 1) }
            if byte == FirstMatchTokenPatterns.backslash {
                guard index + 1 < bytes.count, FirstMatchTokenPatterns.lineTerminatorLength(bytes, index + 1) == 0 else { return .none }
                index += 1
            }
            index += 1
        }
        return .none
    }

    private static func directive(_ text: inout FirstMatchTokenizerText, at position: Int) -> FirstMatchTokenMatch {
        let start = FirstMatchTokenPatterns.endOfBlanks(text.bytes, from: position)
        let opening = FirstMatchTokenPatterns.directiveOpening
        guard FirstMatchTokenPatterns.starts(text.bytes, at: start, with: opening) else { return .none }
        let closingFence = FirstMatchTokenPatterns.directiveClosing
        var from = start + opening.count
        while let closing = text.firstOccurrence(of: closingFence, from: from) {
            if let end = FirstMatchTokenPatterns.endAfterClosingFence(text.bytes, closing + closingFence.count) { return .matched(end: end) }
            from = closing + 1
        }
        return .noneFurtherOn
    }

    private static func frontMatterFence(_ text: inout FirstMatchTokenizerText, at position: Int) -> FirstMatchTokenMatch {
        let bytes = text.bytes
        let fence = FirstMatchTokenPatterns.fence
        guard FirstMatchTokenPatterns.starts(bytes, at: position, with: fence) else { return .none }
        var index = FirstMatchTokenPatterns.endOfBlanks(bytes, from: position + fence.count)
        if index < bytes.count, bytes[index] == MermaidByte.carriageReturn { index += 1 }
        guard index < bytes.count, bytes[index] == MermaidByte.newline else { return .none }
        var lineStart = index + 1
        while true {
            if FirstMatchTokenPatterns.starts(bytes, at: lineStart, with: fence),
               let end = FirstMatchTokenPatterns.endAfterClosingFence(bytes, lineStart + fence.count) { return .matched(end: end) }
            guard let lineBreak = text.firstOccurrence(of: newlineNeedle, from: lineStart) else { return .noneFurtherOn }
            lineStart = lineBreak + 1
        }
    }

    private static let newlineNeedle = [MermaidByte.newline]

    private static func accessibilityTitle(_ bytes: [UInt8], at position: Int, leadingBlanks: Bool) -> FirstMatchTokenMatch {
        let start = leadingBlanks ? FirstMatchTokenPatterns.endOfBlanks(bytes, from: position) : position
        let keyword = FirstMatchTokenPatterns.accessibilityTitleKeyword
        guard FirstMatchTokenPatterns.starts(bytes, at: start, with: keyword) else { return .none }
        let colon = FirstMatchTokenPatterns.endOfBlanks(bytes, from: start + keyword.count)
        guard colon < bytes.count, bytes[colon] == MermaidByte.colon else { return .none }
        return .matched(end: FirstMatchTokenPatterns.endBeforeComment(bytes, from: colon + 1))
    }
}
