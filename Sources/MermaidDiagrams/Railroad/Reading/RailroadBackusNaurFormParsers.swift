/**
 * File: RailroadBackusNaurFormParsers.swift
 * -----------------------------------------
 * Layer: Core
 * Description: Reads a railroad rule's definition written in EBNF (`railroad-ebnf-beta`) or ABNF (`railroad-abnf-beta`)
 *              into one expression tree, as Mermaid's grammars and Pele's parsers read them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Reads EBNF in both its W3C and ISO 14977 styles: alternatives separated by `|`, parts one after the other with or
/// without `,`, groups `( )`, options `[ ]` and repetitions `{ }`, postfix `?`, `*` and `+`, and exceptions `a - b`, each
/// postfix and exception applying, left to right, to everything before it in its term.
struct RailroadExtendedBackusNaurFormParser {
    var reader: FirstMatchTokenReader<RailroadTokenKind>
    var budget: RailroadExpressionBudget

    /// Alternatives up to `closing` (left for the caller to read), or to what can follow no part at the definition's end.
    mutating func choice(depth: Int, closing: String?) throws(MermaidDiagramReadError) -> RailroadPart {
        var alternatives: [[RailroadPart]] = [[]]
        while true {
            alternatives[alternatives.count - 1].append(try term(depth: depth))
            let kind = reader.kind
            if let closing, kind == .sign(closing) { break }
            if reader.accept(.sign("|")) {
                alternatives.append([])
                continue
            }
            if reader.accept(.sign(",")) || kind.map(Self.startsPrimary) == true { continue }
            guard let closing else { break }
            throw reader.failure(.railroad(.expectedClosing(closing)))
        }
        var sequences: [RailroadPart] = []
        for alternative in alternatives { sequences.append(try budget.sequence(of: alternative)) }
        return try budget.choice(of: sequences)
    }

    /// A primary and its postfixes: `?` makes what is before it optional, `*` and `+` repeat it, and `- primary` makes
    /// it a sequence of it, the terminal `-` and that primary.
    private mutating func term(depth: Int) throws(MermaidDiagramReadError) -> RailroadPart {
        var result = try primary(depth: depth)
        while true {
            if reader.accept(.sign("?")) {
                result = try budget.optional(result)
            } else if reader.accept(.sign("*")) {
                result = try budget.repetition(result, minimum: 0, maximum: .infinity)
            } else if reader.accept(.sign("+")) {
                result = try budget.repetition(result, minimum: 1, maximum: .infinity)
            } else if reader.accept(.sign("-")) {
                result = try budget.exception(result, try primary(depth: depth))
            } else {
                return result
            }
        }
    }

    private mutating func primary(depth: Int) throws(MermaidDiagramReadError) -> RailroadPart {
        switch reader.kind {
        case .string: return try budget.leaf(.terminal(RailroadParser.unescaped(reader.take())))
        case .name: return try budget.leaf(.nonterminal(reader.take()))
        case .specialSequence:
            return try budget.leaf(.special(FirstMatchStatementValues.trimmed(String(reader.take().dropFirst().dropLast()))))
        case .sign("("), .sign("["), .sign("{"):
            try budget.check(depth: depth + 1)
            let opening = reader.take()
            let closing = opening == "(" ? ")" : opening == "[" ? "]" : "}"
            let inner = try choice(depth: depth + 1, closing: closing)
            _ = reader.take()
            switch opening {
            case "(": return inner
            case "[": return try budget.optional(inner)
            default: return try budget.repetition(inner, minimum: 0, maximum: .infinity)
            }
        default:
            throw reader.failure(.railroad(.expectedExpression))
        }
    }

    private static func startsPrimary(_ kind: RailroadTokenKind) -> Bool {
        switch kind {
        case .string, .name, .specialSequence, .sign("("), .sign("["), .sign("{"): true
        default: false
        }
    }
}

/// Reads ABNF as in RFC 5234: alternatives separated by `/`, elements one after the other, each an optional repeat
/// (`*`, `1*`, `2*4`, `*4`, `3`) before a string, a numeric value, a rule's name, a group `( )` or an option `[ ]`.
struct RailroadAugmentedBackusNaurFormParser {
    var reader: FirstMatchTokenReader<RailroadTokenKind>
    var budget: RailroadExpressionBudget

    mutating func alternation(depth: Int, closing: String?) throws(MermaidDiagramReadError) -> RailroadPart {
        var concatenations: [[RailroadPart]] = [[]]
        while true {
            concatenations[concatenations.count - 1].append(try element(depth: depth))
            let kind = reader.kind
            if let closing, kind == .sign(closing) { break }
            if reader.accept(.sign("/")) {
                concatenations.append([])
                continue
            }
            if kind.map(Self.startsElement) == true { continue }
            guard let closing else { break }
            throw reader.failure(.railroad(.expectedClosing(closing)))
        }
        var sequences: [RailroadPart] = []
        for concatenation in concatenations { sequences.append(try budget.sequence(of: concatenation)) }
        return try budget.choice(of: sequences)
    }

    private mutating func element(depth: Int) throws(MermaidDiagramReadError) -> RailroadPart {
        let repeatCount = reader.kind == .repeatCount || reader.kind == .exactRepeatCount ? reader.take() : nil
        let primary: RailroadPart
        switch reader.kind {
        case .string: primary = try budget.leaf(.terminal(String(reader.take().dropFirst().dropLast())))
        case .numberValue: primary = try budget.leaf(.terminal(reader.take()))
        case .name: primary = try budget.leaf(.nonterminal(reader.take()))
        case .sign("("), .sign("["):
            try budget.check(depth: depth + 1)
            let isOption = reader.take() == "["
            let inner = try alternation(depth: depth + 1, closing: isOption ? "]" : ")")
            _ = reader.take()
            primary = isOption ? try budget.optional(inner) : inner
        default:
            throw reader.failure(.railroad(.expectedExpression))
        }
        guard let repeatCount, !repeatCount.isEmpty else { return primary }
        let (minimum, maximum) = Self.counts(of: repeatCount)
        return minimum == 0 && maximum == 1 ? try budget.optional(primary) : try budget.repetition(primary, minimum: minimum, maximum: maximum)
    }

    /// The least and most counts of a repeat as Mermaid reads them with `parseInt`: `*` from none to any, `1*` from one,
    /// `*4` up to four, `3` exactly three; a count too large for a double is infinite.
    static func counts(of repeatCount: String) -> (Double, Double) {
        guard let star = repeatCount.firstIndex(of: "*") else {
            let exact = Double(repeatCount) ?? .infinity
            return (exact, exact)
        }
        let before = repeatCount[..<star]
        let after = repeatCount[repeatCount.index(after: star)...]
        return (before.isEmpty ? 0 : Double(before) ?? .infinity, after.isEmpty ? .infinity : Double(after) ?? .infinity)
    }

    private static func startsElement(_ kind: RailroadTokenKind) -> Bool {
        switch kind {
        case .string, .numberValue, .name, .sign("("), .sign("["), .repeatCount, .exactRepeatCount: true
        default: false
        }
    }
}
