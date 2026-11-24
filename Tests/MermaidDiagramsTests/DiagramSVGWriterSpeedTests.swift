/**
 * File: DiagramSVGWriterSpeedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: What makes the SVG writer fast keeps its output: the thread's block is reused from document to
 *              document and a document written inside another gets its own, gradient documents are those of the writer
 *              that put its definitions in afterwards, the series variables' table and the hexadecimal digits are
 *              0.6.1's, the colors written are each paint's own text, a written color is spelled from its channels as
 *              its sRGB conversion, a buffer that grows writes what one that does not grow writes, and a piece at the
 *              end of the room grows it first.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class DiagramSVGWriterSpeedTests: XCTestCase {
    /// A thread writing every document of Pele's corpora, regular and narrow, in both color modes with a title and a
    /// description, a second time writes them all into the block it kept from the first time: no block is made or grown
    /// once the thread has written its largest document. Each is also written from inside the writing of another, into
    /// a block of its own, with the same bytes.
    func testAThreadsBlockIsReusedFromDocumentToDocument() throws {
        let typography = DiagramSceneSamples.typography
        var scenes: [(scene: DiagramScene, type: String, title: String, description: String)] = []
        for (_, sources) in try OutputDigest.corpora() {
            for source in sources {
                for width in [nil] + OutputDigest.narrowColumnWidths.map(Optional.some) {
                    guard let prepared = try? MermaidDiagramPreparation.prepare(source: source, typography: typography, narrowestColumnWidth: width,
                                                                                now: GanttChartCorpus.now, timeZone: GanttChartCorpus.timeZone),
                          let scene = width == nil ? prepared.scene : prepared.narrowScene else { continue }
                    scenes.append((scene, prepared.kind.peleName, prepared.accessibility.title ?? "A title", prepared.accessibility.description ?? "A description"))
                }
            }
        }
        XCTAssertGreaterThan(scenes.count, 1_450)
        let writers = [DiagramSVGWriter(), DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.dark), paintsBackground: true)]
        func writeAll() -> [Int] {
            scenes.flatMap { scene in
                writers.map { writer in writer.document(of: scene.scene, diagramType: scene.type, title: scene.title, description: scene.description).utf8.count }
            }
        }
        let first = writeAll()
        let block = DiagramSVGScratch.current.blockAddress
        let keptByteCount = DiagramSVGScratch.current.keptByteCount
        XCTAssertEqual(writeAll(), first)
        XCTAssertEqual(DiagramSVGScratch.current.blockAddress, block, "the block is reused")
        XCTAssertEqual(DiagramSVGScratch.current.keptByteCount, keptByteCount)
        for scene in scenes.prefix(200) {
            let writer = writers[0]
            let alone = writer.document(of: scene.scene, diagramType: scene.type, title: scene.title, description: scene.description)
            let inside = writer.withDocumentBytes(of: scene.scene, diagramType: "outer") { outer in
                (writer.document(of: scene.scene, diagramType: scene.type, title: scene.title, description: scene.description), outer.count)
            }
            XCTAssertEqual(inside.0, alone, scene.type)
            XCTAssertEqual(DiagramSVGScratch.current.blockAddress, block, "the inner document is written into a block of its own")
        }
    }

    /// A buffer given no room grows as it is written and writes what a buffer given all the room it needs writes.
    func testABufferThatGrowsWritesWhatOneThatDoesNotGrowWrites() {
        func write(into buffer: inout DiagramSVGBuffer) {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -1_234.5, y: 0.004))
            for step in 0..<2_000 {
                path.addCurve(to: CGPoint(x: CGFloat(step) * 1.25, y: -CGFloat(step) / 3),
                              control1: CGPoint(x: 999_999_999.99, y: -999_999_999.99), control2: CGPoint(x: 12.05, y: 7))
            }
            path.closeSubpath()
            for _ in 0..<50 {
                buffer.append("<path d=\"")
                buffer.appendPathData(path)
                buffer.append(byte: UInt8(ascii: "\""))
                buffer.appendEscaped(String(repeating: "Tom & Jerry's <\"quoted\"> \u{1}\u{FFFE}é ", count: 40))
                buffer.append(String(repeating: "var(--pele-series-1,#4c78a8)", count: 10))
                buffer.appendNumbers([4, 2.5, 0.004, 12.05])
                buffer.appendOpacity(0.25, attribute: "stroke-opacity")
            }
        }
        var growing = DiagramSVGBuffer()
        write(into: &growing)
        var roomy = DiagramSVGBuffer(reservingCapacity: growing.count + DiagramSVGNumberWriting.largestPathElementByteCount)
        let address = roomy.storageAddress
        write(into: &roomy)
        XCTAssertGreaterThan(growing.growthCount, 3)
        XCTAssertEqual(roomy.growthCount, 0)
        XCTAssertEqual(roomy.storageAddress, address, "the roomy buffer is written in place")
        XCTAssertEqual(growing.count, roomy.count)
        XCTAssertEqual(growing.text, roomy.text)
        XCTAssertTrue(roomy.text.hasPrefix("<path d=\"M-1234.5 0C999999999.99 -999999999.99 12.05 7 0 0C999999999.99 -999999999.99 12.05 7 1.25 -0.33C"))
    }

    /// Every piece the buffer writes after making sure of its room once (an entity, a number, an opacity attribute, a
    /// path element) is written whole when it starts at any of the last bytes of the room: the buffer grows first, so
    /// nothing goes past the block's end (which debug builds check at each write) and the bytes are the reference's.
    func testPiecesStartingAtTheEndOfTheRoomGrowTheBufferFirst() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -999_999_999_999.99, y: -999_999_999_999.99))
        path.addCurve(to: CGPoint(x: -999_999_999_999.99, y: -999_999_999_999.99), control1: CGPoint(x: -999_999_999_999.99, y: -0.25),
                      control2: CGPoint(x: 12.05, y: -999_999_999_999.99))
        let escaped = "\"&'<>\u{9}é"
        let pieces = DiagramSVGSyntax.escaped(escaped) + "-999999999999.99" + " stroke-opacity=\"0.25\"" + DiagramSVGSyntax.pathData(path)
        let capacity = 64
        for written in (capacity - DiagramSVGNumberWriting.largestPathElementByteCount)...capacity where written >= 0 {
            var buffer = DiagramSVGBuffer(reservingCapacity: capacity)
            let filler = String(repeating: "x", count: written)
            buffer.append(filler)
            buffer.appendEscaped(escaped)
            buffer.appendNumber(-999_999_999_999.99)
            buffer.appendOpacity(0.25, attribute: "stroke-opacity")
            buffer.appendPathData(path)
            XCTAssertEqual(buffer.text, filler + pieces, "\(written) bytes written first")
            XCTAssertLessThanOrEqual(buffer.count, buffer.capacity)
            XCTAssertGreaterThan(buffer.growthCount, 0)
        }
    }

    // MARK: Gradients

    /// The documents with gradients are those of origin/main's writer (`3015de9`), which wrote the definitions into a
    /// buffer of their own and put them in after the title and the description once the body was written: each Sankey
    /// example and a scene of gradients between other shapes and texts, with and without a title, a description and a
    /// background, in both color modes (digests recorded from that writer).
    func testGradientDocumentsAreThoseOfTheWriterThatPutTheDefinitionsInAfterwards() throws {
        var digests: [String] = []
        let scenes = try OutputDigest.corpora().first { corpus in corpus.name == "sankey-docs" }.map { corpus in
            corpus.sources.compactMap { source in
                try? MermaidDiagramPreparation.prepare(source: source, typography: DiagramSceneSamples.typography).scene
            }
        } ?? []
        XCTAssertEqual(scenes.count, 8)
        for scene in scenes + [Self.sceneOfGradientsBetweenOtherItems()] {
            for (writer, title, description) in Self.gradientWriters() {
                digests.append(FowlerNollVoDigest.of(writer.document(of: scene, diagramType: "sankey", title: title, description: description)))
            }
        }
        XCTAssertEqual(digests, Self.gradientDocumentDigests)
    }

    private static func gradientWriters() -> [(DiagramSVGWriter, String?, String?)] {
        [(DiagramSVGWriter(), nil, nil),
         (DiagramSVGWriter(identifierPrefix: "note-3"), "Energy & flows", nil),
         (DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.light), identifierPrefix: "note-9", paintsBackground: true),
          "Energy", "Flows <and> losses"),
         (DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.dark)), nil, "Only a description"),
         (DiagramSVGWriter(colors: .palette(DiagramScenePaletteSamples.dark), paintsBackground: true), "", "")]
    }

    /// Gradient fills first, between and last among fills, strokes and texts, one with an outline.
    private static func sceneOfGradientsBetweenOtherItems() -> DiagramScene {
        func rectangle(_ index: Int) -> CGPath {
            CGPath(rect: CGRect(x: CGFloat(index) * 10.5, y: 3.25, width: 40, height: 10), transform: nil)
        }
        func gradient(_ index: Int) -> DiagramSceneItem {
            let fill = DiagramLinearGradient(startPaint: .series(index), endPaint: .series(index + 3).atOpacity(0.5), startPoint: CGPoint(x: CGFloat(index), y: 0),
                                             endPoint: CGPoint(x: 40, y: 0.125), opacity: index.isMultiple(of: 2) ? 1 : 0.6)
            return .shape(DiagramSceneShape(path: rectangle(index), painting: .gradientFill(fill), part: .edge))
        }
        let measurer = DiagramSceneSamples.typography.measurer(size: 12)
        var label = DiagramTextBlock(label: DiagramLabel("Flow & <loss>"), measurer: measurer, maximumWidth: 200)
        label.center = CGPoint(x: 30, y: 20)
        let items: [DiagramSceneItem] = [
            gradient(0),
            .shape(DiagramSceneShape(path: rectangle(1), painting: .fill(.surface), part: .node)),
            .text(DiagramSceneText(block: label, paint: .foreground, outline: DiagramTextOutline(paint: .background, lineWidth: 3), part: .label)),
            gradient(2), gradient(3),
            .shape(DiagramSceneShape(path: rectangle(4), painting: .stroke(.line, .rounded(lineWidth: 1.5, dashLengths: [3, 2])), part: .edge)),
            .text(DiagramSceneText(block: label, paint: .muted, part: .edgeLabel)),
            gradient(5)
        ]
        return DiagramScene(size: CGSize(width: 120.5, height: 40), font: DiagramSceneSamples.typography.font, items: items)
    }

    /// Five writers per scene, the scenes in order, as origin/main 3015de9 wrote them.
    private static let gradientDocumentDigests = [
        "47da01b7a1ff8121", "5b3bdf3e5cc35cef", "0a94d1ffdcba713f", "749af2f3ef10c4f8", "2fd552e1a2a2fb63",
        "69f89b463f94277c", "3072442d2ce0b4be", "24480c90ce8ed883", "30444845b48a0409", "0c6436b3aecdb89f",
        "c487c856c37a5ad9", "0c7deee8ed9cccdf", "2edae2fc79d7579a", "f4f7901257416d60", "e094fc06565df33a",
        "2b5dd6a3bed6bf25", "eac168544d40ccdb", "31483959ab84c25c", "09479bbcd143beef", "4b84b9fb5668e4c9",
        "c31a83b84a1e96ad", "9b57bf135c620463", "abaf26c896c86f88", "09f5fc9e86f8fbbb", "58b5358fb5bf1e2d",
        "7a6ef1eaace4c7dd", "b7cb64fe8afad123", "b6d8d3ed1535cc58", "90b722e612dc8990", "b7c0bb84d5f697d8",
        "3b44efdb6e31f022", "12ff150d7867db30", "059d66758215b5e1", "6520567c8ebfa365", "51f9ba3e64ccfd5d",
        "2a55ad348cc91307", "e572fc7a90ce3dc5", "20d0d98862b4ab98", "1d82c2c8ab0f0796", "2e0bc6df0b385ad0",
        "d768386f0e5673b3", "f22136fbe731c06d", "23fffdba7803f13c", "a0a08370c37f6912", "f2b58d96e280b572"
    ]

    // MARK: Paints

    /// The table of Pele's series variables is what 0.6.1 spelled out for each series index, the colors taken in turn.
    func testTheSeriesVariablesAreWhat061SpelledOut() {
        for index in -17...17 {
            let slot = ((index % 8) + 8) % 8
            XCTAssertEqual(DiagramSVGColors.variable(.series(index)),
                           "var(--pele-series-\(slot + 1),\(Self.referenceHexadecimal(DiagramPalette.peleSeries[slot])))", "\(index)")
        }
    }

    /// The hexadecimal digits of a color are 0.6.1's, rounding and clamping included.
    func testHexadecimalColorsAreWrittenAs061WroteThem() throws {
        var generator = SeededGenerator(seed: 0x5EED)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let extended = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        for _ in 0..<2_000 {
            let components = (0..<3).map { _ in CGFloat.random(in: -0.2...1.2, using: &generator) } + [1]
            for colorSpace in [space, extended, displayP3] {
                let color = try XCTUnwrap(CGColor(colorSpace: colorSpace, components: components))
                XCTAssertEqual(DiagramSVGColors.hexadecimal(color), Self.referenceHexadecimal(color), "\(components)")
            }
        }
        for level in 0...255 {
            let color = CGColor(srgbRed: CGFloat(level) / 255, green: 0.5, blue: 1, alpha: 1)
            XCTAssertEqual(DiagramSVGColors.hexadecimal(color), Self.referenceHexadecimal(color))
        }
    }

    /// Each paint's color as the document's writer writes it, however many paints a document has and in whatever order
    /// they come, is the text its colors give it alone (`DiagramSVGColors.text(of:)`): the palette's paints compared in
    /// turn and those hashed past them alike, Pele's variables, mixtures and written colors spelled out.
    func testEachPaintsColorIsItsOwnTextPastThePaintsComparedInTurn() {
        var paints: [DiagramPaint] = [.background, .foreground, .accent, .critical, .muted, .alternateSurface, .line, .surface, .border,
                                      .betweenBackgroundAndForeground(share: 0.25), .surface.atOpacity(0.5)]
        paints += (0..<12).map { index in DiagramPaint.series(index) }
        paints += (0..<60).map { index in
            DiagramPaint.color(DiagramColor(red: Double(index) / 60, green: 0.5, blue: 1 - Double(index) / 60, alpha: index.isMultiple(of: 3) ? 0.5 : 1))
        }
        paints += (0..<20).map { index in DiagramPaint.betweenBackgroundAndForeground(share: CGFloat(index) / 20.5).atOpacity(0.75) }
        paints += [DiagramPaint(source: .mixture(from: .series(7), to: .series(15), share: 0.99999)), .color(DiagramColor(red: 1.2, green: -0.1, blue: .nan))]
        var generator = SeededGenerator(seed: 0xFACE)
        let order = (0..<1_000).map { _ in paints[Int.random(in: 0..<paints.count, using: &generator)] }
        for colors in [DiagramSVGColors.peleVariables, .palette(DiagramScenePaletteSamples.dark), .palette(DiagramScenePaletteSamples.light)] {
            var writer = DiagramSVGPaintWriter(colors: colors)
            for paint in order {
                var buffer = DiagramSVGBuffer()
                buffer.reserve(DiagramSVGPaintWriter.largestColorByteCount)
                let opacity = writer.writeColor(of: paint, into: &buffer)
                let alone = colors.text(of: paint)
                XCTAssertEqual(buffer.text, alone.color, "\(paint)")
                XCTAssertEqual(opacity, alone.opacity, "\(paint)")
            }
        }
    }

    /// A color the diagram's text gave is written from its own channels where they lie in 0...1, which is what
    /// converting its `CGColor` to sRGB gives, and through that conversion otherwise.
    func testWrittenColorsAreWrittenAsTheirSRGBConversion() throws {
        var generator = SeededGenerator(seed: 0xC0_10)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var channels: [Double] = (0...255).map { level in Double(level) / 255 } + [0, 1, -0.0, 0.5, 1e-300, 1 - 1e-16, -0.05, 1.06, 2, -1, .nan, .infinity, -.infinity]
        channels += (0..<2_000).map { _ in Double.random(in: 0...1, using: &generator) }
        for index in 0..<20_000 {
            let color = DiagramColor(red: channels[index % channels.count], green: channels[(index * 7 + 3) % channels.count],
                                     blue: channels[(index * 13 + 5) % channels.count])
            let converted = try XCTUnwrap(color.cgColor.converted(to: space, intent: .defaultIntent, options: nil))
            let packed = DiagramSVGPaintWriter.writtenColorHexadecimal(color)
            let written = String(decoding: (0..<7).map { byte in UInt8(truncatingIfNeeded: packed >> (byte * 8)) }, as: UTF8.self)
            XCTAssertEqual(written, DiagramSVGColors.hexadecimal(converted), "\(color)")
            XCTAssertEqual(written, Self.referenceHexadecimal(color.cgColor), "\(color)")
        }
    }

    // MARK: References of 0.6.1

    /// `DiagramSVGColors.hexadecimal` as 0.6.1 wrote it.
    private static func referenceHexadecimal(_ color: CGColor) -> String {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count == 4 else {
            return "#000000"
        }
        let channels = components.prefix(3).map { component in Int((min(1, max(0, component)) * 255).rounded()) }
        return "#" + channels.map { channel in
            let digits = String(channel, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }
}

/// SplitMix64: the same values on every run.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
