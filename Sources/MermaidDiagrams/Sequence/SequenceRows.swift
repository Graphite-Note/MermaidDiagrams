/**
 * File: SequenceRows.swift
 * ------------------------
 * Layer: Core
 * Description: Places a sequence diagram's events top to bottom as Pele does while it draws: messages, notes, block
 *              lines and activations each in the next row, created participants at their messages, crosses where
 *              lifelines end.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// Places a sequence diagram's events top to bottom, as Pele does while it draws: each message, note, block line
/// and activation takes the next row under the one before, and the participants are drawn above the first row (a
/// created one beside the message that creates it) and mirrored under the last (but a destroyed one). Coordinates are
/// relative to the first lifeline and the top of the boxes, or of the participants without boxes; the layout moves them
/// onto the page once everything is placed.
struct SequenceRows<Measurer: DiagramTextMeasuring> {
    let diagram: SequenceDiagram
    let columns: SequenceColumns
    let measurers: SequenceTextMeasurers<Measurer>
    private(set) var extents: SequenceExtents
    /// Where the next row starts.
    private(set) var y: CGFloat
    /// Where the participants above the lifelines end, but those created later.
    let headerBottom: CGFloat
    /// For each participant, the top of its box above its lifeline, and where its lifeline starts and ends (nil: at the
    /// last row).
    private(set) var participantTops: [CGFloat]
    private(set) var lifelineStarts: [CGFloat]
    private(set) var lifelineEnds: [CGFloat?]
    /// The centers of the crosses that end destroyed lifelines.
    private(set) var destructions: [CGPoint] = []
    /// For each participant, where each of its open activations started, innermost last.
    private(set) var activationStarts: [[CGFloat]]
    /// For each block, where its frame starts.
    private var frameTops: [CGFloat]
    /// The blocks open now, innermost last.
    private var openFrameIndices: [Int] = []
    /// For each block, its sections so far.
    private var frameSections: [[SequenceLayoutBlockSection]]
    private var frameTextPatches: [[CGRect]]
    /// What is placed, in the order it closes; the layout turns activations and highlights back to front.
    private(set) var activations: [CGRect] = []
    private(set) var highlights: [SequenceLayoutHighlight] = []
    private(set) var blocks: [SequenceLayoutBlock] = []
    var messages: [SequenceLayoutMessage] = []
    private(set) var notes: [SequenceLayoutNote] = []

    init(diagram: SequenceDiagram, columns: SequenceColumns, extents: SequenceExtents, measurers: SequenceTextMeasurers<Measurer>) {
        self.diagram = diagram
        self.columns = columns
        self.extents = extents
        self.measurers = measurers
        let created = Set(diagram.events.compactMap { event -> Int? in
            guard case .message(let message) = event, message.createsTarget else { return nil }
            return message.targetIndex
        })
        let rowHeight = columns.participantSizes.enumerated().filter { index, _ in !created.contains(index) }.map { _, size in size.height }.max() ?? 0
        headerBottom = columns.boxRuns.topRoom + rowHeight
        participantTops = columns.participantSizes.map { size in columns.boxRuns.topRoom + rowHeight - size.height }
        lifelineStarts = Array(repeating: headerBottom, count: diagram.participants.count)
        lifelineEnds = Array(repeating: nil, count: diagram.participants.count)
        y = headerBottom + SequenceSpacing.firstRowGap
        activationStarts = Array(repeating: [], count: diagram.participants.count)
        frameTops = Array(repeating: 0, count: extents.frames.count)
        frameSections = Array(repeating: [], count: extents.frames.count)
        frameTextPatches = frameSections.map { _ in [] }
    }

    /// Places every event, then ends the activations still open under the last row.
    mutating func placeEvents() {
        for (eventIndex, event) in diagram.events.enumerated() {
            switch event {
            case .activationStart(let participantIndex): activationStarts[participantIndex].append(y)
            case .activationEnd(let participantIndex):
                if !activationStarts[participantIndex].isEmpty { y = max(y, endActivation(of: participantIndex, at: y)) }
            case .blockStart: startFrame(extents.frameIndexOfEvent[eventIndex])
            case .blockSection: addSection(to: extents.frameIndexOfEvent[eventIndex])
            case .blockEnd: endFrame(extents.frameIndexOfEvent[eventIndex])
            case .note(let note): placeNote(note, at: eventIndex)
            case .message(let message): placeMessage(message, at: eventIndex)
            case .numbering: continue
            }
        }
        y += SequenceSpacing.lastRowGap
        for participantIndex in diagram.participants.indices {
            while !activationStarts[participantIndex].isEmpty { _ = endActivation(of: participantIndex, at: y) }
        }
    }

    mutating func extend(from left: CGFloat, to right: CGFloat) {
        extents.extend(from: left, to: right)
    }

    mutating func moveDown(to row: CGFloat) {
        y = max(y, row)
    }

    // MARK: Created and destroyed participants

    /// A created participant's box centered on the line of the message that creates it, its lifeline under it.
    mutating func placeCreatedParticipant(_ participantIndex: Int, centeredAt lineY: CGFloat) {
        participantTops[participantIndex] = lineY - columns.participantSizes[participantIndex].height / 2
        lifelineStarts[participantIndex] = participantTops[participantIndex] + columns.participantSizes[participantIndex].height
    }

    /// Ends a destroyed participant's lifeline at a cross under the message line at `lineY`, and moves the next row
    /// below the cross.
    mutating func destroy(_ participantIndex: Int, under lineY: CGFloat) {
        let center = CGPoint(x: columns.centers[participantIndex], y: lineY + SequenceSpacing.destructionDepth)
        lifelineEnds[participantIndex] = center.y
        destructions.append(center)
        moveDown(to: center.y + SequenceSpacing.destructionHalfSize)
    }

    // MARK: Activations

    /// The left side of a participant's activations, or its lifeline when it has none; `extra` counts activations
    /// about to start.
    func leftEdge(of participantIndex: Int, extra: Int = 0) -> CGFloat {
        let center = columns.centers[participantIndex]
        return activationStarts[participantIndex].count + extra > 0 ? center - SequenceSpacing.activationWidth / 2 : center
    }

    /// The right side of a participant's innermost activation, or its lifeline when it has none.
    func rightEdge(of participantIndex: Int, extra: Int = 0) -> CGFloat {
        let depth = activationStarts[participantIndex].count + extra
        let center = columns.centers[participantIndex]
        return depth > 0 ? center + SequenceSpacing.activationWidth / 2 + CGFloat(depth - 1) * SequenceSpacing.activationStep : center
    }

    /// Ends the innermost activation at `end`, at least its minimum height below its start, and returns its bottom.
    private mutating func endActivation(of participantIndex: Int, at end: CGFloat) -> CGFloat {
        guard let start = activationStarts[participantIndex].popLast() else { return end }
        let bottom = max(end, start + SequenceSpacing.activationMinimumHeight)
        let left = columns.centers[participantIndex] - SequenceSpacing.activationWidth / 2
            + CGFloat(activationStarts[participantIndex].count) * SequenceSpacing.activationStep
        extend(from: left, to: left + SequenceSpacing.activationWidth)
        activations.append(CGRect(x: left, y: start, width: SequenceSpacing.activationWidth, height: bottom - start))
        return bottom
    }

    // MARK: Notes

    /// A note under the row before, beside its lifeline past any activation, or over its lifelines.
    private mutating func placeNote(_ note: SequenceNote, at eventIndex: Int) {
        let text = extents.eventTexts[eventIndex]
        let textHeight = text?.size.height ?? 0
        let height = textHeight + 2 * SequenceSpacing.noteVerticalPadding
        let top = y + SequenceSpacing.noteGapAbove
        var left = extents.noteLefts[eventIndex]
        switch note.placement {
        case .rightOf(let participantIndex): left += rightEdge(of: participantIndex) - columns.centers[participantIndex]
        case .leftOf(let participantIndex): left += leftEdge(of: participantIndex) - columns.centers[participantIndex]
        case .over: break
        }
        let frame = CGRect(x: left, y: top, width: extents.noteWidths[eventIndex], height: height)
        extend(from: frame.minX, to: frame.maxX)
        var placedText = text ?? measurers.messageBlock(DiagramLabel(lines: []), wrappingWidth: nil)
        placedText.center = CGPoint(x: frame.midX, y: frame.midY)
        notes.append(SequenceLayoutNote(frame: frame, text: placedText))
        y = frame.maxY
    }

    // MARK: Blocks

    private mutating func startFrame(_ frameIndex: Int?) {
        guard let frameIndex else { return }
        openFrameIndices.append(frameIndex)
        let frame = extents.frames[frameIndex]
        guard frame.kind.keyword != nil else {
            frameTops[frameIndex] = y + SequenceSpacing.highlightGap
            y = frameTops[frameIndex]
            return
        }
        frameTops[frameIndex] = y + SequenceSpacing.frameGap
        let titleHeight = frame.texts.first.flatMap { text in text?.size.height } ?? 0
        y = frameTops[frameIndex] + max(SequenceSpacing.tabHeight, titleHeight + SequenceSpacing.textRoom)
    }

    /// `else`, `and` or `option`: a dashed line across the block, its text under it.
    private mutating func addSection(to frameIndex: Int?) {
        guard let frameIndex else { return }
        let frame = extents.frames[frameIndex]
        let lineY = y + SequenceSpacing.frameGap
        let sectionNumber = frameSections[frameIndex].count + 1
        var text = sectionNumber < frame.texts.count ? frame.texts[sectionNumber] : nil
        if let width = text?.size.width, let height = text?.size.height {
            let center = CGPoint(x: frame.left + SequenceSpacing.frameTextInset + width / 2, y: lineY + SequenceSpacing.textRoom + height / 2)
            text?.center = center
            if let patch = textPatch(around: center, size: CGSize(width: width, height: height)) { frameTextPatches[frameIndex].append(patch) }
        }
        frameSections[frameIndex].append(SequenceLayoutBlockSection(lineY: lineY, text: text, textBackground: nil))
        y += SequenceSpacing.frameGap + (text?.size.height ?? 0)
    }

    private mutating func endFrame(_ frameIndex: Int?) {
        guard let frameIndex else { return }
        let extent = extents.frames[frameIndex]
        let top = frameTops[frameIndex]
        let bottom = y + SequenceSpacing.frameGap
        let frame = CGRect(x: extent.left, y: top, width: extent.right - extent.left, height: bottom - top)
        y = bottom
        openFrameIndices.removeAll { open in open == frameIndex }
        guard var keyword = extent.keyword else {
            if case .highlight(let color) = extent.kind { highlights.append(SequenceLayoutHighlight(frame: frame, color: color)) }
            return
        }
        let tab = CGRect(x: frame.minX, y: top, width: extent.tabWidth, height: SequenceSpacing.tabHeight)
        keyword.center = CGPoint(x: tab.midX, y: tab.midY)
        var title = extent.texts.first ?? nil
        if let size = title?.size {
            let center = CGPoint(x: tab.maxX + SequenceSpacing.frameTextInset + size.width / 2, y: top + max(SequenceSpacing.tabHeight, size.height) / 2)
            title?.center = center
            if let patch = textPatch(around: center, size: size) { frameTextPatches[frameIndex].append(patch) }
        }
        let sections = frameSections[frameIndex].map { section in
            SequenceLayoutBlockSection(lineY: section.lineY, text: section.text, textBackground: section.text.flatMap(backgroundOfBlockText))
        }
        blocks.append(SequenceLayoutBlock(frame: frame, tab: tab, keyword: keyword, title: title, titleBackground: title.flatMap(backgroundOfBlockText),
                                          sections: sections, textPatches: frameTextPatches[frameIndex]))
    }

    // MARK: Colors under texts and lines

    /// The color under a block's text, when no patch is behind it.
    private func backgroundOfBlockText(_ text: DiagramTextBlock) -> SequenceHighlightColor? {
        guard textPatch(around: text.center, size: text.size) == nil else { return nil }
        return colorUnder(from: text.frame.minX, to: text.frame.maxX)
    }

    /// Pele's `fillUnder`: the color of the innermost `rect` open now (nil when it names none), else of the first box
    /// run that holds `left` to `right`, else nil.
    func colorUnder(from left: CGFloat, to right: CGFloat) -> SequenceHighlightColor? {
        for frameIndex in openFrameIndices.reversed() {
            if case .highlight(let color) = extents.frames[frameIndex].kind { return color }
        }
        for run in columns.boxRuns.runs {
            let edges = columns.boxRuns.edges(of: run, centers: columns.centers, sizes: columns.participantSizes)
            if left >= edges.left, right <= edges.right { return diagram.boxes[run.boxIndex].color }
        }
        return nil
    }

    // MARK: Text patches

    /// A patch of the background behind text centered at `center`, when a lifeline runs across the text; nil otherwise.
    func textPatch(around center: CGPoint, size: CGSize) -> CGRect? {
        guard size.width > 0, isCrossedByALifeline(from: center.x - size.width / 2, to: center.x + size.width / 2) else { return nil }
        return CGRect(x: center.x - size.width / 2 - SequenceSpacing.textPatchOutset, y: center.y - size.height / 2 + SequenceSpacing.textPatchInset,
                      width: size.width + 2 * SequenceSpacing.textPatchOutset, height: size.height - 2 * SequenceSpacing.textPatchInset)
    }

    /// Whether a lifeline runs strictly between `left` and `right`, by binary search over the ordered lifelines.
    private func isCrossedByALifeline(from left: CGFloat, to right: CGFloat) -> Bool {
        let centers = columns.centers
        var low = 0
        var high = centers.count
        while low < high {
            let middle = (low + high) / 2
            if centers[middle] <= left { low = middle + 1 } else { high = middle }
        }
        return low < centers.count && centers[low] < right
    }
}
