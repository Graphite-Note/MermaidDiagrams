/**
 * File: RadarChartParser.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads a radar chart's statements after its `radar-beta` keyword: axes, curves, options and titles.
 *
 * Authors: Bahey Shalash
 * Version: 0.7
 * Date: 25/11/2026
 */

/// Reads the statements after the `radar-beta` keyword (and an optional `:`) as Mermaid's grammar does: `axis id["Label"],
/// …`, `curve id["Label"]{1, 2, 3}` or `{axis: 1, other: 2}`, the options `showLegend true`, `ticks 5`, `max 10`, `min 0`
/// and `graticule polygon`, several of one kind joined by commas, and `title …`, `accTitle: …`, `accDescr: …` or
/// `accDescr { … }`. Axes, curves and options follow one another on a line or on lines of their own; only a title
/// statement ends its line. A curve's named entries are matched with the axes once the whole text is read, so a curve may
/// come before the axes it names.
struct RadarChartParser {
    private var cursor: MermaidTextCursor
    private var chart = RadarChart()
    private var statements = MermaidTitleStatements()
    private var writtenCurves: [WrittenCurve] = []
    /// Every curve's entries, one after another: each entry's axis name ("" in a curve of numbers) and value.
    private var entryNames: [String] = []
    private var entryValues: [Double] = []
    private var entryCount = 0
    private let limits: MermaidDiagramLimits

    /// A curve as written: where its entries are in the parser's lists, and whether they name their axes.
    struct WrittenCurve {
        let name: String
        let label: DiagramLabel
        let line: Int
        let entries: Range<Int>
        let isNamed: Bool
    }

    private init(cursor: MermaidTextCursor, limits: MermaidDiagramLimits) {
        self.cursor = cursor
        self.limits = limits
        // Room for the entries of a few curves, made once.
        entryNames.reserveCapacity(Self.reservedEntryCount)
        entryValues.reserveCapacity(Self.reservedEntryCount)
    }

    static func parse(_ cursor: MermaidTextCursor, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> RadarChart {
        var parser = RadarChartParser(cursor: cursor, limits: limits)
        parser.chart.appearance = RadarAppearance(MermaidConfigurationOptions(section: "radar", in: cursor))
        parser.skipOptionalColon()
        try parser.readStatements()
        try parser.finish()
        parser.chart.seriesColors = MermaidThemeSeriesPalette.radar.seriesColors(in: cursor)
        return parser.chart
    }

    /// `radar-beta:` or `radar-beta :`.
    private mutating func skipOptionalColon() {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard lookahead.peek() == MermaidByte.colon else { return }
        lookahead.advance()
        cursor = lookahead
    }

    private mutating func readStatements() throws(MermaidDiagramReadError) {
        while true {
            MermaidTitleStatements.skipBlank(&cursor)
            guard !cursor.isAtEnd else { return }
            if try statements.read(&cursor) {
                try MermaidTitleStatements.expectLineEnd(&cursor)
                continue
            }
            switch RadarChartWords.word(in: cursor)?.kept {
            case .axis?: try readAxes()
            case .curve?: try readCurves()
            case let kept? where kept.startsOption: try readOptions()
            default: throw .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
            }
        }
    }

    /// Axes and curves are named at most as many as the diagram's nodes.
    private func checkRoomForOneMore() throws(MermaidDiagramReadError) {
        guard chart.axes.count + writtenCurves.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
    }

    // MARK: Axes and curves

    /// `axis` and one or more axes joined by commas.
    private mutating func readAxes() throws(MermaidDiagramReadError) {
        cursor.advance(by: 4)
        repeat {
            try checkRoomForOneMore()
            let name = try readName()
            let label = try readOptionalLabel()
            chart.axes.append(RadarAxis(name: name, label: label ?? DiagramLabelDecoder.label(from: name, form: .plain)))
        } while acceptComma()
    }

    /// `curve` and one or more curves joined by commas.
    private mutating func readCurves() throws(MermaidDiagramReadError) {
        cursor.advance(by: 5)
        repeat {
            try checkRoomForOneMore()
            let line = cursor.line
            let name = try readName()
            let label = try readOptionalLabel()
            guard cursor.peek() == MermaidByte.openingBrace else { throw problem(.expectedOpeningBrace) }
            cursor.advance()
            let firstEntry = entryValues.count
            let isNamed = try readEntries()
            writtenCurves.append(WrittenCurve(name: name, label: label ?? DiagramLabelDecoder.label(from: name, form: .plain), line: line,
                                              entries: firstEntry..<entryValues.count, isNamed: isNamed))
        } while acceptComma()
    }

    /// The entries of a curve after its `{` to its `}`: numbers, or axis names each with a number (and an optional colon);
    /// never both. Line breaks may come after the `{`, after a comma and before the `}`, not before a comma. The entries
    /// go into the parser's lists; whether they name their axes is returned.
    private mutating func readEntries() throws(MermaidDiagramReadError) -> Bool {
        skipLineBreaks()
        let isNamed = RadarChartWords.word(in: cursor)?.isName == true
        guard isNamed || cursor.peek().map(MermaidByte.isDigit) == true else { throw problem(.expectedName) }
        while true {
            guard entryCount < limits.maximumEdgeCount else { throw .tooManyChartValues(limit: limits.maximumEdgeCount) }
            entryCount += 1
            var axisName = ""
            if isNamed {
                axisName = try readName()
                cursor.skipSpaces()
                if cursor.peek() == MermaidByte.colon {
                    cursor.advance()
                    cursor.skipSpaces()
                }
            }
            let value = try readNumber()
            entryNames.append(axisName)
            entryValues.append(value)
            // The comma follows the entry on its line; line breaks may come after it, or before the `}`.
            guard acceptComma() else {
                skipLineBreaks()
                break
            }
            skipLineBreaks()
        }
        guard cursor.peek() == MermaidByte.closingBrace else { throw problem(.expectedClosingBrace) }
        cursor.advance()
        return isNamed
    }

    // MARK: Options

    /// One option, and more joined by commas.
    private mutating func readOptions() throws(MermaidDiagramReadError) {
        try readOption()
        while acceptComma() {
            cursor.skipSpaces()
            guard RadarChartWords.word(in: cursor)?.kept?.startsOption == true else { throw problem(.expectedOption) }
            try readOption()
        }
    }

    private mutating func readOption() throws(MermaidDiagramReadError) {
        let word = RadarChartWords.word(in: cursor)
        cursor.advance(by: word?.length ?? 0)
        cursor.skipSpaces()
        switch word?.kept {
        case .showLegend?: chart.options.showsLegend = try readEitherWord("true", "false", problem: .expectedBoolean)
        case .graticule?: chart.options.graticule = try readEitherWord("circle", "polygon", problem: .expectedGraticule) ? .circle : .polygon
        case .ticks?: chart.options.tickCount = min(try readNumber(), RadarChartOptions.largestTickCount)
        case .max?: chart.options.maximum = try readNumber()
        default: chart.options.minimum = try readNumber()
        }
    }

    /// `first` or `second` at the cursor, taken whatever follows it (`falsecurve` is `false` and a `curve`), as Mermaid's
    /// lexer takes the value of an option: true for `first`.
    private mutating func readEitherWord(_ first: StaticString, _ second: StaticString,
                                         problem expected: RadarSyntaxProblem) throws(MermaidDiagramReadError) -> Bool {
        if RadarChartWords.isWritten(first, in: cursor) {
            cursor.advance(by: first.utf8CodeUnitCount)
            return true
        }
        guard RadarChartWords.isWritten(second, in: cursor) else { throw problem(expected) }
        cursor.advance(by: second.utf8CodeUnitCount)
        return false
    }

    // MARK: Pieces

    private func problem(_ problem: RadarSyntaxProblem) -> MermaidDiagramReadError {
        .invalidSyntax(line: cursor.line, problem: .radar(problem))
    }

    private mutating func skipLineBreaks() {
        MermaidTitleStatements.skipBlank(&cursor)
    }

    /// A comma after spaces; moves past it.
    private mutating func acceptComma() -> Bool {
        var lookahead = cursor
        lookahead.skipSpaces()
        guard lookahead.peek() == MermaidByte.comma else { return false }
        lookahead.advance()
        cursor = lookahead
        return true
    }

    /// A name after spaces: letters, digits, underscores and hyphens, starting with a letter or an underscore, not a word
    /// the grammar keeps.
    private mutating func readName() throws(MermaidDiagramReadError) -> String {
        cursor.skipSpaces()
        guard let word = RadarChartWords.word(in: cursor), word.isName else { throw problem(.expectedName) }
        let name = cursor.text(from: cursor.position, to: cursor.position + word.length)
        cursor.advance(by: word.length)
        return name
    }

    /// `["Label"]` after spaces, or nil when no `[` follows.
    private mutating func readOptionalLabel() throws(MermaidDiagramReadError) -> DiagramLabel? {
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.openingBracket else { return nil }
        cursor.advance()
        cursor.skipSpaces()
        guard let quotation = cursor.peek(), quotation == MermaidByte.quotationMark || quotation == PieChartStatementText.apostrophe else {
            throw problem(.expectedLabel)
        }
        let text = try PieChartStatementText.readString(&cursor)
        cursor.skipSpaces()
        guard cursor.peek() == MermaidByte.closingBracket else { throw problem(.expectedLabel) }
        cursor.advance()
        return DiagramLabelDecoder.label(from: text, form: .plain)
    }

    /// A number after spaces: digits with an optional fraction, no sign, no leading zero before more digits.
    private mutating func readNumber() throws(MermaidDiagramReadError) -> Double {
        cursor.skipSpaces()
        guard let number = RadarChartWords.number(at: &cursor) else { throw problem(.expectedNumber) }
        return number
    }

    // MARK: End

    /// Gives each curve its values by the axes' order, now that every axis is known, and the titles.
    private mutating func finish() throws(MermaidDiagramReadError) {
        for written in writtenCurves {
            chart.curves.append(RadarCurve(name: written.name, label: written.label, values: try values(of: written)))
        }
        chart.title = statements.title
        chart.accessibilityTitle = statements.accessibilityTitle
        chart.accessibilityDescription = statements.accessibilityDescription
    }

    /// The values of a curve of numbers as written; of a curve of named entries, one per axis, the first entry of an axis
    /// winning: found by a search of the curve's entries when it has a few, in a table made once when it has more.
    private func values(of written: WrittenCurve) throws(MermaidDiagramReadError) -> [Double] {
        guard written.isNamed else { return Array(entryValues[written.entries]) }
        guard !chart.axes.isEmpty else { throw .invalidSyntax(line: written.line, problem: .radar(.entriesNamedBeforeAxes(curve: written.name))) }
        var byAxis: [String: Double] = [:]
        if written.entries.count > Self.largestSearchedEntryCount {
            for entry in written.entries where byAxis[entryNames[entry]] == nil { byAxis[entryNames[entry]] = entryValues[entry] }
        }
        return try chart.axes.map { axis throws(MermaidDiagramReadError) in
            let value = written.entries.count > Self.largestSearchedEntryCount
                ? byAxis[axis.name] : written.entries.first { entry in entryNames[entry] == axis.name }.map { entry in entryValues[entry] }
            guard let value else {
                throw .invalidSyntax(line: written.line, problem: .radar(.missingEntry(curve: written.name, axis: axis.label.spokenText)))
            }
            return value
        }
    }

    private static let reservedEntryCount = 32
    /// The most entries a curve's values are found by searching them, axis by axis.
    private static let largestSearchedEntryCount = 16
}
