/**
 * File: TextPrototypeRecorder.swift
 * ---------------------------------
 * Layer: Prototype
 * Description: Records, while a source is prepared, every label decoded and every text block measured, so that the
 *              flat text prototype can be timed and checked against them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// The labels decoded and the blocks measured while recording is on. Prototype only.
enum TextPrototypeRecorder {
    struct RecordedBlock {
        let label: DiagramLabel
        let measurer: CoreTextDiagramTextMeasurer
        let maximumWidth: CGFloat
    }

    nonisolated(unsafe) static var isRecording = false
    nonisolated(unsafe) static var decodes: [(rawText: String, form: DiagramLabelDecoder.Form)] = []
    nonisolated(unsafe) static var blocks: [RecordedBlock] = []
    nonisolated(unsafe) static var otherMeasurerBlockCount = 0

    static func recordDecode(rawText: String, form: DiagramLabelDecoder.Form) {
        decodes.append((rawText, form))
    }

    static func recordBlock(label: DiagramLabel, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) {
        if let coreText = measurer as? CoreTextDiagramTextMeasurer {
            blocks.append(RecordedBlock(label: label, measurer: coreText, maximumWidth: maximumWidth))
        } else {
            otherMeasurerBlockCount += 1
        }
    }
}
