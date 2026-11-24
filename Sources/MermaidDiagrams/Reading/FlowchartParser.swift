/**
 * File: FlowchartParser.swift
 * ---------------------------
 * Layer: Core
 * Description: Reads a flowchart's statements after its keyword into the flat model, on a pointer to the text's bytes:
 *              names interned by their bytes, texts kept as ranges, no String made for a name or a one-line text.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 24/11/2026
 */

/// Reads a flowchart's statements after its `flowchart` or `graph` keyword: the direction, then chains of nodes and
/// links (`A & B --> C -->|yes| D`), groups (`subgraph … end`), accessibility text, and the statements that style the
/// diagram (`FlowchartStyleSyntax`); a `click` is counted and left. Statements end at a line break or a semicolon; `%%`
/// starts a comment. Errors name the line of the position they are found at, as `MermaidTextCursor` counts lines.
struct FlowchartParser {
    let bytes: FlowchartBytes
    var position: Int
    let limits: MermaidDiagramLimits
    /// The thread's working lists, moved here for the reading and back after it.
    var lists = FlowchartReadingLists()
    var parts = FlowchartModelParts()
    var direction = FlowchartDirection.topToBottom
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var unappliedStatementCount = 0
    /// What the statements that style the diagram set, made when the first one is read.
    var styling: FlowchartStyling?
    var openedGroupCount: Int32 = 0
    var endedGroupCount = 0

    init(bytes: FlowchartBytes, position: Int, limits: MermaidDiagramLimits) {
        self.bytes = bytes
        self.position = position
        self.limits = limits
        let room = min(max(bytes.count / 24, 4), 1_024)
        parts.nodes.reserveCapacity(room)
    }

    /// Reads the flowchart whose keyword the front end found.
    static func parse(_ frontEnd: MermaidFrontEndResult, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> FlowchartReading {
        let read: Result<FlowchartReading, MermaidDiagramReadError> = frontEnd.text.withBytes { buffer in
            FlowchartReadingScratch.withLists { lists in
                var lookAhead = FlowchartLookAheadLists()
                swap(&lookAhead, &lists.lookAhead)
                defer { swap(&lookAhead, &lists.lookAhead) }
                lookAhead.build(over: buffer)
                return lookAhead.withIndex { index in
                    guard let base = buffer.baseAddress else { return .failure(.noDiagram) }
                    var parser = FlowchartParser(bytes: FlowchartBytes(base: base, count: buffer.count, lookAhead: index),
                                                 position: frontEnd.keyword.upperBound, limits: limits)
                    swap(&parser.lists, &lists)
                    defer { swap(&parser.lists, &lists) }
                    return Result { () throws(MermaidDiagramReadError) in try parser.read(text: frontEnd.text) }
                }
            }
        }
        return try read.get()
    }

    private mutating func read(text: MermaidSourceText) throws(MermaidDiagramReadError) -> FlowchartReading {
        try readDirection()
        try readStatements()
        nestGroups()
        applyStyles()
        return FlowchartReading(model: parts.model(text: text), direction: direction, accessibilityTitle: accessibilityTitle,
                                accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }

    private mutating func readDirection() throws(MermaidDiagramReadError) {
        skipSpaces()
        guard position < bytes.count, case let byte = bytes.base[position], !MermaidByte.endsStatement(byte), !isAtComment else { return }
        let start = position
        if MermaidByte.isLetter(byte) {
            while MermaidByte.isLetter(bytes[position]) { position += 1 }
        } else {
            position += 1
        }
        guard let written = Self.direction(in: bytes, from: start, to: position) else {
            throw .invalidSyntax(line: bytes.line(at: position), problem: .unknownDirection(bytes.string(from: start, to: position)))
        }
        direction = written
        try expectStatementEnd()
    }

    /// `FlowchartDirection(keyword:)` on bytes: `TB`, `TD`, `V`, `BT`, `^`, `LR`, `>`, `RL`, `<` in any case.
    private static func direction(in bytes: FlowchartBytes, from start: Int, to end: Int) -> FlowchartDirection? {
        let first = MermaidByte.lowercased(bytes[start])
        switch end - start {
        case 1:
            switch first {
            case UInt8(ascii: "v"): return .topToBottom
            case UInt8(ascii: "^"): return .bottomToTop
            case MermaidByte.greaterThan: return .leftToRight
            case MermaidByte.lessThan: return .rightToLeft
            default: return nil
            }
        case 2:
            switch (first, MermaidByte.lowercased(bytes[start + 1])) {
            case (UInt8(ascii: "t"), UInt8(ascii: "b")), (UInt8(ascii: "t"), UInt8(ascii: "d")): return .topToBottom
            case (UInt8(ascii: "b"), UInt8(ascii: "t")): return .bottomToTop
            case (UInt8(ascii: "l"), UInt8(ascii: "r")): return .leftToRight
            case (UInt8(ascii: "r"), UInt8(ascii: "l")): return .rightToLeft
            default: return nil
            }
        default: return nil
        }
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            skipWhitespace()
            while position < bytes.count, bytes.base[position] == MermaidByte.semicolon {
                position += 1
                skipWhitespace()
            }
            if position >= bytes.count { break }
            if isAtComment {
                skipToEndOfLine()
                continue
            }
            if try readKeywordStatement() { continue }
            try readChain()
            try expectStatementEnd()
        }
        if let group = lists.openGroups.last {
            let identifier = group.writtenName >= 0 ? lists.names.string(Int(group.writtenName), in: bytes) : "subGraph\(endedGroupCount)"
            throw .invalidSyntax(line: bytes.line(at: position), problem: .unclosedSubgraph(identifier: identifier))
        }
    }

    /// `A & B --> C -->|text| D`: node groups joined by links, each link making an edge from every node before it to
    /// every node after it.
    private mutating func readChain() throws(MermaidDiagramReadError) {
        lists.chainNodes.removeAll(keepingCapacity: true)
        guard try readNodeGroup() else { return }
        var previousStart = 0
        while true {
            skipSpaces()
            guard let link = try readLink() else { return }
            if link.identifier.end > link.identifier.start {
                let name = lists.names.intern(link.identifier, in: bytes)
                lists.names.names[name].isEdgeIdentifier = true
            }
            skipSpaces()
            let nextStart = lists.chainNodes.count
            guard try readNodeGroup() else { throw .invalidSyntax(line: bytes.line(at: position), problem: .expectedNode) }
            try addEdges(from: previousStart..<nextStart, to: nextStart..<lists.chainNodes.count, link: link)
            previousStart = nextStart
        }
    }

    /// One edge from each source to each target, as `A & B --> C & D` asks.
    private mutating func addEdges(from sources: Range<Int>, to targets: Range<Int>, link: FlowchartLink) throws(MermaidDiagramReadError) {
        let product = sources.count * targets.count
        guard parts.edges.count + product <= limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        if parts.edges.capacity == 0 { parts.edges.reserveCapacity(max(product, parts.nodes.capacity)) }
        for source in sources {
            for target in targets {
                parts.edges.append(FlowchartEdgeRecord(sourceIndex: lists.chainNodes[source], targetIndex: lists.chainNodes[target],
                                                       minimumRankSpan: Int32(link.minimumRankSpan), stroke: link.stroke,
                                                       sourceArrowhead: link.sourceArrowhead, targetArrowhead: link.targetArrowhead, label: link.label))
            }
        }
    }

    /// `A & B & C`, appended to the chain's nodes; false for an edge's attributes (`e1@{ … }`), which name no node. As
    /// in Pele's `node`, the `&` has spaces on both sides: written against a node it is part of the identifier, and
    /// after a shape (`A[x]&B`) or before a node (`A &B`) the statement is refused.
    private mutating func readNodeGroup() throws(MermaidDiagramReadError) -> Bool {
        let start = lists.chainNodes.count
        while true {
            guard let index = try readNode() else { return lists.chainNodes.count > start }
            lists.chainNodes.append(index)
            var lookahead = position
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
            guard lookahead > position, bytes[lookahead] == MermaidByte.ampersand, lookahead < bytes.count else { return true }
            lookahead += 1
            guard MermaidByte.isSpace(bytes[lookahead]) else {
                throw .invalidSyntax(line: bytes.line(at: lookahead), problem: .unexpectedText(bytes.excerpt(at: lookahead)))
            }
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
            position = lookahead
        }
    }

    /// A node: its identifier, then its shape and text or its attributes, then any `:::class`, then any attributes.
    private mutating func readNode() throws(MermaidDiagramReadError) -> Int32? {
        let start = position
        let end = FlowchartIdentifierSyntax.endOfIdentifier(in: bytes, from: start)
        guard end > start else {
            throw .invalidSyntax(line: bytes.line(at: start), problem: start >= bytes.count ? .expectedNode : .unexpectedText(bytes.excerpt(at: start)))
        }
        position = end
        let range = MermaidTextRange(start: start, end: end)
        let name = lists.names.intern(range, in: bytes)
        if isAtAttributes, lists.names.names[name].isEdgeIdentifier {
            _ = try readAttributes()
            unappliedStatementCount += 1
            return nil
        }
        let index = try nodeIndex(name: name, range: range)
        if isAtAttributes {
            try define(nodeAt: index, name: name, as: readAttributes())
        } else if let definition = try readShape() {
            try define(nodeAt: index, name: name, as: definition)
        }
        while bytes[position] == MermaidByte.colon, bytes[position + 1] == MermaidByte.colon, bytes[position + 2] == MermaidByte.colon {
            position += 3
            let classEnd = FlowchartIdentifierSyntax.endOfIdentifier(in: bytes, from: position)
            if classEnd > position {
                assignClass(toNodeNamed: name, className: bytes.string(from: position, to: classEnd))
                position = classEnd
            } else {
                unappliedStatementCount += 1
            }
        }
        // Attributes may also follow a shape in brackets and its classes (`C[Hello]@{ shape: circle }`), as Pele reads them.
        if isAtAttributes { try define(nodeAt: index, name: name, as: readAttributes()) }
        return index
    }

    /// Whether `@{` follows, which opens a node's (or an edge's) attributes.
    var isAtAttributes: Bool {
        bytes[position] == MermaidByte.atSign && bytes[position + 1] == MermaidByte.openingBrace
    }

    /// Whether `%%` follows, which starts a comment.
    var isAtComment: Bool {
        bytes[position] == MermaidByte.percent && bytes[position + 1] == MermaidByte.percent
    }
}

/// What a flowchart's reading gives: its model and what the statements say of the whole diagram.
struct FlowchartReading {
    let model: FlowchartModel
    let direction: FlowchartDirection
    let accessibilityTitle: String?
    let accessibilityDescription: String?
    let unappliedStatementCount: Int
}
