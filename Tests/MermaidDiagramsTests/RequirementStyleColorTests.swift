/**
 * File: RequirementStyleColorTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Whether a requirement diagram's style declaration holds `color`, found on its bytes, answers as
 *              Foundation's search by characters answers, on random declarations beyond ASCII and kept to it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation
import XCTest
@testable import MermaidDiagrams

final class RequirementStyleColorTests: XCTestCase {
    func testTheColorTestAnswersAsFoundationsSearch() {
        let pieces = ["color", "colo", "c", "co", "olor", "r", "ccolor", "fill", ":", "#f00", " ", "\u{301}", "o\u{301}", "é", "中", "Color", "colour", ","]
        var mutations = GraphTextMutations(seed: 53)
        var holding = 0
        for _ in 0..<30_000 {
            let text = (0..<mutations.below(7)).map { _ in pieces[mutations.below(pieces.count)] }.joined()
            for written in [text, GraphTextMutations.ascii(text)] {
                let expected = written.contains("color")
                XCTAssertEqual(RequirementDiagramBuilder.holdsColor(written), expected, written.debugDescription)
                if expected { holding += 1 }
            }
        }
        XCTAssertGreaterThan(holding, 5_000)
    }
}
