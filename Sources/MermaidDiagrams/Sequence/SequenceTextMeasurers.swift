/**
 * File: SequenceTextMeasurers.swift
 * ---------------------------------
 * Layer: Core
 * Description: The text sizes a sequence diagram measures in, Pele's, and the bold of the smallest for block keywords.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 23/11/2026
 */

import CoreGraphics

/// The three text sizes of a sequence diagram, Pele's: participants in the note's size; messages, notes and block
/// texts seven eighths of it; the keywords in block tabs and the message numbers three quarters of it, the keywords
/// bold (sequence/render.ts measures `frame.kind` with `Style.Bold`).
struct SequenceTextMeasurers<Measurer: DiagramTextMeasuring> {
    let participantText: Measurer
    let messageText: Measurer
    let smallestText: SequenceScaledTextMeasurer<Measurer>
    /// The smallest size in bold, for the keywords in block tabs; nil measures them as `smallestText` does.
    let boldSmallestText: Measurer?
    /// The gaps and wrapping widths: Pele's, or its tight ones.
    let measurements: SequenceMeasurements

    /// The smallest size as a fraction of the participants', rounded, as in Pele.
    static var smallestTextScale: CGFloat { 0.75 }

    init(participantText: Measurer, messageText: Measurer, boldSmallestText: Measurer? = nil, measurements: SequenceMeasurements = .standard) {
        self.participantText = participantText
        self.measurements = measurements
        self.messageText = messageText
        smallestText = SequenceScaledTextMeasurer(base: messageText, fontSize: Self.smallestTextSize(participantText: participantText))
        self.boldSmallestText = boldSmallestText
    }

    /// The size of the block keywords and the message numbers: three quarters of the participants', rounded.
    static func smallestTextSize(participantText: Measurer) -> CGFloat {
        (participantText.fontSize * smallestTextScale).rounded()
    }

    /// A participant's text, wrapped only in a tight layout.
    func participantBlock(_ label: DiagramLabel) -> DiagramTextBlock {
        block(label, measurer: participantText, wraps: false, width: nil)
    }

    /// A message's, note's or block's text, wrapped at `wrappingWidth` when it is given.
    func messageBlock(_ label: DiagramLabel, wrappingWidth: CGFloat?) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: messageText, maximumWidth: wrappingWidth ?? .greatestFiniteMagnitude)
    }

    /// A message's, note's or block's text as Pele's `text` sets it: wrapped at `width` (the measurements' wrapping width
    /// when nil) when it `wraps` or the layout is tight, and in a tight layout each line still wider than that, or than
    /// 120 points, broken between characters.
    func messageBlock(_ label: DiagramLabel, wraps: Bool, width: CGFloat? = nil) -> DiagramTextBlock {
        block(label, measurer: messageText, wraps: wraps, width: width)
    }

    /// The text unwrapped, as Pele measures a wrapped message's own width (`messageText(raw, false, Infinity)`).
    func unwrappedMessageBlock(_ label: DiagramLabel) -> DiagramTextBlock {
        DiagramTextBlock(label: label, measurer: messageText, maximumWidth: .greatestFiniteMagnitude)
    }

    private func block(_ label: DiagramLabel, measurer: Measurer, wraps: Bool, width: CGFloat?) -> DiagramTextBlock {
        let width = width ?? measurements.wrappingWidth
        guard measurements.isTight else {
            return DiagramTextBlock(label: label, measurer: measurer, maximumWidth: wraps ? width : .greatestFiniteMagnitude)
        }
        return DiagramTextBlock(label: label, measurer: measurer, wrappingWidth: width,
                                breakingWidth: max(SequenceMeasurements.narrowestBreakingWidth, width))
    }

    func smallestBlock(_ text: String) -> DiagramTextBlock {
        DiagramTextBlock(label: DiagramLabel(text), measurer: smallestText, maximumWidth: .greatestFiniteMagnitude)
    }

    /// A block's keyword, measured in the smallest size's bold, as it is drawn.
    func keywordBlock(_ keyword: String) -> DiagramTextBlock {
        guard let boldSmallestText else { return smallestBlock(keyword) }
        return DiagramTextBlock(label: DiagramLabel(keyword), measurer: boldSmallestText, maximumWidth: .greatestFiniteMagnitude)
    }
}

/// Measures text at a smaller size than another measurer, in proportion: a font's advances scale with its size, so
/// the smallest text of a diagram needs no font of its own read. Sizes with their own optical design can differ by a
/// fraction of a point, which the padding around such text absorbs.
struct SequenceScaledTextMeasurer<Base: DiagramTextMeasuring>: DiagramTextMeasuring {
    let base: Base
    let fontSize: CGFloat

    init(base: Base, fontSize: CGFloat) {
        self.base = base
        self.fontSize = fontSize
    }

    var lineHeight: CGFloat {
        (base.lineHeight * fontSize / base.fontSize).rounded()
    }

    func width(of text: String) -> CGFloat {
        base.width(of: text) * fontSize / base.fontSize
    }
}
