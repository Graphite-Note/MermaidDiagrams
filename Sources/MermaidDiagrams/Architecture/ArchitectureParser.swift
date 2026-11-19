/**
 * File: ArchitectureParser.swift
 * ------------------------------
 * Layer: Core
 * Description: Reads an architecture diagram's statements as Pele's architecture parser does: groups, services and
 *              junctions with their icons, titles and parents, edges between sides, alignments, titles and
 *              accessibility statements, each error with its line.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The statements of an architecture diagram as Pele's AST holds them, each with where it starts.
struct ArchitectureStatements {
    struct Declaration {
        let identifier: String
        let icon: String?
        let iconText: String?
        let title: String?
        let parent: String?
        let start: Int
    }

    struct Link {
        let source: String
        let sourceSide: ArchitectureSide
        let hasSourceArrow: Bool
        let leavesSourceGroup: Bool
        let target: String
        let targetSide: ArchitectureSide
        let hasTargetArrow: Bool
        let entersTargetGroup: Bool
        let title: String?
        let start: Int
    }

    var title: String?
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var groups: [Declaration] = []
    var services: [Declaration] = []
    var junctions: [Declaration] = []
    var links: [Link] = []
    var alignments: [(isRow: Bool, members: [String], start: Int)] = []
}

/// Pele's `parseArchitecture` over the lexer's tokens, then its database's checks (`ArchitectureDiagramBuilder`).
struct ArchitectureParser {
    private let tokens: [(token: ArchitectureToken, start: Int, end: Int)]
    private let bytes: [UInt8]
    private var index = 0
    private var statements = ArchitectureStatements()

    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> ArchitectureDiagram {
        guard keyword == "architecture-beta" else {
            throw .invalidSyntax(line: cursor.line, problem: .architecture(.expectedKeyword))
        }
        var parser = ArchitectureParser(tokens: try ArchitectureLexer.tokens(after: cursor), bytes: cursor.bytes)
        try parser.readStatements()
        var builder = ArchitectureDiagramBuilder(bytes: cursor.bytes, limits: limits)
        var diagram = try builder.diagram(of: parser.statements)
        diagram.options = ArchitectureOptions(MermaidConfigurationOptions(section: "architecture", in: cursor.bytes))
        return diagram
    }

    private var current: ArchitectureToken? { index < tokens.count ? tokens[index].token : nil }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while let token = current {
            switch token {
            case .newline:
                index += 1
                continue
            case .accessibilityDescription(let text):
                statements.accessibilityDescription = text
                index += 1
            case .accessibilityTitle(let text):
                statements.accessibilityTitle = text
                index += 1
            case .title(let text):
                statements.title = text
                index += 1
            case .group, .service, .junction: try declaration(token)
            case .identifier: try link()
            case .align: try alignment()
            default: throw failure(.expectedStatement)
            }
            guard let next = current else { return }
            guard next == .newline else { throw failure(.expectedLineEnd) }
        }
    }

    /// `group id(icon)[Title] in parent`, `service id(icon)[Title] in group` (or `"text"` for the icon), `junction id in group`.
    private mutating func declaration(_ keyword: ArchitectureToken) throws(MermaidDiagramReadError) {
        let start = tokens[index].start
        index += 1
        let identifier = try expectIdentifier()
        var icon: String?
        var iconText: String?
        var title: String?
        if keyword != .junction {
            if keyword == .service, case .string(let text) = current {
                iconText = text
                index += 1
            } else if case .icon(let name) = current {
                icon = name
                index += 1
            }
            if case .label(let written) = current {
                title = Self.labelValue(written)
                index += 1
            }
        }
        var parent: String?
        if current == .inGroup {
            index += 1
            parent = try expectIdentifier()
        }
        let declaration = ArchitectureStatements.Declaration(identifier: identifier, icon: icon, iconText: iconText, title: title, parent: parent, start: start)
        switch keyword {
        case .group: statements.groups.append(declaration)
        case .service: statements.services.append(declaration)
        default: statements.junctions.append(declaration)
        }
    }

    /// `a{group}:R <-[Title]-> L:b{group}`.
    private mutating func link() throws(MermaidDiagramReadError) {
        let start = tokens[index].start
        let source = try expectIdentifier()
        let leavesSourceGroup = accept(.groupModifier)
        try expect(.colon, else: .expectedColon)
        let sourceSide = try expectSide()
        let hasSourceArrow = accept(.into)
        var title: String?
        if !accept(.dashes) {
            guard accept(.dash) else { throw failure(.expectedLine) }
            guard case .label(let written) = current else { throw failure(.expectedEdgeTitle) }
            index += 1
            title = Self.labelValue(written)
            try expect(.dash, else: .expectedEdgeTitle)
        }
        let hasTargetArrow = accept(.into)
        let targetSide = try expectSide()
        try expect(.colon, else: .expectedColon)
        let target = try expectIdentifier()
        let entersTargetGroup = accept(.groupModifier)
        statements.links.append(ArchitectureStatements.Link(source: source, sourceSide: sourceSide, hasSourceArrow: hasSourceArrow,
                                                            leavesSourceGroup: leavesSourceGroup, target: target, targetSide: targetSide,
                                                            hasTargetArrow: hasTargetArrow, entersTargetGroup: entersTargetGroup, title: title, start: start))
    }

    /// `align row a b c` or `align column a b`, at least two members.
    private mutating func alignment() throws(MermaidDiagramReadError) {
        let start = tokens[index].start
        index += 1
        guard current == .row || current == .column else { throw failure(.expectedRowOrColumn) }
        let isRow = current == .row
        index += 1
        var members = [try expectIdentifier(), try expectIdentifier()]
        while case .identifier(let member) = current {
            members.append(member)
            index += 1
        }
        statements.alignments.append((isRow, members, start))
    }

    private mutating func accept(_ token: ArchitectureToken) -> Bool {
        guard current == token else { return false }
        index += 1
        return true
    }

    private mutating func expect(_ token: ArchitectureToken, else problem: ArchitectureSyntaxProblem) throws(MermaidDiagramReadError) {
        guard accept(token) else { throw failure(problem) }
    }

    private mutating func expectIdentifier() throws(MermaidDiagramReadError) -> String {
        guard case .identifier(let identifier) = current else { throw failure(.expectedIdentifier) }
        index += 1
        return identifier
    }

    private mutating func expectSide() throws(MermaidDiagramReadError) -> ArchitectureSide {
        guard case .side(let side) = current else { throw failure(.expectedSide) }
        index += 1
        return side
    }

    /// The error at the current token's line, or, at the end, after the last token that is not a line break.
    private func failure(_ problem: ArchitectureSyntaxProblem) -> MermaidDiagramReadError {
        var at = index < tokens.count ? tokens[index].start : bytes.count
        if index >= tokens.count {
            var last = tokens.count
            while last > 0, tokens[last - 1].token == .newline { last -= 1 }
            if last > 0 { at = tokens[last - 1].end }
        }
        return .invalidSyntax(line: PlaneMapByte.line(of: at, in: bytes), problem: .architecture(problem))
    }

    /// Mermaid's `ArchitectureValueConverter` for a bracketed title: inside the brackets, trimmed, and without its
    /// quotation marks (`\"` and `\'` unescaped) when it is quoted.
    static func labelValue(_ written: String) -> String {
        var value = String(written.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let isQuoted = ((value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")))
        if isQuoted {
            value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\'", with: "'")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
