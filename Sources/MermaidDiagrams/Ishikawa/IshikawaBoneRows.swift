/**
 * File: IshikawaBoneRows.swift
 * ----------------------------
 * Layer: Core
 * Description: Gives every cause of an Ishikawa category a row of its own, so that no two texts meet, and measures how
 *              far its bones rise from the spine and reach toward the tail, as Pele's arrange does.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A category's causes arranged, as Pele's Ishikawa renderer arranges them. Bones at even depths (from 2, the
/// category's own causes) run level, from the slanted bone above them toward the tail; bones at odd depths slant away
/// from the spine, from the level bone above them. A level bone takes the row nearest the spine and its twigs the rows
/// beyond; a slanted twig takes the row beyond everything that hangs off it. The walk keeps a stack of its own, so a
/// cause may be nested as deep as the text goes.
struct IshikawaCategoryArrangement {
    struct Bone {
        let text: DiagramMeasuredText
        let depth: Int32
        /// The bone it stands on, as an index of the category's own bones, or -1 for one on the category's own bone.
        let parentIndex: Int32
        /// Its place among its siblings, counted from the spine outward.
        let slot: Int32
        let childCount: Int32
        /// How far its row is from the spine.
        var rise: CGFloat = 0
        /// Where it meets its parent, measured level from the category's bone: 0 on it, negative toward the tail.
        var meeting: CGFloat = 0
        /// Where its text ends, measured as `meeting`.
        var textEnd: CGFloat = 0
    }

    let label: DiagramMeasuredText
    let boxSize: CGSize
    /// The category's bones: `bones[firstBone..<firstBone + boneCount]` of the list every category's are in.
    let firstBone: Int
    let boneCount: Int
    /// The length of the category's bone, as distance from the spine.
    var rise: CGFloat
    /// How far its causes reach toward the tail, measured level from its bone.
    private(set) var reach: CGFloat

    static let firstRow: CGFloat = 14
    static let rowGap: CGFloat = 6
    static let boneEnd: CGFloat = 8
    static let twigStep: CGFloat = 22
    static let stub: CGFloat = 18
    static let textGap: CGFloat = 5
    static let boxPaddingAcross: CGFloat = 10
    static let boxPaddingDown: CGFloat = 5

    /// `categoryIndex`'s causes arranged above the spine (`isAbove`, the first cause farthest out so that they read from
    /// the top down) or below it, its bones appended to `bones` and its texts measured into `texts`. `walk` is the room
    /// the walk works in, kept from one category to the next.
    init<Measurer>(_ diagram: IshikawaDiagram, categoryIndex: Int, isAbove: Bool, measurers: IshikawaMeasurers<Measurer>, source: UnsafeBufferPointer<UInt8>,
                   bones: inout [Bone], texts: inout DiagramMeasuredLines, walk: inout IshikawaCategoryWalk) {
        label = measurers.measure(categoryIndex, of: diagram, source: source, measurer: measurers.regular, maximumWidth: 180, into: &texts)
        boxSize = CGSize(width: label.width + 2 * Self.boxPaddingAcross, height: label.height + 2 * Self.boxPaddingDown)
        firstBone = bones.count
        walk.addBones(of: diagram, categoryIndex: categoryIndex, isAbove: isAbove, measurers: measurers, source: source, to: &bones, texts: &texts)
        boneCount = bones.count - firstBone
        var nextRise = Self.firstRow
        for index in walk.rows {
            let height = max(bones[firstBone + index].text.height, measurers.small.singleLineHeight) + Self.rowGap
            bones[firstBone + index].rise = nextRise + height / 2
            nextRise += height
        }
        rise = nextRise + Self.boneEnd
        reach = boxSize.width / 2
        for index in firstBone..<bones.count {
            let bone = bones[index]
            if bone.depth % 2 == 0 {
                let parentMeeting = bone.parentIndex < 0 ? 0 : bones[firstBone + Int(bone.parentIndex)].meeting
                bones[index].meeting = parentMeeting
                bones[index].textEnd = parentMeeting - (bone.childCount > 0 ? CGFloat(bone.childCount + 1) * Self.twigStep : Self.stub) - Self.textGap
            } else if bone.parentIndex >= 0 {
                let parent = bones[firstBone + Int(bone.parentIndex)]
                // Twigs stand along their level bone, the one nearest the spine nearest the tail.
                bones[index].meeting = parent.meeting - CGFloat(parent.childCount - bone.slot) * Self.twigStep
                bones[index].textEnd = bones[index].meeting - Self.textGap
            }
            reach = max(reach, bone.text.width - bones[index].textEnd)
        }
    }
}

/// The three measurers of an Ishikawa diagram's fishbone, as the flat measuring reads them: the bold effect, the
/// regular categories and the small causes.
struct IshikawaMeasurers<Measurer: DiagramTextMeasuring> {
    let bold: DiagramFlatMeasurer<Measurer>
    let regular: DiagramFlatMeasurer<Measurer>
    let small: DiagramFlatMeasurer<Measurer>

    init(_ measurers: DiagramTextMeasurerSet<Measurer>) {
        bold = DiagramFlatMeasurer(measurers.bold)
        regular = DiagramFlatMeasurer(measurers.regular)
        small = DiagramFlatMeasurer(measurers.small)
    }

    /// Node `index`'s text measured, as plain text, from the diagram's bytes, as a block of its decoded label measures it.
    func measure(_ index: Int, of diagram: IshikawaDiagram, source: UnsafeBufferPointer<UInt8>, measurer: DiagramFlatMeasurer<Measurer>,
                 maximumWidth: CGFloat, into texts: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let record = diagram.records[index]
        return DiagramFlatTextMeasuring.measure(source, MermaidTextRange(start: Int(record.textStart), end: Int(record.textEnd)), form: .plain,
                                                measurer: measurer, maximumWidth: maximumWidth, into: &texts)
    }
}

/// The walk over a category's causes, its stack and rows kept from one category to the next.
struct IshikawaCategoryWalk {
    private struct Frame {
        var nodeIndex: Int32
        var depth: Int32
        var parentIndex: Int32
        var slot: Int32
        var boneIndex: Int32
    }

    private var stack: [Frame] = []
    /// The order the last category's rows go out from the spine, as indexes of its bones: a level bone's row as it is
    /// reached, a slanted twig's after everything that hangs off it.
    private(set) var rows: [Int] = []

    /// `categoryIndex`'s causes as bones, appended to `bones` in the order they are made, and their rows in `rows`.
    mutating func addBones<Measurer>(of diagram: IshikawaDiagram, categoryIndex: Int, isAbove: Bool, measurers: IshikawaMeasurers<Measurer>,
                                     source: UnsafeBufferPointer<UInt8>, to bones: inout [IshikawaCategoryArrangement.Bone],
                                     texts: inout DiagramMeasuredLines) {
        let firstBone = bones.count
        bones.reserveCapacity(firstBone + diagram.subtreeEnd(of: categoryIndex) - categoryIndex - 1)
        stack.removeAll(keepingCapacity: true)
        rows.removeAll(keepingCapacity: true)
        push(diagram.childIndices(of: categoryIndex), depth: 2, parentIndex: -1, isAbove: isAbove)
        while var frame = stack.popLast() {
            if frame.boneIndex >= 0 {
                rows.append(Int(frame.boneIndex))
                continue
            }
            let nodeIndex = Int(frame.nodeIndex)
            let index = bones.count - firstBone
            let text = measurers.measure(nodeIndex, of: diagram, source: source, measurer: measurers.small, maximumWidth: 200, into: &texts)
            bones.append(IshikawaCategoryArrangement.Bone(text: text, depth: frame.depth, parentIndex: frame.parentIndex, slot: frame.slot,
                                                          childCount: Int32(diagram.childCount(of: nodeIndex))))
            if frame.depth % 2 == 0 {
                rows.append(index)
            } else {
                frame.boneIndex = Int32(index)
                stack.append(frame)
            }
            push(diagram.childIndices(of: nodeIndex), depth: frame.depth + 1, parentIndex: Int32(index), isAbove: isAbove)
        }
    }

    private mutating func push(_ children: ArraySlice<Int32>, depth: Int32, parentIndex: Int32, isAbove: Bool) {
        let first = children.startIndex
        let count = children.count
        for slot in (0..<count).reversed() {
            stack.append(Frame(nodeIndex: children[first + (isAbove ? count - 1 - slot : slot)], depth: depth, parentIndex: parentIndex,
                               slot: Int32(slot), boneIndex: -1))
        }
    }
}
