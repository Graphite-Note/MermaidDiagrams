/**
 * File: DiagramFlatTextMeasuringWritten.swift
 * -------------------------------------------
 * Layer: Core
 * Description: Texts a layout measures into its list of lines that are not ranges of its source: a String its model
 *              keeps, measured from the String's bytes and its lines copied into the derived bytes, and a label decoded
 *              already, measured as its block, so that a layout keeps every text it measures in one list.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics

extension DiagramFlatTextMeasuring {
    /// `text`, a String rather than a range of the source (a model's String, a number, a name made up), measured as
    /// `measure(_:_:form:measurer:maximumWidth:into:)` measures the same bytes in the source: the same lines, widths and
    /// size, the lines copied into the derived bytes, since the String's bytes do not outlive the measuring.
    static func measure<Measurer>(written text: String, form: DiagramLabelDecoder.Form, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                  into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        var text = text
        return text.withUTF8 { bytes in
            let measured = measure(bytes, MermaidTextRange(start: 0, end: bytes.count), form: form, measurer: measurer, maximumWidth: maximumWidth,
                                   into: &lines)
            lines.deriveLines(of: measured, source: bytes)
            return measured
        }
    }

    /// `label`, decoded already, measured as `DiagramTextBlock(label:measurer:maximumWidth:)` measures it, its lines and
    /// runs copied into the derived bytes.
    static func measure<Measurer>(_ label: DiagramLabel, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                  into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        copied(DiagramTextBlock(label: label, measurer: measurer.measurer, maximumWidth: maximumWidth), into: &lines)
    }
}
