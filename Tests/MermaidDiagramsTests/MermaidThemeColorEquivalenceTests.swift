/**
 * File: MermaidThemeColorEquivalenceTests.swift
 * ---------------------------------------------
 * Layer: Tests
 * Description: Series colors looked up slot by slot are those the whole theme variables gave, on every corpus input
 *              and on generated and mutated themed texts; and a hexadecimal style color, theme color and label ink read
 *              on bytes are what 0.7.0 read through characters, to the bit, on random and hostile color texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class MermaidThemeColorEquivalenceTests: XCTestCase {
    private static let palettes: [MermaidThemeSeriesPalette] = [.pieChart, .gitGraph, .timeline, .radar, .treemap, .mindmap, .venn, .xyChart]

    /// How the series colors of `source` differ from those its whole theme variables give, or nil.
    private func seriesDifference(_ source: String) -> String? {
        guard let frontEnd = try? MermaidFrontEnd.read(source) else { return nil }
        let cursor = MermaidTextCursor(frontEnd)
        for palette in Self.palettes {
            let read = palette.seriesColors(in: cursor)
            let expected = palette.seriesColors(MermaidConfigurationOptions(section: "themeVariables", in: cursor))
            if read != expected { return "\(palette): \(read.colors), expected \(expected.colors)" }
        }
        return nil
    }

    private func seriesDifferences(_ sources: [String]) -> [String] {
        var found: [String] = []
        for source in sources {
            guard let difference = seriesDifference(source) else { continue }
            found.append("\(difference) in \(String(source.prefix(200)).debugDescription)")
            if found.count == 5 { break }
        }
        return found
    }

    func testEveryCorpusInputsSeriesColorsAreAsBefore() throws {
        XCTAssertEqual(try seriesDifferences(MermaidDirectiveJSONEquivalenceTests.everySource()), [])
    }

    func testGeneratedAndMutatedThemedTextsSeriesColorsAreAsBefore() {
        var generator = RandomThemedTexts(seed: 0x7EE7_0001)
        let sources = (0..<4_000).map { index in index.isMultiple(of: 4) ? generator.mutated(generator.themedText()) : generator.themedText() }
        XCTAssertEqual(seriesDifferences(sources), [])
        let colored = sources.filter { source in
            (try? MermaidFrontEnd.read(source)).map { frontEnd in !MermaidThemeSeriesPalette.pieChart.seriesColors(in: MermaidTextCursor(frontEnd)).isEmpty } ?? false
        }
        XCTAssertGreaterThan(colored.count, 500, "too few texts give a pie chart colors to compare")
    }

    func testStyleColorsAreReadAsBefore() {
        var generator = RandomThemedTexts(seed: 0x7EE7_0002)
        var found: [String] = []
        for _ in 0..<30_000 {
            let text = generator.colorText()
            let read = DiagramColor(cssText: text)
            let expected = ReferenceDiagramColor.color(cssText: text)
            if !Self.isIdentical(read, expected) { found.append("\(String(describing: read)), expected \(String(describing: expected)) for \(text.debugDescription)") }
            if found.count == 5 { break }
        }
        XCTAssertEqual(found, [])
    }

    func testThemeColorsAreReadAsBefore() {
        var generator = RandomThemedTexts(seed: 0x7EE7_0003)
        var found: [String] = []
        for _ in 0..<30_000 {
            let text = generator.colorText()
            let read = DiagramThemeColor(cssText: text)
            let trimmed = String(JavaScriptWhitespace.trimmed(Substring(text)))
            let isSafe = DiagramThemeColor.isSafe(trimmed)
            let expression = isSafe ? DiagramThemeColorExpression.read(Substring(trimmed)) : nil
            if read?.cssText != (isSafe ? trimmed : nil) || read?.expression != expression {
                found.append("\(String(describing: read)) for \(text.debugDescription)")
            }
            if found.count == 5 { break }
        }
        XCTAssertEqual(found, [])
    }

    func testInksAreReadAsBefore() {
        var generator = RandomThemedTexts(seed: 0x7EE7_0004)
        var found: [String] = []
        for _ in 0..<30_000 {
            let text = generator.colorText()
            let read = DiagramSeriesInk.luminanceAndAlpha(text)
            let expected = DiagramSeriesInk.luminanceAndAlphaOfText(text)
            let isSame = read?.0.bitPattern == expected?.0.bitPattern && read?.1.bitPattern == expected?.1.bitPattern
            if !isSame { found.append("\(String(describing: read)), expected \(String(describing: expected)) for \(text.debugDescription)") }
            if found.count == 5 { break }
        }
        XCTAssertEqual(found, [])
    }

    private static func isIdentical(_ first: DiagramColor?, _ second: DiagramColor?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        return first.red.bitPattern == second.red.bitPattern && first.green.bitPattern == second.green.bitPattern
            && first.blue.bitPattern == second.blue.bitPattern && first.alpha.bitPattern == second.alpha.bitPattern
    }
}

/// Seeded color texts and diagrams whose theme variables set series colors, in front matter, in directives or both.
struct RandomThemedTexts {
    private var random: RandomJSONTexts

    init(seed: UInt64) {
        random = RandomJSONTexts(seed: seed)
    }

    private mutating func pick(_ choices: [String]) -> String {
        choices[random.below(choices.count)]
    }

    /// A color as written: hexadecimal ones of every length and case, with white space and broken digits around, names,
    /// functions, variables and non-colors.
    mutating func colorText() -> String {
        let digits = "0123456789abcdefABCDEFgG"
        let hexadecimal = "#" + String((0..<random.below(10)).map { _ in digits[digits.index(digits.startIndex, offsetBy: random.below(digits.count))] })
        let body = random.below(3) == 0 ? pick(["red", "Red", "grey", "transparent", "none", "currentColor", "rgb(1, 2, 3)", "rgba(10%,20%,30%,0.5)",
                                                 "hsl(120 50% 50%)", "var(--pele-series-2)", "light-dark(#fff, #000)", "#", "##fff", "#ｆｆｆ", "#fff ",
                                                 "#f\u{301}ff", "oklch(70% 0.1 200)", "color-mix(in srgb, red, blue)", "", "#12345g", "rgb(255,0,0)",
                                                 "RGB(1 2 3 / 50%)", "rgba(1,2,3,4,5)", "rgb(1,2)", "rgb( 1 , 2 , 3 )", "rgb(1e2,inf,nan)", "rgb()",
                                                 "rgba(10%, 20%, 30%, 40%)", "rgb(", "rgbx(1,2,3)", "rgb(1,,2,3)", "rgb(-5,300,2.5)", "Transparent",
                                                 "NONE", "LightGoldenRodYellow", "rgb(1\r\n,2,3)", "rgb(1,2,3", "rgba(1 2 3 4)", "rgb(0x10,1,2)",
                                                 "rgb(1%,2,3)", "rgb(+1,.5,1.)", "rgb(1/2/3)", "rgb ( 1, 2, 3)", "lightgoldenrodyellowx", "red "]) : hexadecimal
        return pick(["", "", " ", "\t", "\n", "\u{A0}", "\u{2028}", "\u{0B}"]) + body + pick(["", "", " ", "\t", "\n", "\u{A0}", "\u{FEFF}"])
    }

    private mutating func quoted(_ color: String) -> String {
        "'" + color.replacingOccurrences(of: "'", with: "") + "'"
    }

    /// A pie chart, Git graph, timeline or Venn diagram whose theme variables set some of the variables each palette reads.
    mutating func themedText() -> String {
        let names = ["pie", "git", "cScale", "venn"]
        var frontMatterLines: [String] = []
        var directiveEntries: [String] = []
        for _ in 0..<(random.below(6) + 1) {
            let name = names[random.below(names.count)] + String(random.below(10))
            let color = random.below(5) == 0 ? pick(["", "null", "5", "true"]) : colorText().trimmingCharacters(in: .whitespacesAndNewlines)
            if random.below(2) == 0 {
                frontMatterLines.append("    \(name): " + (["null", "5", "true"].contains(color) ? color : quoted(color)))
            } else {
                directiveEntries.append("\"\(name)\": " + (["null", "5", "true"].contains(color) ? color : "\"" + color.replacingOccurrences(of: "\"", with: "") + "\""))
            }
        }
        if random.below(8) == 0 { frontMatterLines.append("    xyChart:\n      plotColorPalette: '#f00, #0f0, rgb(1,2,3)'") }
        var text = ""
        if !frontMatterLines.isEmpty, random.below(6) != 0 {
            text += "---\nconfig:\n  themeVariables:\n" + frontMatterLines.joined(separator: "\n") + "\n---\n"
        }
        if !directiveEntries.isEmpty {
            let section = random.below(10) == 0 ? pick(["5", "null", "\"x\"", "[]"]) : "{" + directiveEntries.joined(separator: ", ") + "}"
            text += "%%{init: {\"themeVariables\": \(section)}}%%\n"
        }
        return text + pick(["pie\n\"A\": 1\n\"B\": 2", "gitGraph\ncommit", "timeline\n2020 : a", "venn-beta\nset A", "xychart-beta\nbar [1, 2]"])
    }

    mutating func mutated(_ text: String) -> String {
        random.mutated(text)
    }
}
