/**
 * File: ClassDiagramTextMeasuring.swift
 * -------------------------------------
 * Layer: Core
 * Description: Measures a class diagram's texts from its records into one list of lines: names, labels, notes and
 *              interfaces from their ranges of the source on the flat path where the decoder reads them as written,
 *              the others from their labels, each as its block would be measured; and the lists the measured texts of
 *              the boxes are kept in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The measured texts of a class diagram's boxes: their lines, and each box's annotations and members in a run.
struct ClassDiagramMeasuredTexts {
    var lines = DiagramMeasuredLines()
    var annotations: [DiagramMeasuredText] = []
    var members: [ClassDiagramPlacedMember] = []
}

/// A member's text measured or placed, and how it is drawn.
struct ClassDiagramPlacedMember: Sendable {
    var text: DiagramMeasuredText
    let classifier: ClassDiagramMemberClassifier
}

/// The measurers of a class diagram's texts, made once a layout, with the bytes of its text.
struct ClassDiagramTextMeasuring<Measurer: DiagramTextMeasuring> {
    let names: DiagramFlatMeasurer<Measurer>
    let members: DiagramFlatMeasurer<Measurer>
    let marks: DiagramFlatMeasurer<Measurer>
    let markRowHeight: CGFloat
    /// The bytes of the diagram's text, which the records' ranges index; valid while the measuring lasts.
    let source: UnsafeBufferPointer<UInt8>

    init(_ measurers: ClassDiagramTextMeasurers<Measurer>, source: UnsafeBufferPointer<UInt8>) {
        names = DiagramFlatMeasurer(measurers.names)
        members = DiagramFlatMeasurer(measurers.members)
        marks = DiagramFlatMeasurer(measurers.marks)
        markRowHeight = measurers.markRowHeight
        self.source = source
    }

    /// `text`, measured on its bytes when it is a range read as written, else as its label's block is.
    func measure(_ text: ClassDiagramText, of model: ClassDiagramModel, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                 into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        guard text.isSourceRange else {
            return DiagramFlatTextMeasuring.measure(model.labels[Int(text.labelIndex)], measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        }
        return DiagramFlatTextMeasuring.measure(source, text.range, form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }

    /// The name a class's box shows, as `ClassDiagramClass.displayedName` gives it: its label, its generic type in angle
    /// brackets after its last line; a class labelled by its identifier shows it as written (`DiagramLabel(identifier)`).
    func measureName(ofClassAt index: Int, of model: ClassDiagramModel, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let record = model.classes[index]
        let width = CGFloat.greatestFiniteMagnitude
        guard !record.hasGenericType else {
            let label = model.label(ofClassAt: index)
            var labelLines = label.lines
            let displayed = labelLines.popLast().map { last in DiagramLabel(lines: labelLines + [last + "<" + (model.genericType(ofClassAt: index) ?? "") + ">"]) }
            return DiagramFlatTextMeasuring.measure(displayed ?? label, measurer: names, maximumWidth: width, into: &lines)
        }
        guard record.label.isNone else { return measure(record.label, of: model, measurer: names, maximumWidth: width, into: &lines) }
        guard record.writtenIdentifierIndex < 0 else {
            return DiagramFlatTextMeasuring.measure(DiagramLabel(model.identifier(ofClassAt: index)), measurer: names, maximumWidth: width, into: &lines)
        }
        return DiagramFlatTextMeasuring.measure(writtenLine: source, record.identifier, measurer: names, maximumWidth: width, into: &lines)
    }

    /// An interface of a lollipop end, as `DiagramLabel(name)` measures, wrapped at `maximumWidth`.
    func measureInterface(at index: Int, of model: ClassDiagramModel, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let interface = model.interfaces[index]
        guard interface.isSourceRange else {
            return DiagramFlatTextMeasuring.measure(model.labels[Int(interface.labelIndex)], measurer: members, maximumWidth: maximumWidth, into: &lines)
        }
        return DiagramFlatTextMeasuring.measure(writtenLine: source, interface.range, measurer: members, maximumWidth: maximumWidth, into: &lines)
    }
}
