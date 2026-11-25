/**
 * File: FlowchartTextMeasuring.swift
 * ----------------------------------
 * Layer: Core
 * Description: A flowchart's node and edge texts measured into the blocks its layout keeps: a text written with markup
 *              decoded straight from the bytes it was written in, with no String made; a line without markup, as the
 *              reader left it, written once from its bytes; any other through the model's label.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics

/// Measures a flowchart's texts as `DiagramTextBlock(label: model.label(reference), measurer:, maximumWidth:)` does, to
/// the bit. A `line` reference, nearly every text, is already flat end to end: its bytes are written once into the
/// thread's text storage, measured there and kept by the block the scene draws, so it is measured as before. A `plain` or
/// `markdown` reference into the text read is decoded from its bytes (`DiagramLabelDecoder.label(fromUTF8:form:)`)
/// instead of from a String of them. A reference into the side bytes, or to a label decoded while reading, is the model's.
///
/// Measuring a `line` from its range with `DiagramFlatTextMeasuring` and writing the measured text into a block was
/// timed and is slower here (docs/redesign/scene-flat-text.md): it scans the bytes the reader already classified again,
/// and fills a list of measured lines the block then copies, where the label path writes the bytes once.
struct FlowchartTextMeasuring<Measurer: DiagramTextMeasuring> {
    private let model: FlowchartModel
    private let measurer: Measurer
    private let maximumWidth: CGFloat

    init(model: FlowchartModel, measurer: Measurer, maximumWidth: CGFloat) {
        self.model = model
        self.measurer = measurer
        self.maximumWidth = maximumWidth
    }

    /// The block of the text `reference` stands for, `source` the bytes of the model's text; a block of no line for none.
    func block(of reference: FlowchartLabelReference, source: UnsafeBufferPointer<UInt8>) -> DiagramTextBlock {
        let label: DiagramLabel
        switch reference.kind {
        case .plain where reference.range.start >= 0: label = decoded(reference.range, form: .plain, source: source)
        case .markdown where reference.range.start >= 0: label = decoded(reference.range, form: .markdown, source: source)
        default: label = model.label(reference) ?? DiagramLabel(lines: [])
        }
        return DiagramTextBlock(label: label, measurer: measurer, maximumWidth: maximumWidth)
    }

    /// The label of the text at `range` of `source`, decoded from its bytes.
    private func decoded(_ range: MermaidTextRange, form: DiagramLabelDecoder.Form, source: UnsafeBufferPointer<UInt8>) -> DiagramLabel {
        precondition(range.end <= source.count, "a label's range outside its text")
        return DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: source[range.lowerBound..<range.upperBound]), form: form)
    }
}
