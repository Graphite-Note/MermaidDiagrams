/**
 * File: DiagramMeasuredSceneTextWorkload.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Texts taken from the bytes they were written in to a scene, as the benchmark times them: as blocks of
 *              labels decoded from Strings (what most layouts do now) or measured from source ranges and given to the
 *              scene builder as measured texts, each way ending with the scene made and let go.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics

/// Texts as a model holds them, ranges of one byte buffer, taken into a scene in one font at one width: decoded from
/// Strings into labels, measured into blocks and drawn (`sceneFromBlocks`), or measured from the bytes and drawn from the
/// measured lines (`sceneFromMeasuredTexts`). Both give the same scene to the byte (`DiagramSceneMeasuredTextTests`).
@_spi(Benchmark) public struct DiagramMeasuredSceneTextWorkload {
    private let texts: [String]
    private let source: [UInt8]
    private let ranges: [MermaidTextRange]
    private let measurer: CoreTextDiagramTextMeasurer
    private let maximumWidth: CGFloat
    private var lines = DiagramMeasuredLines()
    private static let font = DiagramFont(postScriptName: nil, size: 14)

    public init(texts: [String], font: DiagramFont, maximumWidth: CGFloat) {
        self.texts = texts
        var source: [UInt8] = []
        var ranges: [MermaidTextRange] = []
        for text in texts {
            let start = source.count
            source += Array(text.utf8)
            ranges.append(MermaidTextRange(start: start, end: source.count))
            source.append(UInt8(ascii: "\n"))
        }
        self.source = source
        self.ranges = ranges
        measurer = CoreTextDiagramTextMeasurer(font: font)
        self.maximumWidth = maximumWidth
    }

    /// Each text decoded from its String, measured into a block and drawn; the number of texts the scene holds.
    public func sceneFromBlocks() -> Int {
        var builder = DiagramSceneBuilder()
        for (index, text) in texts.enumerated() {
            let block = DiagramTextBlock(label: DiagramLabelDecoder.label(from: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
            builder.text(block.translated(by: CGVector(dx: CGFloat(index), dy: 0)), .foreground, part: .label)
        }
        return builder.scene(size: CGSize(width: 100, height: 100), font: Self.font).texts.count
    }

    /// Each text measured from its bytes into the workload's lines and drawn from them; the number of texts the scene holds.
    public mutating func sceneFromMeasuredTexts() -> Int {
        lines.removeAll()
        let flat = DiagramFlatMeasurer(measurer)
        var builder = DiagramSceneBuilder()
        source.withUnsafeBufferPointer { source in
            for (index, range) in ranges.enumerated() {
                let measured = DiagramFlatTextMeasuring.measure(source, range, form: .plain, measurer: flat, maximumWidth: maximumWidth, into: &lines)
                builder.text(measured.centered(at: CGPoint(x: CGFloat(index), y: 0)), of: lines, source: source, .foreground, part: .label)
            }
        }
        return builder.scene(size: CGSize(width: 100, height: 100), font: Self.font).texts.count
    }
}
