/**
 * File: StateDiagramTextMeasuring.swift
 * -------------------------------------
 * Layer: Core
 * Description: Measures a state diagram's texts from its records: a text read as written from its range of the source,
 *              on the flat path, a decoded one from its label, and a state's name from its first description or its
 *              identifier, each as its block would be measured.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// Measures a state diagram's texts into one list of lines, to the bit as `DiagramTextBlock(label:measurer:maximumWidth:)`
/// measures the labels 0.7.0 read.
struct StateDiagramTextMeasuring<Measurer: DiagramTextMeasuring> {
    /// The bytes of the diagram's text, which the records' ranges index; valid while the measuring lasts.
    let source: UnsafeBufferPointer<UInt8>
    let measurer: DiagramFlatMeasurer<Measurer>

    /// `text`: a range read as written is measured on its bytes (`DiagramFlatTextMeasuring`, which measures them as
    /// decoding them and measuring the block would), a label kept as its block is measured.
    func measure(_ text: StateDiagramText, in model: StateDiagramModel, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        guard text.isSourceRange else {
            return DiagramFlatTextMeasuring.measure(model.labels[Int(text.labelIndex)], measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        }
        return DiagramFlatTextMeasuring.measure(source, text.range, form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }

    /// The name of `state`, as `StateDiagramState.name` gives it: its first description, else its identifier as written
    /// (`DiagramLabel(identifier)`, one line, no markup read), measured on its bytes where it is a range of the text.
    func measureName(of state: Int, in model: StateDiagramModel, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let record = model.states[state]
        if record.descriptionCount > 0 {
            return measure(model.descriptions[Int(record.firstDescription)], in: model, maximumWidth: maximumWidth, into: &lines)
        }
        guard record.isIdentifierInText else {
            return DiagramFlatTextMeasuring.measure(DiagramLabel(model.identifier(of: state)), measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        }
        let range = MermaidTextRange(start: Int(record.identifierStart), end: Int(record.identifierEnd))
        return DiagramFlatTextMeasuring.measure(writtenLine: source, range, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }
}
