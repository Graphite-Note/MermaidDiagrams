/**
 * File: WardleyMapStatementReading.swift
 * --------------------------------------
 * Layer: Core
 * Description: The parts of a Wardley map's statements as Pele's parser.ts reads them: names, numbers, coordinate pairs,
 *              label offsets, evolution stages, components with their sourcing and inertia, pipelines, annotations and
 *              links with their ports, arrows and labels.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension WardleyMapParser {
    /// A quoted string without its quotation marks, an identifier, or a name with spaces.
    mutating func readName() throws(MermaidDiagramReadError) -> String {
        switch current {
        case .string: return PlaneMapTerminalValues.string(take())
        case .identifier, .name: return take()
        default: throw failure(.expectedName)
        }
    }

    /// The token's text when it is of `kind`; an error that names Pele's token otherwise.
    mutating func expect(_ kind: WardleyMapTokenKind, named name: String) throws(MermaidDiagramReadError) -> String {
        guard isAt(kind) else { throw failure(.expectedToken(name)) }
        return take()
    }

    /// Moves past the token when it is of `kind`, without making its text; an error that names Pele's token otherwise.
    mutating func skip(_ kind: WardleyMapTokenKind, named name: String) throws(MermaidDiagramReadError) {
        guard isAt(kind) else { throw failure(.expectedToken(name)) }
        index += 1
    }

    mutating func readDecimal() throws(MermaidDiagramReadError) -> Double {
        Double(try expect(.decimal, named: "WARDLEY_NUMBER")) ?? .nan
    }

    mutating func readWholeNumber() throws(MermaidDiagramReadError) -> Double {
        Double(try expect(.wholeNumber, named: "INT")) ?? .infinity
    }

    /// `[first, second]`, each of `kind`, or either a decimal or a whole number when `kind` is nil.
    mutating func readPair(of kind: WardleyMapTokenKind?) throws(MermaidDiagramReadError) -> (first: Double, second: Double) {
        try skip(.openingBracket, named: "'['")
        let first = try readCoordinate(of: kind)
        try skip(.comma, named: "','")
        let second = try readCoordinate(of: kind)
        try skip(.closingBracket, named: "']'")
        return (first, second)
    }

    private mutating func readCoordinate(of kind: WardleyMapTokenKind?) throws(MermaidDiagramReadError) -> Double {
        switch kind {
        case .decimal: return try readDecimal()
        case .wholeNumber: return try readWholeNumber()
        default: return isAt(.decimal) ? try readDecimal() : try readWholeNumber()
        }
    }

    /// `label [x, y]`, each a whole number with an optional minus sign.
    mutating func readLabelOffset() throws(MermaidDiagramReadError) -> WardleyMapStatements.LabelOffset {
        try skip(.label, named: "KW_LABEL")
        try skip(.openingBracket, named: "'['")
        let x = try readSignedWholeNumber()
        try skip(.comma, named: "','")
        let y = try readSignedWholeNumber()
        try skip(.closingBracket, named: "']'")
        return WardleyMapStatements.LabelOffset(x: x, y: y)
    }

    private mutating func readSignedWholeNumber() throws(MermaidDiagramReadError) -> Double {
        let isNegative = isAt(.minus)
        if isNegative { index += 1 }
        return (isNegative ? -1 : 1) * (try readWholeNumber())
    }

    /// `evolution` and two or more stages joined by `->`, each a name, `@` and its right edge, and `/` and a second name.
    mutating func readEvolution() throws(MermaidDiagramReadError) {
        index += 1
        var stages = [try readStage()]
        try skip(.arrow, named: "ARROW")
        stages.append(try readStage())
        while isAt(.arrow) {
            index += 1
            guard stages.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            stages.append(try readStage())
        }
        statements.stages = stages
    }

    private mutating func readStage() throws(MermaidDiagramReadError) -> WardleyMapStatements.Stage {
        let name = try readName()
        var boundary: Double?
        if isAt(.atSign) {
            index += 1
            boundary = try readDecimal()
        }
        var secondName: String?
        if isAt(.slash) {
            index += 1
            secondName = try readName()
        }
        return WardleyMapStatements.Stage(name: name, boundary: boundary, secondName: secondName)
    }

    /// `component`, a name, `[visibility, evolution]`, a label offset, `(build)`, `(buy)`, `(outsource)` or `(market)`, and
    /// `inertia` or `(inertia)`, each optional in that order.
    mutating func readComponent(offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        let name = try readName()
        let pair = try readPair(of: .decimal)
        let labelOffset = isAt(.label) ? try readLabelOffset() : nil
        var sourcing: WardleyMapSourcing?
        if isAt(.openingParenthesis), index + 1 < tokens.count, tokens[index + 1].kind == .sourcing {
            sourcing = WardleyMapSourcing(rawValue: text(index + 1))
            index += 2
            try skip(.closingParenthesis, named: "')'")
        }
        var hasInertia = false
        if isAt(.inertia) {
            index += 1
            hasInertia = true
        } else if isAt(.openingParenthesis) {
            index += 1
            try skip(.inertia, named: "KW_INERTIA")
            try skip(.closingParenthesis, named: "')'")
            hasInertia = true
        }
        try countNode()
        statements.components.append(.init(name: name, visibility: pair.first, evolution: pair.second, labelOffset: labelOffset, sourcing: sourcing,
                                           hasInertia: hasInertia, offset: offset))
    }

    /// `pipeline`, its parent's name and `{`, a line break, then one or more components with one decimal each and an
    /// optional label offset, each ending its line, then `}`.
    mutating func readPipeline(offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        let parent = try readName()
        try skip(.openingBrace, named: "'{'")
        try skip(.newline, named: "NEWLINE")
        while isAt(.newline) { index += 1 }
        var components: [WardleyMapStatements.PipelineComponent] = []
        repeat {
            let componentOffset = index < tokens.count ? tokens[index].start : bytes.count
            try skip(.component, named: "KW_COMPONENT")
            let name = try readName()
            try skip(.openingBracket, named: "'['")
            let evolution = try readDecimal()
            try skip(.closingBracket, named: "']'")
            let labelOffset = isAt(.label) ? try readLabelOffset() : nil
            if current != nil {
                guard isAt(.newline) else { throw failure(.expectedLineEnd) }
                while isAt(.newline) { index += 1 }
            }
            try countNode()
            components.append(.init(name: name, evolution: evolution, labelOffset: labelOffset, offset: componentOffset))
        } while isAt(.component)
        try skip(.closingBrace, named: "'}'")
        statements.pipelines.append(.init(parent: parent, components: components, offset: offset))
    }

    /// `annotation`, its number, `,`, its coordinates, decimal or whole, and its quoted text.
    mutating func readAnnotation(offset: Int) throws(MermaidDiagramReadError) {
        index += 1
        let number = try readWholeNumber()
        try skip(.comma, named: "','")
        let pair = try readPair(of: nil)
        let text = PlaneMapTerminalValues.string(try expect(.string, named: "STRING"))
        try countNode()
        statements.annotations.append(.init(number: number, first: pair.first, second: pair.second, text: text, offset: offset))
    }

    /// A link: a name, a port, an arrow, a name, a port and a label after `;`, the ports, the arrow and the label optional.
    mutating func readLink() throws(MermaidDiagramReadError) {
        guard isAt(.string) || isAt(.identifier) || isAt(.name) else { throw failure(.expectedStatement) }
        let from = try readName()
        let fromPort = isAt(.linkPort) ? take() : nil
        let arrow = isAt(.linkArrow) || isAt(.arrow) ? take() : nil
        let to = try readName()
        let toPort = isAt(.linkPort) ? take() : nil
        let label = isAt(.linkLabel) ? PlaneMapText.trimmed(String(take().dropFirst())) : nil
        guard statements.links.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        statements.links.append(.init(from: from, fromPort: fromPort, arrow: arrow, to: to, toPort: toPort, label: label))
    }
}
