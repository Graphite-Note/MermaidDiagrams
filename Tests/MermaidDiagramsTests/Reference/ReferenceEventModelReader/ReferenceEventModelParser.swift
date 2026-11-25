/**
 * File: ReferenceEventModelParser.swift
 * -------------------------------------
 * Layer: Tests
 * Description: 0.7.0's event model parser, frozen as main dad6fb8 read it over the tokens of EventModelLexer, which
 *              the event model reader is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

/// Reads an event model's statements over the tokens of `EventModelLexer`, in any order and anywhere on their lines
/// (line breaks are whitespace), and hands them to `ReferenceEventModelDiagramBuilder`, which builds the diagram as Mermaid's
/// database does.
struct ReferenceEventModelParser {
    typealias Reader = FirstMatchTokenReader<EventModelTokenKind>

    private var reader: Reader
    private var statements = ReferenceEventModelStatements()
    private let limits: MermaidDiagramLimits

    private init(reader: Reader, limits: MermaidDiagramLimits) {
        self.reader = reader
        self.limits = limits
    }

    /// Reads the event model whose keyword, `keyword` as written, ends at the cursor: Mermaid detects any text that
    /// starts with `eventmodeling` as an event model, and its grammar then takes the keyword alone.
    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> EventModelDiagram {
        let bytes = cursor.bytes
        guard keyword == "eventmodeling", FirstMatchTokenPatterns.isAtEndOfWord(bytes, cursor.position) else {
            throw .invalidSyntax(line: cursor.line, problem: .eventModeling(.expectedKeyword))
        }
        let tokens: [FirstMatchToken<EventModelTokenKind>]
        do {
            tokens = try EventModelLexer.tokenizer.tokens(of: bytes, from: cursor.position)
        } catch {
            throw .invalidSyntax(line: Reader.line(of: error.position, in: bytes), problem: .unexpectedText(Reader.excerpt(at: error.position, in: bytes)))
        }
        var parser = ReferenceEventModelParser(reader: Reader(bytes: bytes, tokens: tokens, start: cursor.position), limits: limits)
        try parser.readStatements()
        return try ReferenceEventModelDiagramBuilder.diagram(of: parser.statements, bytes: bytes, limits: limits)
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while let kind = reader.kind {
            switch kind {
            case .accessibilityDescription: statements.accessibilityDescription = reader.take()
            case .accessibilityTitle: statements.accessibilityTitle = reader.take()
            case .title: statements.title = reader.take()
            case .word("entity"):
                _ = reader.take()
                statements.entities.append(try qualifiedName())
            case .word("tf"), .word("timeframe"), .word("rf"), .word("resetframe"): try readFrame()
            case .word("data"): try readDataBlock()
            case .word("note"): try readNote()
            case .word("gwt"): try readSpecification()
            default: throw reader.failure(.eventModeling(.expectedStatement))
            }
        }
    }

    private mutating func readFrame() throws(MermaidDiagramReadError) {
        try checkNodeCount()
        let position = reader.position
        let isReset = reader.kind == .word("rf") || reader.kind == .word("resetframe")
        _ = reader.take()
        let identifier = try reader.expect(.frameNumber, else: .eventModeling(.expectedFrameNumber))
        let kindKeyword = try entityKind()
        var frame = ReferenceEventModelWrittenFrame(identifier: identifier, kindKeyword: kindKeyword, entity: try qualifiedName(), isReset: isReset,
                                           position: position)
        while reader.accept(.arrow) {
            frame.sourceIdentifiers.append(try reader.expect(.frameNumber, else: .eventModeling(.expectedFrameNumber)))
        }
        if reader.accept(.openingReference) {
            frame.dataReference = try reader.expect(.name, else: .eventModeling(.expectedName))
            _ = try reader.expect(.closingReference, else: .eventModeling(.expectedClosingReference))
        }
        if reader.kind == .graveAccent || reader.kind == .inlineData {
            frame.dataType = try dataType()
            frame.inlineData = try reader.expect(.inlineData, else: .eventModeling(.expectedInlineData))
        }
        statements.frames.append(frame)
    }

    private mutating func readDataBlock() throws(MermaidDiagramReadError) {
        _ = reader.take()
        let name = try reader.expect(.name, else: .eventModeling(.expectedName))
        let type = try dataType()
        let block = try reader.expect(.dataBlock, else: .eventModeling(.expectedDataBlock))
        statements.dataBlocks.append((name, type, block))
    }

    private mutating func readNote() throws(MermaidDiagramReadError) {
        try checkNodeCount()
        _ = reader.take()
        let frame = try reader.expect(.frameNumber, else: .eventModeling(.expectedFrameNumber))
        let type = try dataType()
        let block = try reader.expect(.dataBlock, else: .eventModeling(.expectedDataBlock))
        statements.notes.append(EventModelNote(frameIdentifier: frame, text: ReferenceEventModelDiagramBuilder.blockText(block), dataType: type))
    }

    private mutating func readSpecification() throws(MermaidDiagramReadError) {
        try checkNodeCount()
        _ = reader.take()
        let frame = try reader.expect(.frameNumber, else: .eventModeling(.expectedFrameNumber))
        _ = try reader.expect(.word("given"), else: .eventModeling(.expectedGiven))
        let given = try specificationStatements()
        let when = reader.accept(.word("when")) ? try specificationStatements() : []
        _ = try reader.expect(.word("then"), else: .eventModeling(.expectedThen))
        statements.specifications.append(EventModelSpecification(frameIdentifier: frame, given: given, when: when, then: try specificationStatements()))
    }

    /// One or more entities, each a kind and a name.
    private mutating func specificationStatements() throws(MermaidDiagramReadError) -> [String] {
        var names: [String] = []
        repeat {
            _ = try entityKind()
            names.append(try reader.expect(.name, else: .eventModeling(.expectedName)))
        } while reader.kind.map(Self.isEntityKind) == true
        return names
    }

    private mutating func entityKind() throws(MermaidDiagramReadError) -> String {
        guard let kind = reader.kind, Self.isEntityKind(kind) else { throw reader.failure(.eventModeling(.expectedEntityKind)) }
        return reader.take()
    }

    /// A name, then `.` and a name any number of times.
    private mutating func qualifiedName() throws(MermaidDiagramReadError) -> String {
        var name = try reader.expect(.name, else: .eventModeling(.expectedName))
        while reader.accept(.period) { name += "." + (try reader.expect(.name, else: .eventModeling(.expectedName))) }
        return name
    }

    /// A type between backticks, or nil when no backtick is there.
    private mutating func dataType() throws(MermaidDiagramReadError) -> String? {
        guard reader.accept(.graveAccent) else { return nil }
        guard case .word(let word) = reader.kind, Self.dataTypes.contains(word) else { throw reader.failure(.eventModeling(.expectedDataType)) }
        _ = reader.take()
        _ = try reader.expect(.graveAccent, else: .eventModeling(.expectedDataType))
        return word
    }

    /// Frames, notes and specifications are drawn, each as a box: together they count as the diagram's nodes.
    private func checkNodeCount() throws(MermaidDiagramReadError) {
        let count = statements.frames.count + statements.notes.count + statements.specifications.count
        guard count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    private static func isEntityKind(_ kind: EventModelTokenKind) -> Bool {
        guard case .word(let word) = kind else { return false }
        return entityKinds.contains(word)
    }

    private static let entityKinds: Set<String> = ["rmo", "readmodel", "ui", "cmd", "command", "evt", "event", "pcr", "processor"]
    private static let dataTypes: Set<String> = ["json", "jsobj", "figma", "salt", "uri", "md", "html", "text"]
}

/// An event model's statements as they are written, before the diagram is built from them.
struct ReferenceEventModelStatements {
    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var entities: [String] = []
    var frames: [ReferenceEventModelWrittenFrame] = []
    var dataBlocks: [(name: String, type: String?, block: String)] = []
    var notes: [EventModelNote] = []
    var specifications: [EventModelSpecification] = []
}

/// A frame as written: `tf 02 evt Cart.ItemAdded ->> 01 [[Data]] `json`{ … }`.
struct ReferenceEventModelWrittenFrame {
    let identifier: String
    let kindKeyword: String
    let entity: String
    let isReset: Bool
    /// Where the frame starts in the text, for the line of an error about it.
    let position: Int
    var sourceIdentifiers: [String] = []
    var dataReference: String?
    var dataType: String?
    var inlineData: String?
}
