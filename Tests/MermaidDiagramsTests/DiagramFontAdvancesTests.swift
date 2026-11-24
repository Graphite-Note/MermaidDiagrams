/**
 * File: DiagramFontAdvancesTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Checks the font registry and the widths it gives: a measurer copies without retaining, widths from bytes
 *              are the widths of 0.7.0's String measuring to the bit for ASCII and every other script, a face past the
 *              registry's room measures alike, exactly summable tables sum alike in any order, and the line width cache
 *              lets its texts go when full and measures them again alike.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import CoreText
@testable import MermaidDiagrams
import XCTest

final class DiagramFontAdvancesTests: XCTestCase {
    private static let font = DiagramFont(postScriptName: nil, size: 16)
    private static let texts = ["Start", "Is it ready? (yes/no)", "", " ", "~tilde~", "Étape", "Начало", "数据库", "Done ✓", "«person»",
                                "├── src", "└─┬ lib", "日本語の、テキスト。", "e\u{301}", "\u{1F600} smile", "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
                                "tab\there", "soft\u{AD}hyphen", "\u{A0}no-break", "mixed ASCII «and» more"]

    /// 0.7.0's measuring, kept here: the font made as the registry makes it, printable ASCII added up from its advances
    /// in order, any other text as a Core Text line of the String.
    private func referenceWidth(of text: String, font: DiagramFont, style: DiagramTextStyle) -> CGFloat {
        let regular = style.contains(.monospaced) ? font.makeMonospacedCoreTextFont() : font.makeCoreTextFont()
        var traits: CTFontSymbolicTraits = []
        if style.contains(.bold) { traits.insert(.traitBold) }
        if style.contains(.italic) { traits.insert(.traitItalic) }
        let coreTextFont = traits.isEmpty ? regular : CTFontCreateCopyWithSymbolicTraits(regular, font.size, nil, traits, traits) ?? regular
        if text.utf8.allSatisfy({ byte in byte >= 32 && byte <= 126 }) {
            let characters = text.utf8.map { byte in UniChar(byte) }
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            var advances = [CGSize](repeating: .zero, count: characters.count)
            CTFontGetGlyphsForCharacters(coreTextFont, characters, &glyphs, characters.count)
            CTFontGetAdvancesForGlyphs(coreTextFont, .horizontal, glyphs, &advances, glyphs.count)
            var width: CGFloat = 0
            for advance in advances { width += advance.width }
            return width
        }
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: coreTextFont]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func testAMeasurerIsTriviallyCopyable() {
        XCTAssertTrue(_isPOD(CoreTextDiagramTextMeasurer.self))
        XCTAssertTrue(_isPOD(DiagramFontFace.self))
        XCTAssertTrue(_isPOD(DiagramFontAdvances.self))
    }

    func testWidthsFromBytesAreTheStringWidthsToTheBit() {
        let fonts = [Self.font, DiagramFont(postScriptName: nil, size: 13.7), DiagramFont(postScriptName: "Helvetica", size: 17.3)]
        let styles: [DiagramTextStyle] = [[], .bold, .italic, .monospaced, [.bold, .italic]]
        for font in fonts {
            for style in styles {
                let measurer = CoreTextDiagramTextMeasurer(font: font, isBold: style.contains(.bold), isItalic: style.contains(.italic),
                                                           isMonospaced: style.contains(.monospaced))
                let plain = CoreTextDiagramTextMeasurer(font: font)
                for text in Self.texts {
                    let expected = referenceWidth(of: text, font: font, style: style).bitPattern
                    XCTAssertEqual(measurer.width(of: text).bitPattern, expected, "\(text) at \(font.size) in \(style)")
                    let fromBytes = Array(text.utf8).withUnsafeBufferPointer { bytes in plain.width(ofUTF8: bytes, style: style) }
                    XCTAssertEqual(fromBytes.bitPattern, expected, "\(text) from bytes at \(font.size) in \(style)")
                }
            }
        }
    }

    func testAFacePastTheRegistrysRoomMeasuresAlike() {
        let registered = CoreTextDiagramTextMeasurer(font: Self.font, isBold: true)
        let unregistered = DiagramFontFace(index: .unregistered, name: registered.face.name)
        XCTAssertNil(unregistered.advances)
        for text in Self.texts {
            let width = Array(text.utf8).withUnsafeBufferPointer { bytes in unregistered.width(ofUTF8: bytes) }
            XCTAssertEqual(width.bitPattern, registered.width(of: text).bitPattern, text)
        }
    }

    func testMeasurersAtAnotherSizeOrEmphasisAreTheFontsMadeForThem() {
        let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: "Helvetica", size: 12))
        let resized = measurer.resized(to: 20)
        XCTAssertEqual(resized.diagramFont, DiagramFont(postScriptName: "Helvetica", size: 20))
        XCTAssertEqual(resized.lineHeight, 30)
        let bold = measurer.adding(.bold)
        XCTAssertTrue(bold.isBold)
        XCTAssertFalse(bold.isItalic)
        XCTAssertEqual(bold.face, CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: "Helvetica", size: 12), isBold: true).face)
        XCTAssertEqual(bold.adding(.bold).face, bold.face, "an emphasis it has is not added again")
    }

    /// Every face the typography makes is checked for exact sums, and where its table says so, sums of its advances in
    /// any order are the same to the bit; Pele's 16 points, and the sizes made from it, are such faces.
    func testExactlySummableFacesSumAlikeInAnyOrder() {
        let typography = DiagramTypography(font: Self.font)
        let measurers = [typography.nodeText, typography.edgeText, typography.boldNodeText, typography.smallText, typography.rowText,
                         typography.axisText, typography.boldEdgeText, typography.boldRowText, typography.monospacedEdgeText,
                         typography.monospacedAxisText, typography.italicEdgeText]
        var generator: UInt64 = 0x5EED_A0A0
        for measurer in measurers {
            guard let advances = measurer.printableASCIIAdvances else { return XCTFail("a registered face has advances") }
            XCTAssertTrue(advances.isExactlySummable, "\(measurer.fontSize) points in \(measurer.face.name.style)")
            for _ in 0..<200 {
                var bytes: [UInt8] = []
                for _ in 0..<64 {
                    generator = generator &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    bytes.append(UInt8(32 + (generator >> 33) % 95))
                }
                let forward = advances.width(continuing: 0, over: bytes)
                let backward = advances.width(continuing: 0, over: bytes.reversed())
                let halves = advances.width(continuing: 0, over: bytes[..<32]) + advances.width(continuing: 0, over: bytes[32...])
                XCTAssertEqual(forward.bitPattern, backward.bitPattern)
                XCTAssertEqual(forward.bitPattern, halves.bitPattern)
            }
        }
    }

    func testTheExactnessCheckRefusesLongFractionsLargeAndNegativeAdvances() {
        let table = UnsafeMutablePointer<CGFloat>.allocate(capacity: 256)
        defer { table.deallocate() }
        table.initialize(repeating: 0, count: 256)
        table[65] = 9.0625
        XCTAssertTrue(DiagramFontFaceRegistry.isExactlySummable(UnsafePointer(table)))
        for inexact: CGFloat in [0.1, 1_024, -1, 1.0 / 3, 1 + 1.0 / 2_097_152] {
            table[66] = inexact
            XCTAssertFalse(DiagramFontFaceRegistry.isExactlySummable(UnsafePointer(table)), "\(inexact)")
        }
    }

    /// Filling the cache past its room empties it: the first text is no longer kept, and measured again it has its width.
    func testTheLineWidthCacheLetsItsTextsGoWhenFullAndMeasuresThemAgainAlike() {
        let measurer = CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 11.25))
        let first = "«first» text"
        let firstWidth = measurer.width(of: first)
        let kept = Array(first.utf8).withUnsafeBufferPointer { bytes in DiagramLineWidthCache.shared.contains(bytes, face: measurer.face.index) }
        XCTAssertTrue(kept)
        for index in 0..<6_000 { _ = measurer.width(of: "«\(index)»") }
        let stillKept = Array(first.utf8).withUnsafeBufferPointer { bytes in DiagramLineWidthCache.shared.contains(bytes, face: measurer.face.index) }
        XCTAssertFalse(stillKept)
        XCTAssertEqual(measurer.width(of: first).bitPattern, firstWidth.bitPattern)
        XCTAssertEqual(firstWidth.bitPattern, referenceWidth(of: first, font: DiagramFont(postScriptName: nil, size: 11.25), style: []).bitPattern)
    }

    func testTextLongerThanTheKeptKeysIsMeasuredWithoutBeingKept() {
        let measurer = CoreTextDiagramTextMeasurer(font: Self.font)
        let long = String(repeating: "«long» ", count: 60)
        XCTAssertEqual(measurer.width(of: long).bitPattern, referenceWidth(of: long, font: Self.font, style: []).bitPattern)
        let kept = Array(long.utf8).withUnsafeBufferPointer { bytes in DiagramLineWidthCache.shared.contains(bytes, face: measurer.face.index) }
        XCTAssertFalse(kept)
    }
}
