/**
 * File: ReferenceUserJourneyMeasurement.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's user journey measurement, frozen as main ba176e5 kept it (text blocks, paths and lists in each
 *              placed task), which the flat user journey layout is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A user journey's cards measured as Pele measures them: each task's text wrapped in a column 124 points wide; a word
/// too wide widens every card up to 200 points, past which it is cut. Then the cards' width, their spacing, and the
/// width of the run of cards.
struct ReferenceUserJourneyMeasurement {
    /// The width of a card's text.
    let textWidth: CGFloat
    let taskTexts: [DiagramTextBlock]
    /// The height of every card's text: its tallest task's, at least a line.
    let textHeight: CGFloat

    static let narrowestTextWidth: CGFloat = 124
    static let widestTextWidth: CGFloat = 200

    init(diagram: UserJourneyDiagram, taskText: some DiagramTextMeasuring) {
        var textWidth = Self.narrowestTextWidth
        var taskTexts = diagram.taskRecords.map { task in TimelineTextFitting.wrapped(task.label, measurer: taskText, maximumWidth: textWidth) }
        let widest = taskTexts.map(\.size.width).max() ?? 0
        if widest > textWidth {
            textWidth = min(widest.rounded(.up), Self.widestTextWidth)
            taskTexts = diagram.taskRecords.map { task in TimelineTextFitting.fitted(task.label, measurer: taskText, maximumWidth: textWidth) }
        }
        self.textWidth = textWidth
        self.taskTexts = taskTexts
        textHeight = max(taskText.lineHeight, taskTexts.map(\.size.height).max() ?? 0)
    }

    var cardWidth: CGFloat { textWidth + 2 * UserJourneyGeometry.cardPadding.width }

    /// From one card's left edge to the next one's.
    var cardPitch: CGFloat { cardWidth + UserJourneyGeometry.cardGap }

    /// The width of the run of cards, which the scale spans.
    var plotWidth: CGFloat {
        taskTexts.isEmpty ? 0 : CGFloat(taskTexts.count) * cardPitch - UserJourneyGeometry.cardGap
    }
}
