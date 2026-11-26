/**
 * File: TimelineEquivalence.swift
 * -------------------------------
 * Layer: Tests
 * Description: Compares the flat timeline's model, layout and scene with 0.7.0's frozen ones, and makes the texts the
 *              timeline equivalence tests read: hostile, random and changed timelines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

enum TimelineEquivalence {
    /// The flat model and the frozen one of `source`, both read from its front end's text; nil when it is no timeline.
    /// The frozen one takes the front matter's title as the reader gives it to the flat one.
    static func models(_ source: String) -> (model: TimelineDiagram, reference: ReferenceTimelineDiagram)? {
        guard case .timeline(let model) = try? MermaidDiagramReader.read(source, limits: .standard),
              let frontEnd = try? MermaidFrontEnd.read(source),
              var reference = try? ReferenceTimelineParser.parse(MermaidTextCursor(frontEnd), limits: .standard) else { return nil }
        reference.title = model.title
        return (model, reference)
    }

    static func same(_ model: TimelineDiagram, _ reference: ReferenceTimelineDiagram) -> Bool {
        let periods = model.periods
        return model.seriesColors == reference.seriesColors && model.direction == reference.direction && model.title == reference.title
            && model.accessibilityTitle == reference.accessibilityTitle && model.accessibilityDescription == reference.accessibilityDescription
            && model.sections == reference.sections && periods.count == reference.periods.count
            && zip(periods, reference.periods).allSatisfy { period, expected in
                period.label == expected.label && period.events == expected.events && period.sectionIndex == expected.sectionIndex
            }
    }

    static func same(_ layout: TimelineLayout, _ reference: ReferenceTimelineLayout) -> Bool {
        let sections = layout.sections
        let periods = layout.periods
        return layout.size == reference.size && layout.font == reference.font && layout.direction == reference.direction
            && layout.seriesColors == reference.seriesColors && layout.axis == reference.axis && layout.axisArrow == reference.axisArrow
            && layout.title == reference.title && sections.count == reference.sections.count && periods.count == reference.periods.count
            && zip(sections, reference.sections).allSatisfy { section, expected in
                section.sectionIndex == expected.sectionIndex && section.frame == expected.frame && section.text == expected.text
            }
            && zip(periods, reference.periods).allSatisfy { period, expected in
                period.color == expected.color && period.frame == expected.frame && period.text == expected.text && period.dot == expected.dot
                    && period.connectors == expected.connectors && period.events.count == expected.events.count
                    && zip(period.events, expected.events).allSatisfy { event, expectedEvent in
                        event.frame == expectedEvent.frame && event.text == expectedEvent.text
                    }
            }
    }

    /// The scenes of the two layouts, compared as their SVG documents, which write every element, number and text.
    static func sameScene(_ layout: TimelineLayout, _ reference: ReferenceTimelineLayout) -> Bool {
        let writer = DiagramSVGWriter()
        return writer.document(of: DiagramScene(layout: layout), diagramType: "timeline")
            == writer.document(of: ReferenceTimelineSceneRecording.scene(reference), diagramType: "timeline")
    }

    /// Timelines that stress the records: many periods and events, long and many-lined texts, every kind of text.
    static func hostileTexts() -> [String] {
        let many = "timeline\n" + (0..<400).map { index in "  section s\(index % 7)\n  p\(index) : e\(index) : f" }.joined(separator: "\n")
        let longLine = "timeline\n  " + String(repeating: "word ", count: 4_000) + ": " + String(repeating: "x", count: 3_000)
        let manyEvents = "timeline\n  2004\n" + String(repeating: "    : event <br> with a break\n", count: 600)
        let breaks = "timeline TD\n  " + String(repeating: "a<br>", count: 500) + " : " + String(repeating: "&amp;<br/>", count: 300)
        let wideWords = "timeline\n  " + String(repeating: "W", count: 900) + " : " + String(repeating: "é", count: 400) + "\n  section " + String(repeating: "S", count: 700)
        return [many, longLine, manyEvents, breaks, wideWords]
    }

    /// Random timelines of the texts a reader decides on, ASCII and not, with entities, breaks, markup and white space.
    static func randomTexts(count: Int, seed: UInt64) -> [String] {
        let texts = ["2004", " 2004 ", "\t2005\u{0B}", "Facebook", "  Google  ", "a<br>b", "&amp;", "#9829;", "é", " \u{A0}x\u{A0} ", "\u{3000}y", "z\u{85}",
                     "\u{FEFF}w", "", "  ", "a very long period text that wraps over several lines of its column", String(repeating: "Z", count: 60),
                     "*em* and **strong**", "<b>tag</b>", "x\\ny", "Ünïcödé wörds hère", "a\u{0C}b", "tab\there", "1<br/>2<br />3"]
        var state = seed
        func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        return (0..<count).map { _ in
            var lines = ["timeline" + [" LR", " TD", "", ""][below(4)]]
            for _ in 0..<(1 + below(10)) {
                switch below(7) {
                case 0: lines.append("title " + texts[below(texts.count)])
                case 1: lines.append("section " + texts[below(texts.count)])
                case 2, 3: lines.append("    : " + texts[below(texts.count)])
                default: lines.append(texts[below(texts.count)] + (0..<below(4)).map { _ in " : " + texts[below(texts.count)] }.joined())
                }
            }
            return lines.joined(separator: "\n")
        }
    }
}

/// Counts, across threads, the results that match what one thread made alone and those that do not.
final class TrackFlatThreadTally: @unchecked Sendable {
    private let lock = NSLock()
    private var matches = 0
    private var differences = 0

    func record(_ isMatch: Bool) {
        lock.lock()
        if isMatch { matches += 1 } else { differences += 1 }
        lock.unlock()
    }

    var matchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return matches
    }

    var differenceCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return differences
    }
}
