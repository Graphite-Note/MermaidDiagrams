/**
 * File: RailroadParser.swift
 * --------------------------
 * Layer: Core
 * Description: Reads a railroad diagram after its keyword as Mermaid's four railroad parsers do: the title and
 *              accessibility statements, then rules to the end of the text in the notation its keyword names.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

/// Reads a railroad diagram over the tokens of its notation's lexer (`RailroadLexers`): titles and accessibility
/// statements, any number and in any order, then each rule (a name, its sign, its definition and `;`) to the end of the
/// text, each definition read by its notation's parser into one `RailroadExpression` tree.
enum RailroadParser {
    typealias Reader = FirstMatchTokenReader<RailroadTokenKind>

    /// Reads the railroad diagram whose keyword, `keyword` as written, ends at the cursor.
    static func parse(_ cursor: MermaidTextCursor, keyword: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> RailroadDiagram {
        guard let notation = RailroadNotation(typeKeyword: keyword), keyword == notation.keyword,
              FirstMatchTokenPatterns.isAtEndOfWord(cursor.bytes, cursor.position) else {
            throw .invalidSyntax(line: cursor.line, problem: .railroad(.expectedKeyword(keyword)))
        }
        let text = RailroadSourceText(bytes: cursor.bytes, keywordEnd: cursor.position)
        let options = RailroadOptions(MermaidConfigurationOptions(section: "railroad", in: cursor))
        do {
            return try parse(text.bytes, from: text.start, notation: notation, options: options, limits: limits)
        } catch {
            throw text.inSource(error)
        }
    }

    /// Reads the rules of `bytes`, Pele's text of the diagram, from the end of its keyword at `start`.
    private static func parse(_ bytes: [UInt8], from start: Int, notation: RailroadNotation, options: RailroadOptions,
                              limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> RailroadDiagram {
        let tokens: [FirstMatchToken<RailroadTokenKind>]
        do {
            tokens = try RailroadLexers.tokenizer(of: notation).tokens(of: bytes, from: start)
        } catch {
            throw .invalidSyntax(line: Reader.line(of: error.position, in: bytes), problem: .unexpectedText(Reader.excerpt(at: error.position, in: bytes)))
        }
        var reader = Reader(bytes: bytes, tokens: tokens, start: start)
        var diagram = RailroadDiagram(notation: notation, options: options)
        readStatements(&reader, into: &diagram)
        var budget = RailroadExpressionBudget(limits: limits)
        while !reader.isAtEnd {
            try budget.count()
            let name = try reader.expect(.name, else: .railroad(.expectedRuleName))
            try readDefinitionSign(&reader, notation: notation)
            let definition = try readDefinition(&reader, notation: notation, budget: &budget)
            _ = try reader.expect(.sign(";"), else: .railroad(.expectedSemicolon))
            diagram.rules.append(RailroadRule(name: name, definition: definition))
        }
        return diagram
    }

    /// The titles and accessibility statements before the first rule: a later one of each kind replaces an earlier one,
    /// and the last one sets the diagram's only when it is not empty, as Mermaid's database is given them.
    private static func readStatements(_ reader: inout Reader, into diagram: inout RailroadDiagram) {
        var title: String?, accessibilityTitle: String?, accessibilityDescription: String?
        reading: while let kind = reader.kind {
            switch kind {
            case .title: title = unquotedTitle(FirstMatchStatementValues.title(of: reader.take()), notation: diagram.notation)
            case .accessibilityTitle: accessibilityTitle = FirstMatchStatementValues.accessibilityTitle(of: reader.take())
            case .accessibilityDescription: accessibilityDescription = FirstMatchStatementValues.accessibilityDescription(of: reader.take())
            default: break reading
            }
        }
        if let title, !title.isEmpty { diagram.title = title }
        if let accessibilityTitle, !accessibilityTitle.isEmpty { diagram.accessibilityTitle = accessibilityTitle }
        if let accessibilityDescription, !accessibilityDescription.isEmpty { diagram.accessibilityDescription = accessibilityDescription }
    }

    /// A title in matching quotation marks without them: its escapes read, except in ABNF, whose strings have none.
    private static func unquotedTitle(_ title: String, notation: RailroadNotation) -> String {
        guard let quote = title.first, quote == "\"" || quote == "'", title.hasSuffix(String(quote)) else { return title }
        return notation == .augmentedBackusNaurForm ? String(title.dropFirst().dropLast()) : unescaped(title)
    }

    private static func readDefinitionSign(_ reader: inout Reader, notation: RailroadNotation) throws(MermaidDiagramReadError) {
        switch notation {
        case .parsingExpressionGrammar:
            _ = try reader.expect(.sign("<-"), else: .railroad(.expectedDefinitionSign))
        case .extendedBackusNaurForm:
            if !reader.accept(.sign("=")) { _ = try reader.expect(.sign("::="), else: .railroad(.expectedDefinitionSign)) }
        case .railroad, .augmentedBackusNaurForm:
            _ = try reader.expect(.sign("="), else: .railroad(.expectedDefinitionSign))
        }
    }

    private static func readDefinition(_ reader: inout Reader, notation: RailroadNotation,
                                       budget: inout RailroadExpressionBudget) throws(MermaidDiagramReadError) -> RailroadExpression {
        switch notation {
        case .railroad:
            var parser = RailroadConstructorNotationParser(reader: reader, budget: budget)
            defer { reader = parser.reader; budget = parser.budget }
            return try parser.expression(depth: 1).expression
        case .extendedBackusNaurForm:
            var parser = RailroadExtendedBackusNaurFormParser(reader: reader, budget: budget)
            defer { reader = parser.reader; budget = parser.budget }
            return try parser.choice(depth: 1, closing: nil).expression
        case .augmentedBackusNaurForm:
            var parser = RailroadAugmentedBackusNaurFormParser(reader: reader, budget: budget)
            defer { reader = parser.reader; budget = parser.budget }
            return try parser.alternation(depth: 1, closing: nil).expression
        case .parsingExpressionGrammar:
            var parser = RailroadParsingExpressionGrammarParser(reader: reader, budget: budget)
            defer { reader = parser.reader; budget = parser.budget }
            return try parser.choice(depth: 1, isInGroup: false).expression
        }
    }

    /// The text inside a string's quotation marks with Mermaid's three escapes read (`\n`, `\r`, `\t`); any other
    /// escaped character stands for itself.
    static func unescaped(_ quoted: String) -> String {
        let scalars = Array(quoted.unicodeScalars)
        guard scalars.count >= 2 else { return "" }
        var text = String.UnicodeScalarView()
        var index = 1
        while index < scalars.count - 1 {
            var scalar = scalars[index]
            if scalar == "\\", index + 1 < scalars.count - 1 {
                index += 1
                switch scalars[index] {
                case "n": scalar = "\n"
                case "r": scalar = "\r"
                case "t": scalar = "\t"
                default: scalar = scalars[index]
                }
            }
            text.append(scalar)
            index += 1
        }
        return String(text)
    }
}
