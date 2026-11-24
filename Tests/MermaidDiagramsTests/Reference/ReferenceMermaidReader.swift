/**
 * File: ReferenceMermaidReader.swift
 * ----------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's front end (MermaidDiagramReader.read and preprocessed), frozen as the reference:
 *              the text preprocessed as Pele does, its front matter's title, comments, the type's keyword, then a
 *              flowchart or a swimlane read by the frozen flowchart reader; any other type is named and not read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// Reads Mermaid text as 0.7.0's MermaidDiagramReader read it, up to the type's keyword, then a flowchart or a swimlane.
enum ReferenceMermaidReader {
    /// What the reference reads: a flowchart, a swimlane (a flowchart whose groups are lanes), or another type, named.
    enum Reading: Equatable {
        case flowchart(ReferenceFlowchartDiagram)
        case swimlane(ReferenceFlowchartDiagram)
        case otherType(keyword: String)

        var flowchart: ReferenceFlowchartDiagram? {
            switch self {
            case .flowchart(let diagram), .swimlane(let diagram): diagram
            case .otherType: nil
            }
        }
    }

    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> Reading {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        var (title, cursor) = try preprocessed(source)
        skipCommentsAndBlankLines(&cursor)
        guard let keyword = readTypeKeyword(&cursor) else {
            throw cursor.isAtEnd ? .noDiagram : .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        switch keyword {
        case "flowchart", "graph", "flowchart-elk": return .flowchart(titled(try ReferenceFlowchartParser.parse(cursor, limits: limits), title))
        case "swimlane-beta": return .swimlane(titled(try ReferenceFlowchartParser.parse(cursor, limits: limits), title))
        default: return .otherType(keyword: keyword)
        }
    }

    private static func titled(_ diagram: ReferenceFlowchartDiagram, _ frontMatterTitle: String?) -> ReferenceFlowchartDiagram {
        var titledDiagram = diagram
        if titledDiagram.title == nil { titledDiagram.title = frontMatterTitle }
        return titledDiagram
    }

    /// The front matter's title, and a cursor after the front matter on the text preprocessed as Pele does.
    static func preprocessed(_ source: String) throws(MermaidDiagramReadError) -> (title: String?, cursor: ReferenceMermaidTextCursor) {
        let utf8 = source.utf8
        let written = utf8.starts(with: byteOrderMark) ? Array(utf8.dropFirst(byteOrderMark.count)) : Array(utf8)
        let found = ReferenceMermaidPreprocessing.bytesFound(in: written)
        var sourceBytes = written
        if found.contains(.carriageReturn) { sourceBytes = ReferenceMermaidPreprocessing.normalizedLineBreaks(sourceBytes) }
        if found.contains([.lessThan, .greaterThan]) { sourceBytes = ReferenceMermaidPreprocessing.singleQuotingTagAttributes(sourceBytes) }
        let readFrontMatter = MermaidReadFrontMatter(in: sourceBytes)
        let (title, start) = try frontMatterTitleAndEnd(readFrontMatter, in: sourceBytes)
        var bytes = sourceBytes
        if found.contains(.percent) { bytes = ReferenceMermaidPreprocessing.removingDirectives(from: bytes, from: start) }
        if found.contains(.hash) { bytes = ReferenceMermaidPreprocessing.droppingColorSemicolons(bytes, from: start) }
        var cursor = ReferenceMermaidTextCursor(bytes: bytes, sourceBytes: sourceBytes, readFrontMatter: readFrontMatter)
        cursor.advance(by: start)
        return (title, cursor)
    }

    private static func frontMatterTitleAndEnd(_ read: MermaidReadFrontMatter,
                                               in bytes: [UInt8]) throws(MermaidDiagramReadError) -> (title: String?, end: Int) {
        guard let frontMatter = read.frontMatter else {
            var opening = ReferenceMermaidTextCursor(bytes: bytes)
            opening.skipSpaces()
            if opening.hasPrefix(fence), opening.readRestOfLine() == "---" { throw .invalidSyntax(line: 1, problem: .unclosedFrontMatter) }
            return (nil, 0)
        }
        guard let value = read.value else {
            let firstLine = frontMatter.body.split(separator: "\n").first { line in !line.allSatisfy(\.isWhitespace) } ?? ""
            throw .invalidSyntax(line: 2, problem: .unexpectedText(String(firstLine.trimmingCharacters(in: .whitespaces).prefix(24))))
        }
        return (MermaidFrontMatter.title(in: value), frontMatter.end)
    }

    /// Skips blank space and comments, each to the end of its line, before the diagram's keyword.
    static func skipCommentsAndBlankLines(_ cursor: inout ReferenceMermaidTextCursor) {
        while true {
            cursor.skipWhitespace()
            guard cursor.hasPrefix(commentStart) else { return }
            cursor.skipToEndOfLine()
        }
    }

    /// The keyword that names the type: a letter, then letters, digits and `-`.
    static func readTypeKeyword(_ cursor: inout ReferenceMermaidTextCursor) -> String? {
        guard let first = cursor.peek(), MermaidByte.isLetter(first) else { return nil }
        let start = cursor.position
        while let byte = cursor.peek(), MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.hyphen { cursor.advance() }
        return cursor.position > start ? cursor.text(from: start, to: cursor.position) : nil
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let commentStart = Array("%%".utf8)
    private static let fence = Array("---".utf8)
}
