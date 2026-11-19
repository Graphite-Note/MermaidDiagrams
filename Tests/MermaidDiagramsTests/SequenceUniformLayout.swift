/**
 * File: SequenceUniformLayout.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Lays a sequence diagram out with uniform-width text for tests, and reads its headers, footers and
 *              lifelines.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Lays a sequence diagram out with uniform-width text: participants 8 points a character at 16 points, messages
/// 7 points a character at 14, so that what a test asserts does not depend on installed fonts.
enum SequenceUniformLayout {
    static let participantCharacterWidth: CGFloat = 8
    static let messageCharacterWidth: CGFloat = 7

    static func layout(_ source: String) throws -> SequenceLayout {
        try SequenceLayoutEngine.layout(SequenceReading.sequence(source), participantText: UniformWidthTextMeasurer(),
                                        messageText: UniformWidthTextMeasurer(characterWidth: messageCharacterWidth, fontSize: 14, lineHeight: 21),
                                        font: UniformWidthLayout.font)
    }
}

extension SequenceLayout {
    /// The participants above the lifelines, in order: one per lifeline.
    var headers: [SequenceLayoutParticipant] {
        Array(participants.prefix(lifelines.count))
    }

    /// The participants below the lifelines, in order: those not destroyed.
    var footers: [SequenceLayoutParticipant] {
        Array(participants.dropFirst(lifelines.count))
    }

    /// Each lifeline's x, in the participants' order.
    var lifelineXs: [CGFloat] {
        lifelines.map(\.x)
    }
}

extension DiagramPath {
    /// The x and y the path ends at.
    var end: CGPoint {
        switch segments.last {
        case .line(let end): end
        case .curve(let end, _, _): end
        case nil: start
        }
    }
}
