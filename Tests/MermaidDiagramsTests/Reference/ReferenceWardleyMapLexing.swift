/**
 * File: ReferenceWardleyMapLexing.swift
 * -------------------------------------
 * Layer: Tests
 * Description: 0.7.0's Wardley map lexer, words and builder, frozen as main 2a0cc65 read them, for
 *              the frozen Wardley map reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The kinds of a Wardley map's tokens.
enum ReferenceWardleyMapTokenKind: Equatable {
    case openingBracket, comma, closingBracket, atSign, slash, openingParenthesis, closingParenthesis, minus, openingBrace, closingBrace
    /// Digits, a point and digits.
    case decimal
    /// `->`.
    case arrow
    /// `+<>`, `+>` or `+<`.
    case linkPort
    /// `-->`, `-.->`, `>`, or `+'label'` and `<>`, `<` or `>`.
    case linkArrow
    /// `;` and the rest of the line.
    case linkLabel
    /// `build`, `buy`, `outsource` or `market`.
    case sourcing
    /// A second `wardley-beta`, which no statement takes.
    case wardleyKeyword
    case size, evolution, anchor, component, label, inertia, evolve, pipeline, note, annotations, annotation, accelerator, deaccelerator
    /// A name of words separated by spaces.
    case name
    case accessibilityDescription, accessibilityTitle, title
    /// A whole number without a point after it.
    case wholeNumber
    case string
    /// Word characters and hyphens.
    case identifier
    case newline
}

/// A token: its kind and where it lies in the diagram's bytes.
struct ReferenceWardleyMapToken {
    let kind: ReferenceWardleyMapTokenKind
    let start: Int
    let end: Int
}

/// Reads a Wardley map's tokens after its `wardley-beta` keyword, every terminal of Pele's table in its order; spaces and
/// tabs, front matter, directives and `%%` comments are hidden, and any other text is an error where it starts.
enum ReferenceWardleyMapLexer {
    static func tokens(after cursor: MermaidTextCursor) throws(MermaidDiagramReadError) -> [ReferenceWardleyMapToken] {
        var terminals = PlaneMapTerminals(bytes: cursor.bytes)
        var position = cursor.position
        var tokens: [ReferenceWardleyMapToken] = []
        while position < cursor.bytes.count {
            let start = position
            guard let (kind, end) = match(at: start, terminals: &terminals) else {
                throw .invalidSyntax(line: PlaneMapByte.line(of: start, in: cursor.bytes), problem: .unexpectedText(PlaneMapByte.excerpt(at: start, in: cursor.bytes)))
            }
            position = end
            if let kind { tokens.append(ReferenceWardleyMapToken(kind: kind, start: start, end: end)) }
        }
        return tokens
    }

    /// The token at `start` and its end, nil for a hidden one; nil altogether where no terminal matches.
    private static func match(at start: Int, terminals: inout PlaneMapTerminals) -> (ReferenceWardleyMapTokenKind?, Int)? {
        guard let current = terminals.byte(start) else { return nil }
        if let kind = punctuation[current] { return (kind, start + 1) }
        switch current {
        case PlaneMapByte.hyphen: return matchHyphen(at: start, terminals: &terminals)
        case PlaneMapByte.space, PlaneMapByte.tab: return (nil, ReferenceWardleyMapWords.endOfBlanks(in: terminals, from: start))
        case PlaneMapByte.plus, PlaneMapByte.greaterThan: return ReferenceWardleyMapWords.endOfLink(in: terminals, at: start)
        case PlaneMapByte.semicolon:
            let end = terminals.lineEnd(from: start + 1)
            return end > start + 1 ? (.linkLabel, end) : nil
        case PlaneMapByte.quotationMark, PlaneMapByte.apostrophe: return terminals.endOfString(at: start).map { end in (.string, end) }
        case PlaneMapByte.lineFeed, PlaneMapByte.carriageReturn: return terminals.endOfLineBreak(at: start).map { end in (.newline, end) }
        case PlaneMapByte.percent:
            if let end = terminals.endOfDirective(at: start) { return (nil, end) }
            return terminals.endOfComment(at: start).map { end in (nil, end) }
        default:
            if PlaneMapByte.isDigit(current) { return ReferenceWardleyMapWords.matchNumber(in: terminals, at: start) }
            return ReferenceWardleyMapWords.matchWord(in: &terminals, at: start)
        }
    }

    /// `-`, unless `->`, `-->`, `-.->` or front matter is longer.
    private static func matchHyphen(at start: Int, terminals: inout PlaneMapTerminals) -> (ReferenceWardleyMapTokenKind?, Int)? {
        if terminals.byte(start + 1) == PlaneMapByte.greaterThan { return (.arrow, start + 2) }
        if terminals.hasPrefix("-->", at: start) { return (.linkArrow, start + 3) }
        if terminals.hasPrefix("-.->", at: start) { return (.linkArrow, start + 4) }
        if let end = terminals.endOfFrontMatter(at: start) { return (nil, end) }
        return (.minus, start + 1)
    }

    private static let punctuation: [UInt8: ReferenceWardleyMapTokenKind] = [
        PlaneMapByte.openingBracket: .openingBracket, PlaneMapByte.comma: .comma, PlaneMapByte.closingBracket: .closingBracket, PlaneMapByte.atSign: .atSign,
        PlaneMapByte.slash: .slash, PlaneMapByte.openingParenthesis: .openingParenthesis, PlaneMapByte.closingParenthesis: .closingParenthesis,
        PlaneMapByte.openingBrace: .openingBrace, PlaneMapByte.closingBrace: .closingBrace,
    ]
}


/// Matches the terminals of a Wardley map that start with a letter, a digit or a link's sign, in Pele's order.
enum ReferenceWardleyMapWords {
    /// The keywords in Pele's order, each matched without regard to what follows it, as Langium's lexer matches them.
    private static let keywords: [(String, ReferenceWardleyMapTokenKind)] = [
        ("wardley-beta", .wardleyKeyword), ("size", .size), ("evolution", .evolution), ("anchor", .anchor), ("component", .component), ("label", .label),
        ("inertia", .inertia), ("evolve", .evolve), ("pipeline", .pipeline), ("note", .note), ("annotations", .annotations), ("annotation", .annotation),
        ("accelerator", .accelerator), ("deaccelerator", .deaccelerator),
    ]
    private static let sourcingWords = ["build", "buy", "outsource", "market"]

    static func endOfBlanks(in terminals: PlaneMapTerminals, from start: Int) -> Int {
        var end = start
        while let next = terminals.byte(end), PlaneMapByte.isBlank(next) { end += 1 }
        return end
    }

    /// At `+`: a port (`+<>`, `+>`, `+<`), else a labelled arrow (`+'label'<>`, `<` or `>`); at `>`: an arrow.
    static func endOfLink(in terminals: PlaneMapTerminals, at start: Int) -> (ReferenceWardleyMapTokenKind?, Int)? {
        if terminals.byte(start) == PlaneMapByte.greaterThan { return (.linkArrow, start + 1) }
        for port in ["+<>", "+>", "+<"] where terminals.hasPrefix(port, at: start) { return (.linkPort, start + port.utf8.count) }
        guard terminals.byte(start + 1) == PlaneMapByte.apostrophe else { return nil }
        var index = start + 2
        while let next = terminals.byte(index), next != PlaneMapByte.apostrophe { index += 1 }
        guard terminals.byte(index) == PlaneMapByte.apostrophe else { return nil }
        for ending in ["<>", "<", ">"] where terminals.hasPrefix(ending, at: index + 1) { return (.linkArrow, index + 1 + ending.utf8.count) }
        return nil
    }

    /// Digits, a point and digits; else a whole number not followed by a point (`0` alone, or digits from 1 to 9 first,
    /// backing off one digit before a point); else an identifier.
    static func matchNumber(in terminals: PlaneMapTerminals, at start: Int) -> (ReferenceWardleyMapTokenKind?, Int)? {
        var end = start
        while let next = terminals.byte(end), PlaneMapByte.isDigit(next) { end += 1 }
        if terminals.byte(end) == PlaneMapByte.period, let next = terminals.byte(end + 1), PlaneMapByte.isDigit(next) {
            var fractionEnd = end + 1
            while let digit = terminals.byte(fractionEnd), PlaneMapByte.isDigit(digit) { fractionEnd += 1 }
            return (.decimal, fractionEnd)
        }
        if terminals.byte(start) == UInt8(ascii: "0") { return (.wholeNumber, start + 1) }
        if terminals.byte(end) != PlaneMapByte.period { return (.wholeNumber, end) }
        if end - start >= 2 { return (.wholeNumber, end - 1) }
        return endOfIdentifier(in: terminals, at: start).map { end in (.identifier, end) }
    }

    /// A sourcing word, a keyword, a name with spaces, an accessibility statement, a title or an identifier.
    static func matchWord(in terminals: inout PlaneMapTerminals, at start: Int) -> (ReferenceWardleyMapTokenKind?, Int)? {
        for word in sourcingWords where terminals.hasPrefix(word, at: start) { return (.sourcing, start + word.utf8.count) }
        for (word, kind) in keywords where terminals.hasPrefix(word, at: start) {
            return (kind, start + word.utf8.count)
        }
        if let end = endOfName(in: terminals, at: start) { return (.name, end) }
        if let end = terminals.endOfAccessibilityDescription(at: start) { return (.accessibilityDescription, end) }
        if let end = terminals.endOfAccessibilityTitle(at: start) { return (.accessibilityTitle, end) }
        if let end = terminals.endOfTitle(at: start) { return (.title, end) }
        return endOfIdentifier(in: terminals, at: start).map { end in (.identifier, end) }
    }

    /// A letter, then letters, digits, `_`, `(`, `)`, `&` and hyphens not before `>`; then words after spaces or tabs,
    /// each starting with a letter or `(`. Not a name where `title` and white space, `accTitle` or `accDescr` start.
    private static func endOfName(in terminals: PlaneMapTerminals, at start: Int) -> Int? {
        guard let first = terminals.byte(start), PlaneMapByte.isLetter(first) else { return nil }
        if terminals.hasPrefix("accTitle", at: start) || terminals.hasPrefix("accDescr", at: start) { return nil }
        if terminals.hasPrefix("title", at: start), JavaScriptWhitespace.length(in: terminals.bytes, at: start + 5) > 0 { return nil }
        var end = endOfNameWord(in: terminals, from: start + 1)
        while true {
            let afterBlanks = endOfBlanks(in: terminals, from: end)
            guard afterBlanks > end, let next = terminals.byte(afterBlanks), PlaneMapByte.isLetter(next) || next == PlaneMapByte.openingParenthesis else { return end }
            end = endOfNameWord(in: terminals, from: afterBlanks + 1)
        }
    }

    private static func endOfNameWord(in terminals: PlaneMapTerminals, from start: Int) -> Int {
        var end = start
        while let next = terminals.byte(end) {
            if PlaneMapByte.isWord(next) || next == PlaneMapByte.openingParenthesis || next == PlaneMapByte.closingParenthesis || next == PlaneMapByte.ampersand {
                end += 1
            } else if next == PlaneMapByte.hyphen, terminals.byte(end + 1) != PlaneMapByte.greaterThan {
                end += 1
            } else {
                return end
            }
        }
        return end
    }

    /// A word character, then word characters and hyphens, ending on a word character.
    private static func endOfIdentifier(in terminals: PlaneMapTerminals, at start: Int) -> Int? {
        guard let first = terminals.byte(start), PlaneMapByte.isWord(first) else { return nil }
        var end = start + 1
        var lastWord = end
        while let next = terminals.byte(end), PlaneMapByte.isWord(next) || next == PlaneMapByte.hyphen {
            end += 1
            if PlaneMapByte.isWord(next) { lastWord = end }
        }
        return lastWord
    }
}


/// Mermaid's `populateDb`: the size and the stages, then anchors, components, notes, pipelines, links, evolutions, the
/// annotations' box and the annotations, and the forces, in that order whatever the order written. A coordinate up to 1
/// is a fraction and is turned into percent; one from 1 to 100 is already one; any other is refused.
struct ReferenceWardleyMapBuilder {
    private var map = WardleyMap()
    private var indexByIdentifier: [String: Int] = [:]
    private var indexByTrend: [String: Int] = [:]
    private var indexByPipeline: [String: Int] = [:]
    private let bytes: [UInt8]

    static func map(of statements: WardleyMapStatements, bytes: [UInt8]) throws(MermaidDiagramReadError) -> WardleyMap {
        var builder = ReferenceWardleyMapBuilder(bytes: bytes)
        try builder.populate(statements)
        return builder.map
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private mutating func populate(_ statements: WardleyMapStatements) throws(MermaidDiagramReadError) {
        map.title = statements.title
        map.accessibilityTitle = statements.accessibilityTitle
        map.accessibilityDescription = statements.accessibilityDescription
        map.size = statements.size
        if let stages = statements.stages {
            map.stages = stages.map { stage in
                stage.secondName.map { second in PlaneMapText.trimmed(stage.name) + " / " + PlaneMapText.trimmed(second) } ?? PlaneMapText.trimmed(stage.name)
            }
            map.stageBoundaries = stages.compactMap(\.boundary)
        }
        for anchor in statements.anchors {
            let point = try self.point(anchor.first, anchor.second, at: anchor.offset)
            add(WardleyMapNode(identifier: anchor.name, label: anchor.name, point: point, kind: .anchor), keepsSourcing: true)
        }
        for component in statements.components {
            let point = try self.point(component.visibility, component.evolution, at: component.offset)
            add(WardleyMapNode(identifier: component.name, label: component.name, point: point, kind: .component, labelOffsetX: component.labelOffset?.x,
                               labelOffsetY: component.labelOffset?.y, hasInertia: component.hasInertia, sourcing: component.sourcing), keepsSourcing: false)
        }
        for note in statements.notes { map.notes.append(WardleyMapNote(text: note.name, point: try point(note.first, note.second, at: note.offset))) }
        for pipeline in statements.pipelines { try addPipeline(pipeline) }
        addLinks(statements.links)
        for evolve in statements.evolves { try addTrend(evolve) }
        if let box = statements.annotationBoxes.first { map.annotationsBox = try point(box.first, box.second, at: box.offset) }
        for annotation in statements.annotations {
            map.annotations.append(WardleyMapAnnotation(number: annotation.number, point: try point(annotation.first, annotation.second, at: annotation.offset),
                                                        text: annotation.text))
        }
        for force in statements.accelerators { map.accelerators.append(WardleyMapForce(name: force.name, point: try point(force.first, force.second, at: force.offset))) }
        for force in statements.deaccelerators {
            map.deaccelerators.append(WardleyMapForce(name: force.name, point: try point(force.first, force.second, at: force.offset)))
        }
    }

    /// `[visibility, evolution]` as written, as a point in percent: x the evolution, y the visibility.
    private func point(_ visibility: Double, _ evolution: Double, at offset: Int) throws(MermaidDiagramReadError) -> WardleyMapPoint {
        let x = try percent(evolution, at: offset)
        return WardleyMapPoint(x: x, y: try percent(visibility, at: offset))
    }

    /// A value up to 1 times 100, else the value, which must be from 0 to 100.
    private func percent(_ value: Double, at offset: Int) throws(MermaidDiagramReadError) -> Double {
        let normalized = value <= 1 ? value * 100 : value
        guard !(normalized < 0 || normalized > 100) else {
            throw .invalidSyntax(line: PlaneMapByte.line(of: offset, in: bytes), problem: .wardleyMap(.coordinateOutOfRange(value)))
        }
        return normalized
    }

    /// Adds `node`, or merges it into the node of its identifier: the label, the point and the kind are the new node's,
    /// the label offsets the new node's where it gives them, and the inertia and sourcing the new node's unless
    /// `keepsSourcing` (an anchor sets neither).
    private mutating func add(_ node: WardleyMapNode, keepsSourcing: Bool) {
        guard let index = indexByIdentifier[node.identifier] else {
            indexByIdentifier[node.identifier] = map.nodes.count
            map.nodes.append(node)
            return
        }
        var merged = map.nodes[index]
        merged.label = node.label
        merged.point = node.point
        merged.kind = node.kind
        merged.labelOffsetX = node.labelOffsetX ?? merged.labelOffsetX
        merged.labelOffsetY = node.labelOffsetY ?? merged.labelOffsetY
        if !keepsSourcing {
            merged.hasInertia = node.hasInertia
            merged.sourcing = node.sourcing
        }
        map.nodes[index] = merged
    }

    /// A pipeline under an existing component, its components at the parent's visibility with identifiers
    /// `Parent_Name`; a later pipeline under the same parent starts its components again.
    private mutating func addPipeline(_ pipeline: WardleyMapStatements.Pipeline) throws(MermaidDiagramReadError) {
        guard let parentIndex = indexByIdentifier[pipeline.parent] else {
            throw .invalidSyntax(line: PlaneMapByte.line(of: pipeline.offset, in: bytes), problem: .wardleyMap(.pipelineWithoutComponent(pipeline.parent)))
        }
        let visibility = map.nodes[parentIndex].point.y
        if let existing = indexByPipeline[pipeline.parent] {
            map.pipelines[existing].componentIdentifiers = []
        } else {
            indexByPipeline[pipeline.parent] = map.pipelines.count
            map.pipelines.append(WardleyMapPipeline(nodeIdentifier: pipeline.parent, componentIdentifiers: []))
        }
        map.nodes[parentIndex].isPipelineParent = true
        for component in pipeline.components {
            let identifier = pipeline.parent + "_" + component.name
            let point = WardleyMapPoint(x: try percent(component.evolution, at: component.offset), y: visibility)
            add(WardleyMapNode(identifier: identifier, label: component.name, point: point, kind: .pipelineComponent, labelOffsetX: component.labelOffset?.x,
                               labelOffsetY: component.labelOffset?.y), keepsSourcing: false)
            if let index = indexByPipeline[pipeline.parent] { map.pipelines[index].componentIdentifiers.append(identifier) }
            if let index = indexByIdentifier[identifier] { map.nodes[index].isInPipeline = true }
        }
    }

    /// Each link with its ends resolved, by identifier, else by the first node with that label, else as written.
    private mutating func addLinks(_ links: [WardleyMapStatements.Link]) {
        guard !links.isEmpty else { return }
        var identifierByLabel: [String: String] = [:]
        for node in map.nodes where identifierByLabel[node.label] == nil { identifierByLabel[node.label] = node.identifier }
        func resolved(_ name: String) -> String {
            indexByIdentifier[name] != nil ? name : identifierByLabel[name] ?? name
        }
        for link in links {
            let isDashed = link.arrow.map { arrow in arrow.contains("-.->") || arrow.contains(".-.") } ?? false
            let fromArrow = Self.flowAndLabel(of: link.arrow)
            let flow = Self.flow(ofPort: link.fromPort) ?? Self.flow(ofPort: link.toPort) ?? fromArrow.flow
            map.links.append(WardleyMapLink(source: resolved(link.from), target: resolved(link.to), isDashed: isDashed, label: fromArrow.label ?? link.label,
                                            flow: flow))
        }
    }

    /// `evolve Component 0.8`, for a component found by its identifier.
    private mutating func addTrend(_ evolve: WardleyMapStatements.Placed) throws(MermaidDiagramReadError) {
        guard let index = indexByIdentifier[evolve.name] else { return }
        let trend = WardleyMapTrend(nodeIdentifier: evolve.name, target: WardleyMapPoint(x: try percent(evolve.first, at: evolve.offset), y: map.nodes[index].point.y))
        if let existing = indexByTrend[evolve.name] {
            map.trends[existing] = trend
        } else {
            indexByTrend[evolve.name] = map.trends.count
            map.trends.append(trend)
        }
    }

    private static func flow(ofPort port: String?) -> WardleyMapFlow? {
        switch port {
        case "+<>": .bidirectional
        case "+<": .backward
        case "+>": .forward
        default: nil
        }
    }

    /// A labelled arrow's flow and label (`+'label'>`): its label between apostrophes, its flow by its end.
    private static func flowAndLabel(of arrow: String?) -> (flow: WardleyMapFlow?, label: String?) {
        guard let arrow, arrow.hasPrefix("+") else { return (nil, nil) }
        var label: String?
        let afterPlus = arrow.dropFirst()
        if afterPlus.first == "'", let closing = afterPlus.dropFirst().firstIndex(of: "'") {
            label = String(afterPlus[afterPlus.index(after: afterPlus.startIndex)..<closing])
        }
        if arrow.contains("<>") { return (.bidirectional, label) }
        if arrow.contains("<") { return (.backward, label) }
        if arrow.contains(">") { return (.forward, label) }
        return (nil, label)
    }
}
