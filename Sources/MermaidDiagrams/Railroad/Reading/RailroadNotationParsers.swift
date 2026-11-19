/**
 * File: RailroadNotationParsers.swift
 * -----------------------------------
 * Layer: Core
 * Description: Reads a railroad rule's definition written in Mermaid's constructor notation (`railroad-beta`) or as a
 *              parsing expression grammar (`railroad-peg-beta`) into one expression tree, as Pele's parsers read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads Mermaid's constructor notation: `terminal("…")`, `nonterminal("…")` and `special("…")` around a string,
/// `sequence(…)` and `choice(…)` around one or more expressions separated by commas, and `optional(…)`, `oneOrMore(…)`
/// and `zeroOrMore(…)` around exactly one.
struct RailroadConstructorNotationParser {
    var reader: FirstMatchTokenReader<RailroadTokenKind>
    var budget: RailroadExpressionBudget

    mutating func expression(depth: Int) throws(MermaidDiagramReadError) -> RailroadPart {
        try budget.check(depth: depth)
        guard case .constructor(let constructor) = reader.kind else { throw reader.failure(.railroad(.expectedExpression)) }
        _ = reader.take()
        _ = try reader.expect(.sign("("), else: .railroad(.expectedOpeningParenthesis))
        let expression: RailroadPart
        switch constructor {
        case "terminal", "nonterminal", "special":
            let text = RailroadParser.unescaped(try reader.expect(.string, else: .railroad(.expectedQuotedText)))
            expression = try budget.leaf(constructor == "terminal" ? .terminal(text) : constructor == "nonterminal" ? .nonterminal(text) : .special(text))
        case "sequence", "choice":
            var elements = [try self.expression(depth: depth + 1)]
            while reader.accept(.sign(",")) { elements.append(try self.expression(depth: depth + 1)) }
            expression = constructor == "sequence" ? try budget.sequence(of: elements) : try budget.choice(of: elements)
        default:
            let element = try self.expression(depth: depth + 1)
            switch constructor {
            case "optional": expression = try budget.optional(element)
            case "oneOrMore": expression = try budget.repetition(element, minimum: 1, maximum: .infinity)
            default: expression = try budget.repetition(element, minimum: 0, maximum: .infinity)
            }
        }
        _ = try reader.expect(.sign(")"), else: .railroad(.expectedClosing(")")))
        return expression
    }
}

/// Reads a parsing expression grammar: ordered choices separated by `/`, sequences of prefixes, each an optional
/// predicate (`&`, `!`) before a suffix, each a primary (a literal, a name, `.` or a group `( )`) and an optional `?`,
/// `*` or `+`. A predicate is shown as special text: its operator and what it looks ahead for (`!"x"`, `&name`, `!.`), or
/// `(...)` for anything larger.
struct RailroadParsingExpressionGrammarParser {
    var reader: FirstMatchTokenReader<RailroadTokenKind>
    var budget: RailroadExpressionBudget

    mutating func choice(depth: Int, isInGroup: Bool) throws(MermaidDiagramReadError) -> RailroadPart {
        var sequences: [[RailroadPart]] = [[]]
        while true {
            sequences[sequences.count - 1].append(try prefix(depth: depth))
            let kind = reader.kind
            if isInGroup, kind == .sign(")") { break }
            if reader.accept(.sign("/")) {
                sequences.append([])
                continue
            }
            if kind.map(Self.startsPrefix) == true { continue }
            guard isInGroup else { break }
            throw reader.failure(.railroad(.expectedClosing(")")))
        }
        var alternatives: [RailroadPart] = []
        for sequence in sequences { alternatives.append(try budget.sequence(of: sequence)) }
        return try budget.choice(of: alternatives)
    }

    private mutating func prefix(depth: Int) throws(MermaidDiagramReadError) -> RailroadPart {
        let predicate = reader.kind == .sign("&") || reader.kind == .sign("!") ? reader.take() : nil
        var suffix: RailroadPart
        switch reader.kind {
        case .string: suffix = try budget.leaf(.terminal(RailroadParser.unescaped(reader.take())))
        case .name: suffix = try budget.leaf(.nonterminal(reader.take()))
        case .sign("."): suffix = try budget.leaf(.special(reader.take()))
        case .sign("("):
            try budget.check(depth: depth + 1)
            _ = reader.take()
            suffix = try choice(depth: depth + 1, isInGroup: true)
            _ = reader.take()
        default:
            throw reader.failure(.railroad(.expectedExpression))
        }
        if reader.accept(.sign("?")) {
            suffix = try budget.optional(suffix)
        } else if reader.accept(.sign("*")) {
            suffix = try budget.repetition(suffix, minimum: 0, maximum: .infinity)
        } else if reader.accept(.sign("+")) {
            suffix = try budget.repetition(suffix, minimum: 1, maximum: .infinity)
        }
        guard let predicate else { return suffix }
        return try budget.leaf(.special(predicate + Self.label(of: suffix.expression)))
    }

    /// What a predicate shows of the expression it looks ahead for.
    private static func label(of expression: RailroadExpression) -> String {
        switch expression {
        case .terminal(let value): "\"\(value)\""
        case .nonterminal(let name): name
        case .special(let text): text
        default: "(...)"
        }
    }

    private static func startsPrefix(_ kind: RailroadTokenKind) -> Bool {
        switch kind {
        case .string, .name, .sign("."), .sign("("), .sign("&"), .sign("!"): true
        default: false
        }
    }
}
