/**
 * File: DiagramTextFittingTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Fitting a line of text into a width as Pele's fit-text does: shrinking by whole points, then cutting.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import XCTest
@testable import MermaidDiagrams

final class DiagramTextFittingTests: XCTestCase {
    /// Every character is half the font size wide, so a text of n characters is n times 8 points wide at 16.
    private let measurer = UniformWidthTextMeasurer(characterWidth: 8, fontSize: 16, lineHeight: 24)

    private func fit(_ text: String, _ width: CGFloat, size: CGFloat = 16, least: CGFloat = 8) -> DiagramFittedText? {
        DiagramTextFitting.fitted(text, maximumWidth: width, fontSize: size, minimumFontSize: least, measurer: measurer)
    }

    func testTextThatFitsKeepsItsSize() {
        XCTAssertEqual(fit("abcd", 32), DiagramFittedText(text: "abcd", fontSize: 16, width: 32))
        XCTAssertEqual(fit("abcd", 100, size: 14)?.width, 28)
    }

    func testTextThatDoesNotFitShrinksByWholePointsToTheLargestSizeThatDoes() {
        // Ten characters are 5 points each at size 10: 50 wide; 80 points at 16 is too wide for 55.
        XCTAssertEqual(fit("abcdefghij", 55), DiagramFittedText(text: "abcdefghij", fontSize: 11, width: 55))
        XCTAssertEqual(fit("abcdefghij", 54)?.fontSize, 10)
        XCTAssertEqual(fit("abcdefghij", 40)?.fontSize, 8)
    }

    func testTextThatDoesNotFitAtTheSmallestSizeIsCutAndEndsInAnEllipsis() {
        // At 8 points a character is 4 wide: 20 points hold four characters and the ellipsis.
        let cut = fit("abcdefghij", 20)
        XCTAssertEqual(cut, DiagramFittedText(text: "abcd\u{2026}", fontSize: 8, width: 20))
        XCTAssertEqual(fit("ab cdefghij", 20)?.text, "ab c\u{2026}")
        XCTAssertEqual(fit("ab  defghij", 20)?.text, "ab\u{2026}", "A space before the cut is trimmed")
    }

    func testNothingFitsWhenNoRoomIsLeftOrNotEvenOneCharacterFits() {
        XCTAssertNil(fit("", 100))
        XCTAssertNil(fit("abc", 0))
        XCTAssertNil(fit("abc", -5))
        XCTAssertNil(fit("abcdefghij", 7))
        XCTAssertEqual(fit("abcdefghij", 8)?.text, "a\u{2026}")
    }

    func testAnEnormousTextIsCutInSteps() {
        let started = Date()
        let cut = fit(String(repeating: "x", count: 50_000), 100)
        XCTAssertEqual(cut?.text.count, 25, "Twenty-four characters of 4 points and the ellipsis")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    /// Core Text draws the system font wider at small sizes than its width at 16 points scaled down (it tracks it out), so a
    /// text shrunk or cut to fit is measured in the font at the size it is drawn at, and is no wider than its room when drawn.
    func testCoreTextTextIsMeasuredAtTheSizeItIsDrawnAt() throws {
        let font = DiagramFont(postScriptName: nil, size: 16)
        let measurer = CoreTextDiagramTextMeasurer(font: font)
        let text = "Destination Port and more"
        let proportional = measurer.width(of: text) * 8 / 16
        let drawn = CoreTextDiagramTextMeasurer(font: font.resized(to: 8)).width(of: text)
        XCTAssertGreaterThan(drawn, proportional * 1.03, "The system font is wider at 8 points than in proportion")
        for room in [proportional, proportional + 2, (proportional + drawn) / 2, drawn, 80, 140] {
            let fitted = try XCTUnwrap(DiagramTextFitting.fitted(text, maximumWidth: room, fontSize: 14, minimumFontSize: 8, measurer: measurer))
            let width = CoreTextDiagramTextMeasurer(font: font.resized(to: fitted.fontSize)).width(of: fitted.text)
            XCTAssertEqual(fitted.width, width, accuracy: 1e-9, "\(room)")
            XCTAssertLessThanOrEqual(width, room, "\(room)")
        }
        let bold = CoreTextDiagramTextMeasurer(font: font, isBold: true)
        XCTAssertEqual(DiagramTextFitting.width(of: text, atFontSize: 9, measurer: bold),
                       CoreTextDiagramTextMeasurer(font: font.resized(to: 9), isBold: true).width(of: text), accuracy: 1e-9, "A bold measurer stays bold")
    }

    func testABlockIsOneLineOfTheFittedSizeAndLineHeight() {
        let block = fit("abcdefghij", 55)?.block
        XCTAssertEqual(block?.lines, ["abcdefghij"])
        XCTAssertEqual(block?.fontSize, 11)
        XCTAssertEqual(block?.lineHeight, 17, "One and a half times the size, rounded")
        XCTAssertEqual(block?.size.width, 55)
        XCTAssertEqual(DiagramTextFitting.block(of: "ab", fontSize: 8, measurer: measurer).size.width, 8)
        XCTAssertEqual(DiagramTextFitting.width(of: "ab", atFontSize: 32, measurer: measurer), 32)
    }
}
