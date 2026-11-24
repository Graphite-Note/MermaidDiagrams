/**
 * File: DiagramSVGWriterIdentityTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The rewritten SVG writer writes every document 0.7.0's writer (kept as ReferenceSVGWriter) writes, byte
 *              for byte: every input of every corpus with Pele's variables, its title and its description, and with the
 *              fixed palette and background, the narrow scenes at 280, 390 and 600 points, and seeded random scenes of
 *              every painting, text, number and name a scene can hold, hostile ones included; and the bytes a host takes
 *              are the document's.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSVGWriterIdentityTests: XCTestCase {
    /// The design's check of the prototype (`--prototype-svg check`), kept: 825 inputs written with Pele's variables,
    /// title and description and with the fixed palette and background, and their narrow scenes at 280, 390 and 600
    /// points, 2,246 documents in all, each the reference's to the byte.
    func testEveryDocumentOfEveryCorpusIsThe070WritersDocument() throws {
        let typography = DiagramSceneSamples.typography
        let palette = DiagramSVGColors.palette(MermaidDiagramsBenchmark.palette)
        var documentCount = 0
        var differenceCount = 0
        func compare(_ written: String, _ reference: String, _ name: @autoclosure () -> String) {
            documentCount += 1
            guard written != reference else { return }
            differenceCount += 1
            if differenceCount <= 5 { XCTFail("differs: \(name())\n written: \(written.prefix(400))\n reference: \(reference.prefix(400))") }
        }
        for (corpus, sources) in try OutputDigest.corpora() {
            for (index, source) in sources.enumerated() {
                guard let diagram = Self.prepared(source, typography: typography, narrowestColumnWidth: nil) else { continue }
                let type = diagram.kind.peleName
                compare(diagram.svgDocument(),
                        ReferenceSVGWriter().document(of: diagram.scene, diagramType: type, title: diagram.accessibility.title,
                                                      description: diagram.accessibility.description), "\(corpus) \(index)")
                compare(DiagramSVGWriter(colors: palette, paintsBackground: true).document(of: diagram.scene, diagramType: type),
                        ReferenceSVGWriter(colors: palette, paintsBackground: true).document(of: diagram.scene, diagramType: type), "\(corpus) \(index) palette")
                for width in OutputDigest.narrowColumnWidths {
                    guard let narrow = Self.prepared(source, typography: typography, narrowestColumnWidth: width)?.narrowScene else { continue }
                    compare(DiagramSVGWriter().document(of: narrow, diagramType: type), ReferenceSVGWriter().document(of: narrow, diagramType: type),
                            "\(corpus) \(index) narrow \(width)")
                }
            }
        }
        XCTAssertEqual(documentCount, 2_246)
        XCTAssertEqual(differenceCount, 0)
    }

    private static func prepared(_ source: String, typography: DiagramTypography, narrowestColumnWidth: CGFloat?) -> PreparedMermaidDiagram? {
        try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: narrowestColumnWidth,
                                               now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone)
    }

    /// Seeded random scenes: paths of every element with ordinary, fractional, tied, huge, negative and non-finite
    /// coordinates; every painting with every end, corner and dash; texts of one and several lines, with runs, escaped
    /// and forbidden characters, rotation and outline; written, mixed and series colors; fonts whose names hold quotes;
    /// theme series; identifier prefixes; titles and descriptions; both color modes, with and without a background.
    func testRandomAndHostileScenesAreWrittenAsThe070WriterWritesThem() {
        var samples = DiagramSVGSceneSamples(seed: 0x5C_E7E5)
        for round in 0..<600 {
            let scene = samples.scene()
            let colors: DiagramSVGColors = round % 3 == 0 ? .peleVariables : .palette(round % 2 == 0 ? DiagramScenePaletteSamples.dark : DiagramScenePaletteSamples.light)
            let prefix = ["pele", "note-7", "x\" onload=\"", "", "a_b-9"][round % 5]
            let paintsBackground = round % 4 == 1
            let title = round % 6 == 0 ? nil : samples.text()
            let description = round % 7 == 0 ? "" : samples.text()
            let written = DiagramSVGWriter(colors: colors, identifierPrefix: prefix, paintsBackground: paintsBackground)
                .document(of: scene, diagramType: samples.text(), title: title, description: description)
            let reference = ReferenceSVGWriter(colors: colors, identifierPrefix: prefix, paintsBackground: paintsBackground)
                .document(of: scene, diagramType: samples.lastText, title: title, description: description)
            if written != reference {
                XCTFail("round \(round) differs:\n written: \(written.prefix(600))\n reference: \(reference.prefix(600))")
                return
            }
        }
    }

    /// The bytes a host takes are the document's, for each corpus of the documentation's first example.
    func testTheBytesAHostTakesAreTheDocuments() throws {
        let typography = DiagramSceneSamples.typography
        for (corpus, sources) in try OutputDigest.corpora() {
            guard let source = sources.first, let diagram = Self.prepared(source, typography: typography, narrowestColumnWidth: nil) else { continue }
            let writer = DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.light), identifierPrefix: "host")
            let document = writer.document(of: diagram.scene, diagramType: diagram.kind.peleName, title: "T", description: "D")
            let bytes = writer.withDocumentBytes(of: diagram.scene, diagramType: diagram.kind.peleName, title: "T", description: "D") { bytes in Array(bytes) }
            XCTAssertEqual(bytes, Array(document.utf8), corpus)
        }
    }

    /// Every part's class is Pele's `pele-` and the part's raw value.
    func testEveryPartIsWrittenWithItsClass() {
        for part in DiagramScenePart.allCases {
            let scene = DiagramScene(size: CGSize(width: 10, height: 10), font: DiagramFont(postScriptName: nil, size: 12),
                                     items: [.shape(DiagramSceneShape(path: CGPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1), transform: nil),
                                                                      painting: .fill(.accent), part: part))])
            XCTAssertTrue(DiagramSVGWriter().document(of: scene, diagramType: "x").contains("<path class=\"pele-\(part.rawValue)\" d="), "\(part)")
        }
    }
}

/// Seeded random scenes for comparing writers, of every kind of item, paint and value a scene can hold.
struct DiagramSVGSceneSamples {
    private var generator: DiagramPathLaneSamples
    private(set) var lastText = ""
    private let measurer = DiagramSceneSamples.typography.measurer(size: 13)

    init(seed: UInt64) {
        generator = DiagramPathLaneSamples(seed: seed)
    }

    private mutating func pick(_ count: Int) -> Int {
        Int(generator.next() % UInt64(count))
    }

    /// A number of the kinds scenes hold, and of kinds they never should: ties at half hundredths, huge, not finite.
    mutating func number() -> CGFloat {
        switch pick(8) {
        case 0: CGFloat(pick(2_001)) / 200 - 5 + 0.005
        case 1: [CGFloat.nan, .infinity, -.infinity, 1e12, -1e12, 999_999_999_999.99, 9_999, -9_998.995, 0, -0.0][pick(10)]
        case 2: (generator.fraction() - 0.5) * 2e6
        default: generator.coordinate()
        }
    }

    mutating func point() -> CGPoint {
        CGPoint(x: number(), y: number())
    }

    /// Text with characters that are escaped or left out, beyond ASCII, and plain.
    mutating func text() -> String {
        let pieces = ["Tom & Jerry", "<b>", "\"q\" 'a'", "é漢😀", "\u{1}\u{FFFE}\u{FFFF}\t\n\r", "plain", " ", "\u{7F}x"]
        lastText = (0..<(pick(4) + 1)).map { _ in pieces[pick(pieces.count)] }.joined()
        return lastText
    }

    /// A paint of any role, mixture or written color; series indexes from 0, as scenes give them (a negative index, which
    /// no scene gives, counts back from the last: `DiagramPaletteSeriesIndexTests`).
    mutating func paint() -> DiagramPaint {
        let roles: [DiagramPaletteRole] = [.background, .foreground, .line, .surface, .border, .accent, .critical, .muted, .alternateSurface,
                                           .series(pick(40))]
        let opacity: CGFloat = [1, 0.5, 0.125, 0, -0.2, 1.5][pick(6)]
        switch pick(4) {
        case 0: return DiagramPaint(source: .mixture(from: roles[pick(roles.count)], to: roles[pick(roles.count)], share: generator.fraction()), opacity: opacity)
        case 1:
            let channels = [0, 1, 0.2, 0.999, generator.fraction(), 1.3, -0.4]
            let color = DiagramColor(red: channels[pick(7)], green: channels[pick(7)], blue: channels[pick(7)], alpha: [1, 0.5, 0][pick(3)])
            return DiagramPaint(source: .color(color), opacity: opacity)
        default: return DiagramPaint(roles[pick(roles.count)], opacity: opacity)
        }
    }

    mutating func stroke() -> DiagramStroke {
        let dashes = (0..<pick(4)).map { _ in number() }
        return DiagramStroke(lineWidth: number(), dashLengths: dashes, lineCap: [.butt, .round, .square][pick(3)], lineJoin: [.miter, .round, .bevel][pick(3)])
    }

    mutating func path() -> CGPath {
        let path = CGMutablePath()
        for _ in 0..<(pick(6) + 1) {
            switch pick(6) {
            case 0: path.move(to: point())
            case 1: path.addLine(to: point())
            case 2: path.addQuadCurve(to: point(), control: point())
            case 3: path.addCurve(to: point(), control1: point(), control2: point())
            case 4: path.addRoundedRect(in: CGRect(x: generator.coordinate(), y: generator.coordinate(), width: 30, height: 20), cornerWidth: 4, cornerHeight: 4)
            default: path.closeSubpath()
            }
        }
        return path
    }

    mutating func shape() -> DiagramSceneItem {
        let painting: DiagramShapePainting
        switch pick(4) {
        case 0: painting = .fill(paint())
        case 1: painting = .stroke(paint(), stroke())
        case 2: painting = .fillAndStroke(paint(), paint(), stroke())
        default:
            painting = .gradientFill(DiagramLinearGradient(startPaint: paint(), endPaint: paint(), startPoint: point(), endPoint: point(),
                                                           opacity: [1, 0.6, 0][pick(3)]))
        }
        return .shape(DiagramSceneShape(path: path(), painting: painting, part: DiagramScenePart.allCases[pick(DiagramScenePart.allCases.count)]))
    }

    mutating func placedText() -> DiagramSceneItem {
        let forms: [DiagramLabelDecoder.Form] = [.plain, .markdown]
        let source = pick(2) == 0 ? text() : "**\(text())** _\(text())_ `code` plain\n\(text())"
        var block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: source, form: forms[pick(2)]), measurer: measurer,
                                     maximumWidth: [40, 200, 1_000][pick(3)])
        block.center = point()
        let outline = pick(3) == 0 ? DiagramTextOutline(paint: paint(), lineWidth: number()) : nil
        return .text(DiagramSceneText(block: block, paint: paint(), isBold: pick(2) == 0, isItalic: pick(3) == 0, isMonospaced: pick(4) == 0,
                                      rotation: pick(3) == 0 ? number() : nil, outline: outline,
                                      part: DiagramScenePart.allCases[pick(DiagramScenePart.allCases.count)]))
    }

    mutating func scene() -> DiagramScene {
        let items = (0..<pick(12)).map { _ in pick(2) == 0 ? shape() : placedText() }
        let fonts = [nil, "ArialMT", "Weird\"Name\\", "Ünï <&>"]
        let series = DiagramSeriesColors(colors: (0..<pick(5)).map { _ in
            [DiagramThemeColor(cssText: "#ffeb3b"), DiagramThemeColor(cssText: "red"), nil, DiagramThemeColor(cssText: "var(--x, #123456)")][pick(4)]
        })
        return DiagramScene(size: CGSize(width: number(), height: number()), font: DiagramFont(postScriptName: fonts[pick(fonts.count)], size: number()),
                            items: items, seriesColors: series)
    }
}
