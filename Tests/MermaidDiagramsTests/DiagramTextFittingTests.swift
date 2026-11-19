/**
 * File: DiagramTextFittingTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Fitting a line of text into a width as Pele's fit-text does: shrinking by whole points, then cutting.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
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
