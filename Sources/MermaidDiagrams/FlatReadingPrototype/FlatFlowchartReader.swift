/**
 * File: FlatFlowchartReader.swift
 * -------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: Reads a flowchart's statements after its keyword into the flat model, as FlowchartParser and
 *              FlowchartDiagramBuilder read them, on a pointer to the bytes: names interned by their bytes, texts kept
 *              as ranges, no String made for a name or a one-line text. Statements that style the diagram, an
 *              unclosed construct and any error bail out to the present reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

struct FlatFlowchartReader {
    var bytes: FlatBytes
    var position: Int
    let limits: MermaidDiagramLimits
    /// The scratch's lists, moved here for the reading and back after it.
    var slots: [Int32]
    var names: [FlatNameEntry]
    var sideBytes: [UInt8]
    var groupBuffer: [Int32]
    var openSubgraphs: [FlatOpenSubgraph]
    var openMembers: [Int32]
    var endedSubgraphs: [FlatEndedSubgraph]
    var endedMembers: [Int32] = []
    var styling: FlatStyling? = nil
    var writtenAssetAttributes = FlowchartNodeAssetAttributes()
    /// The text's line count, at most 1,024: the room the edges' list is given when the first edge is made.
    var lineCount = 0
    var document: FlatFlowchartDocument
    var openedSubgraphCount: Int32 = 0
    var endedSubgraphCount = 0

    // MARK: Statements

    mutating func readDirection() throws(FlatReadingBailOut) {
        skipSpaces()
        let byte = bytes[position]
        guard position < bytes.count, !MermaidByte.endsStatement(byte), !(byte == MermaidByte.percent && bytes[position + 1] == MermaidByte.percent) else { return }
        let start = position
        if MermaidByte.isLetter(byte) {
            while MermaidByte.isLetter(bytes[position]) { position += 1 }
        } else {
            position += 1
        }
        guard let direction = Self.direction(in: bytes, from: start, to: position) else { throw FlatReadingBailOut() }
        document.direction = direction
        try expectStatementEnd()
    }

    /// FlowchartDirection(keyword:) on bytes: `TB`, `TD`, `V`, `BT`, `^`, `LR`, `>`, `RL`, `<` in any case.
    private static func direction(in bytes: FlatBytes, from start: Int, to end: Int) -> FlowchartDirection? {
        let first = MermaidByte.lowercased(bytes[start])
        switch end - start {
        case 1:
            switch first {
            case 0x76: return .topToBottom
            case UInt8(ascii: "^"): return .bottomToTop
            case MermaidByte.greaterThan: return .leftToRight
            case MermaidByte.lessThan: return .rightToLeft
            default: return nil
            }
        case 2:
            switch (first, MermaidByte.lowercased(bytes[start + 1])) {
            case (0x74, 0x62), (0x74, 0x64): return .topToBottom
            case (0x62, 0x74): return .bottomToTop
            case (0x6C, 0x72): return .leftToRight
            case (0x72, 0x6C): return .rightToLeft
            default: return nil
            }
        default: return nil
        }
    }

    mutating func readStatements() throws(FlatReadingBailOut) {
        while true {
            skipWhitespace()
            while bytes[position] == MermaidByte.semicolon, position < bytes.count {
                position += 1
                skipWhitespace()
            }
            if position >= bytes.count { break }
            if bytes[position] == MermaidByte.percent, bytes[position + 1] == MermaidByte.percent {
                skipToEndOfLine()
                continue
            }
            if try readKeywordStatement() { continue }
            try readChain()
            try expectStatementEnd()
        }
        guard openSubgraphs.isEmpty else { throw FlatReadingBailOut() }
    }

    private enum Keyword {
        case subgraph, end, direction, styling(StyleKeyword), click, accessibilityTitle, accessibilityDescription
    }

    /// The keyword the letters from `start` to `end` spell, or nil.
    private func keyword(from start: Int, to end: Int) -> Keyword? {
        switch end - start {
        case 3: return bytes.hasText("end", at: start) ? .end : nil
        case 5:
            if bytes.hasText("class", at: start) { return .styling(.classAssignment) }
            if bytes.hasText("style", at: start) { return .styling(.style) }
            return bytes.hasText("click", at: start) ? .click : nil
        case 8:
            if bytes.hasText("subgraph", at: start) { return .subgraph }
            if bytes.hasText("classDef", at: start) { return .styling(.classDefinition) }
            if bytes.hasText("accTitle", at: start) { return .accessibilityTitle }
            return bytes.hasText("accDescr", at: start) ? .accessibilityDescription : nil
        case 9:
            if bytes.hasText("direction", at: start) { return .direction }
            return bytes.hasText("linkStyle", at: start) ? .styling(.linkStyle) : nil
        default: return nil
        }
    }

    private mutating func readKeywordStatement() throws(FlatReadingBailOut) -> Bool {
        var wordEnd = position
        while MermaidByte.isLetter(bytes[wordEnd]) { wordEnd += 1 }
        guard wordEnd > position, let keyword = keyword(from: position, to: wordEnd) else { return false }
        let next = bytes[wordEnd]
        if wordEnd < bytes.count, !MermaidByte.isSpace(next), !MermaidByte.endsStatement(next), next != MermaidByte.colon,
           next != MermaidByte.openingBrace { return false }
        position = wordEnd
        switch keyword {
        case .subgraph: readSubgraphOpening()
        case .end:
            guard closeSubgraph() else { throw FlatReadingBailOut() }
            try expectStatementEnd()
        case .accessibilityTitle: document.rare.accessibilityTitle = readAccessibilityLine()
        case .accessibilityDescription: document.rare.accessibilityDescription = try readAccessibilityDescription()
        case .direction: readDirectionStatement()
        case .styling(let styleKeyword): try readStyleStatement(styleKeyword)
        case .click:
            skipStatement()
            document.unappliedStatementCount += 1
        }
        return true
    }

    private mutating func readChain() throws(FlatReadingBailOut) {
        groupBuffer.removeAll(keepingCapacity: true)
        guard try readNodeGroup() else { return }
        var previousStart = 0
        while true {
            skipSpaces()
            guard let link = try readLink() else { return }
            if link.identifierEnd > link.identifierStart {
                let name = intern(FlatTextRange(start: Int32(link.identifierStart), end: Int32(link.identifierEnd)))
                names[name].isEdgeIdentifier = true
            }
            skipSpaces()
            let nextStart = groupBuffer.count
            guard try readNodeGroup() else { throw FlatReadingBailOut() }
            let product = (nextStart - previousStart) * (groupBuffer.count - nextStart)
            guard document.edges.count + product <= limits.maximumEdgeCount else { throw FlatReadingBailOut() }
            if document.edges.capacity == 0 { document.edges.reserveCapacity(max(product, lineCount)) }
            for sourcePlace in previousStart..<nextStart {
                for targetPlace in nextStart..<groupBuffer.count {
                    document.edges.append(FlatFlowchartEdge(sourceIndex: groupBuffer[sourcePlace], targetIndex: groupBuffer[targetPlace],
                                                            minimumRankSpan: Int32(link.minimumRankSpan), stroke: link.stroke,
                                                            sourceArrowhead: link.sourceArrowhead, targetArrowhead: link.targetArrowhead, label: link.label))
                }
            }
            previousStart = nextStart
        }
    }

    /// `A & B & C`, appended to `groupBuffer`; false for an edge's attributes, which name no node.
    private mutating func readNodeGroup() throws(FlatReadingBailOut) -> Bool {
        let start = groupBuffer.count
        while true {
            guard let index = try readNode() else { return groupBuffer.count > start }
            groupBuffer.append(index)
            var lookahead = position
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
            guard lookahead > position, bytes[lookahead] == MermaidByte.ampersand else { return true }
            lookahead += 1
            guard MermaidByte.isSpace(bytes[lookahead]) else { throw FlatReadingBailOut() }
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
            position = lookahead
        }
    }

    private mutating func readNode() throws(FlatReadingBailOut) -> Int32? {
        let start = position
        let end = bytes.endOfIdentifier(from: start)
        guard end > start else { throw FlatReadingBailOut() }
        position = end
        let range = FlatTextRange(start: Int32(start), end: Int32(end))
        let name = intern(range)
        if isAtAttributes, names[name].isEdgeIdentifier {
            _ = try readAttributes()
            document.unappliedStatementCount += 1
            return nil
        }
        let index = try nodeIndex(name: name, range: range)
        if isAtAttributes {
            try define(nodeAt: index, name: name, as: try readAttributes())
        } else if let definition = try readShape() {
            try define(nodeAt: index, name: name, as: definition)
        }
        while bytes[position] == MermaidByte.colon, bytes[position + 1] == MermaidByte.colon, bytes[position + 2] == MermaidByte.colon {
            position += 3
            let classEnd = bytes.endOfIdentifier(from: position)
            if classEnd > position {
                assignClass(nodeName: name, classRange: position..<classEnd)
                position = classEnd
            } else {
                document.unappliedStatementCount += 1
            }
        }
        if isAtAttributes { try define(nodeAt: index, name: name, as: try readAttributes()) }
        return index
    }

    private var isAtAttributes: Bool {
        bytes[position] == MermaidByte.atSign && bytes[position + 1] == MermaidByte.openingBrace
    }

    // MARK: Nodes and names

    /// The name's index, interned by its bytes (FNV-1a), the text's or the side bytes'.
    mutating func intern(_ range: FlatTextRange) -> Int {
        let hash = range.start >= 0 ? Self.hash(bytes.base + Int(range.start), count: range.length)
            : sideBytes.withUnsafeBufferPointer { side in Self.hash(side.baseAddress! + Int(~range.start), count: range.length) }
        let mask = slots.count &- 1
        var slot = Int(hash) & mask
        while true {
            let entry = slots[slot]
            if entry == 0 { break }
            let name = Int(entry &- 1)
            let candidate = names[name]
            if candidate.hash == hash, candidate.range.length == range.length, sameBytes(candidate.range, range) { return name }
            slot = (slot &+ 1) & mask
        }
        let name = names.count
        names.append(FlatNameEntry(range: range, hash: hash, slot: Int32(slot)))
        slots[slot] = Int32(name + 1)
        if names.count * 2 > slots.count { growSlots() }
        return name
    }

    @inline(__always) private static func hash(_ start: UnsafePointer<UInt8>, count: Int) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for offset in 0..<count { hash = (hash ^ UInt32(start[offset])) &* 0x0100_0193 }
        return hash
    }

    private mutating func growSlots() {
        let count = slots.count * 2
        slots = Array(repeating: 0, count: count)
        for (name, entry) in names.enumerated() {
            var slot = Int(entry.hash) & (count - 1)
            while slots[slot] != 0 { slot = (slot + 1) & (count - 1) }
            slots[slot] = Int32(name + 1)
            names[name].slot = Int32(slot)
        }
    }

    /// Whether two ranges of equal length hold the same bytes.
    @inline(__always) private func sameBytes(_ first: FlatTextRange, _ second: FlatTextRange) -> Bool {
        if first.start >= 0, second.start >= 0 { return memcmp(bytes.base + Int(first.start), bytes.base + Int(second.start), first.length) == 0 }
        return sideBytes.withUnsafeBufferPointer { side in
            let firstStart = first.start >= 0 ? bytes.base + Int(first.start) : side.baseAddress! + Int(~first.start)
            let secondStart = second.start >= 0 ? bytes.base + Int(second.start) : side.baseAddress! + Int(~second.start)
            return memcmp(firstStart, secondStart, first.length) == 0
        }
    }

    /// A name made by the reader (a group's identifier), interned from the side bytes.
    mutating func intern(_ text: String) -> Int {
        let start = sideBytes.count
        sideBytes.append(contentsOf: text.utf8)
        let length = sideBytes.count - start
        return intern(FlatTextRange(start: ~Int32(start), end: ~Int32(start) + Int32(length)))
    }

    /// FlowchartDiagramBuilder.nodeIndex(for:).
    private mutating func nodeIndex(name: Int, range: FlatTextRange) throws(FlatReadingBailOut) -> Int32 {
        var index = names[name].nodeIndex
        if index < 0 {
            guard document.nodes.count < limits.maximumNodeCount else { throw FlatReadingBailOut() }
            index = Int32(document.nodes.count)
            document.nodes.append(FlatFlowchartNode(identifier: range, label: writtenLabel(range, form: .plain), shape: .rectangle))
            names[name].nodeIndex = index
        }
        if let innermost = openSubgraphs.last { listMember(name, in: innermost) }
        return index
    }

    mutating func listMember(_ name: Int, in group: FlatOpenSubgraph) {
        guard names[name].listedByGroupSerial != group.serial else { return }
        names[name].listedByGroupSerial = group.serial
        if group.hasClosedChild, openMembers[Int(group.membersStart)...].contains(Int32(name)) { return }
        openMembers.append(Int32(name))
    }

    private mutating func define(nodeAt index: Int32, name: Int, as definition: FlatNodeDefinition) throws(FlatReadingBailOut) {
        if let shape = definition.shape { document.nodes[Int(index)].shape = shape }
        if let label = definition.label { document.nodes[Int(index)].label = label }
        if definition.asksForCollapsedView { names[name].isCollapsed = true }
        guard definition.hasAssetAttributes else { return }
        let written = writtenAssetAttributes
        var node = document.nodes[Int(index)]
        if written.icon != nil || written.image != nil, definition.hasBlankWrittenLabel,
           diagramLabel(node.label) == DiagramLabel(string(from: Int(node.identifier.start), to: Int(node.identifier.end))) {
            node.label = decoded(DiagramLabel(lines: [""]))
        }
        var attributes = node.assetIndex >= 0 ? document.rare.assetAttributes[Int(node.assetIndex)] : FlowchartNodeAssetAttributes()
        attributes.icon = written.icon ?? attributes.icon
        attributes.image = written.image ?? attributes.image
        attributes.form = written.form ?? attributes.form
        attributes.position = written.position ?? attributes.position
        attributes.width = written.width ?? attributes.width
        attributes.height = written.height ?? attributes.height
        attributes.constraint = written.constraint ?? attributes.constraint
        if node.assetIndex >= 0 {
            document.rare.assetAttributes[Int(node.assetIndex)] = attributes
        } else {
            node.assetIndex = Int32(document.rare.assetAttributes.count)
            document.rare.assetAttributes.append(attributes)
        }
        document.nodes[Int(index)] = node
    }

    // MARK: Labels

    mutating func decoded(_ label: DiagramLabel) -> FlatLabel {
        document.rare.decodedLabels.append(label)
        return FlatLabel(kind: .decoded, range: FlatTextRange(start: Int32(document.rare.decodedLabels.count - 1), end: 0))
    }

    @inline(__always) static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    /// A label of the reading as the present model has it (the document's text is set when the reading ends).
    func diagramLabel(_ label: FlatLabel) -> DiagramLabel? {
        switch label.kind {
        case .none: nil
        case .line: DiagramLabel(lines: [string(from: Int(label.range.start), to: Int(label.range.end))])
        case .writtenPlain: DiagramLabelDecoder.label(from: string(from: Int(label.range.start), to: Int(label.range.end)), form: .plain)
        case .writtenMarkdown: DiagramLabelDecoder.label(from: string(from: Int(label.range.start), to: Int(label.range.end)), form: .markdown)
        case .decoded: document.rareStorage!.decodedLabels[Int(label.range.start)]
        }
    }

    func string(from start: Int, to end: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes.buffer[start..<end]), as: UTF8.self)
    }

    // MARK: Cursor

    @inline(__always) mutating func skipSpaces() {
        while MermaidByte.isSpace(bytes[position]) { position += 1 }
    }

    @inline(__always) mutating func skipWhitespace() {
        while case let byte = bytes[position], MermaidByte.isSpace(byte) || byte == MermaidByte.newline || byte == MermaidByte.carriageReturn {
            position += 1
        }
    }

    mutating func skipToEndOfLine() {
        while position < bytes.count, bytes.base[position] != MermaidByte.newline { position += 1 }
    }

    /// The next line break, or semicolon outside quotation marks.
    mutating func skipStatement() {
        var isInsideQuotation = false
        while position < bytes.count, case let byte = bytes.base[position], byte != MermaidByte.newline {
            if byte == MermaidByte.quotationMark { isInsideQuotation.toggle() }
            if byte == MermaidByte.semicolon, !isInsideQuotation { return }
            position += 1
        }
    }

    mutating func expectStatementEnd() throws(FlatReadingBailOut) {
        skipSpaces()
        guard position < bytes.count, !MermaidByte.endsStatement(bytes[position]) else { return }
        guard bytes[position] == MermaidByte.percent, bytes[position + 1] == MermaidByte.percent else { throw FlatReadingBailOut() }
        skipToEndOfLine()
    }

    // MARK: Accessibility

    /// `accTitle: text`, to the end of the line.
    private mutating func readAccessibilityLine() -> String {
        skipSpaces()
        if bytes[position] == MermaidByte.colon { position += 1 }
        skipSpaces()
        let start = position
        skipToEndOfLine()
        var end = position
        while end > start, MermaidByte.isSpace(bytes[end - 1]) || bytes[end - 1] == MermaidByte.carriageReturn { end -= 1 }
        return DiagramLabelDecoder.decodingEntities(string(from: start, to: end))
    }

    private mutating func readAccessibilityDescription() throws(FlatReadingBailOut) -> String {
        skipSpaces()
        guard bytes[position] == MermaidByte.openingBrace else { return readAccessibilityLine() }
        position += 1
        let start = position
        while position < bytes.count, bytes.base[position] != MermaidByte.closingBrace { position += 1 }
        guard position < bytes.count else { throw FlatReadingBailOut() }
        let description = string(from: start, to: position)
        position += 1
        return DiagramLabelDecoder.label(from: description, form: .plain).lines.filter { line in !line.isEmpty }.joined(separator: " ")
    }
}
