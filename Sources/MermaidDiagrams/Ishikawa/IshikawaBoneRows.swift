/**
 * File: IshikawaBoneRows.swift
 * ----------------------------
 * Layer: Core
 * Description: Gives every cause of an Ishikawa category a row of its own, so that no two texts meet, and measures how
 *              far its bones rise from the spine and reach toward the tail, as Pele's arrange does.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

/// A category's causes arranged, as Pele's Ishikawa renderer arranges them. Bones at even depths (from 2, the
/// category's own causes) run level, from the slanted bone above them toward the tail; bones at odd depths slant away
/// from the spine, from the level bone above them. A level bone takes the row nearest the spine and its twigs the rows
/// beyond; a slanted twig takes the row beyond everything that hangs off it. The walk keeps a stack of its own, so a
/// cause may be nested as deep as the text goes.
struct IshikawaCategoryArrangement {
    struct Bone {
        let text: DiagramTextBlock
        let depth: Int
        /// The bone it stands on, or nil for one on the category's own bone.
        let parentIndex: Int?
        /// Its place among its siblings, counted from the spine outward.
        let slot: Int
        let childCount: Int
        /// How far its row is from the spine.
        var rise: CGFloat = 0
        /// Where it meets its parent, measured level from the category's bone: 0 on it, negative toward the tail.
        var meeting: CGFloat = 0
        /// Where its text ends, measured as `meeting`.
        var textEnd: CGFloat = 0
    }

    let label: DiagramTextBlock
    let boxSize: CGSize
    private(set) var bones: [Bone] = []
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
    /// the top down) or below it.
    /// `walk` is the room the walk works in, kept from one category to the next.
    init<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, categoryIndex: Int, isAbove: Bool, measurers: DiagramTextMeasurerSet<Measurer>,
                                         walk: inout IshikawaCategoryWalk) {
        label = Self.textBlock(of: categoryIndex, in: diagram, measurer: measurers.regular, maximumWidth: 180)
        boxSize = CGSize(width: label.size.width + 2 * Self.boxPaddingAcross, height: label.size.height + 2 * Self.boxPaddingDown)
        bones = walk.bones(of: diagram, categoryIndex: categoryIndex, isAbove: isAbove, measurer: measurers.small)
        var nextRise = Self.firstRow
        for index in walk.rows {
            let height = max(bones[index].text.size.height, measurers.small.lineHeight) + Self.rowGap
            bones[index].rise = nextRise + height / 2
            nextRise += height
        }
        rise = nextRise + Self.boneEnd
        reach = boxSize.width / 2
        for index in bones.indices {
            let bone = bones[index]
            let parent = bone.parentIndex.map { parentIndex in bones[parentIndex] }
            if bone.depth % 2 == 0 {
                bones[index].meeting = parent?.meeting ?? 0
                bones[index].textEnd = bones[index].meeting - (bone.childCount > 0 ? CGFloat(bone.childCount + 1) * Self.twigStep : Self.stub) - Self.textGap
            } else if let parent {
                // Twigs stand along their level bone, the one nearest the spine nearest the tail.
                bones[index].meeting = parent.meeting - CGFloat(parent.childCount - bone.slot) * Self.twigStep
                bones[index].textEnd = bones[index].meeting - Self.textGap
            }
            reach = max(reach, bone.text.size.width - bones[index].textEnd)
        }
    }

    /// Node `index`'s text measured, as plain text, from the diagram's bytes.
    static func textBlock(of index: Int, in diagram: IshikawaDiagram, measurer: some DiagramTextMeasuring, maximumWidth: CGFloat) -> DiagramTextBlock {
        diagram.withText(of: index) { text in
            DiagramTextBlock(label: DiagramLabelDecoder.label(fromUTF8: text, form: .plain), measurer: measurer, maximumWidth: maximumWidth)
        }
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
    /// The order the last category's rows go out from the spine: a level bone's row as it is reached, a slanted twig's
    /// after everything that hangs off it.
    private(set) var rows: [Int] = []

    /// `categoryIndex`'s causes as bones, in the order they are made, and their rows in `rows`.
    mutating func bones(of diagram: IshikawaDiagram, categoryIndex: Int, isAbove: Bool,
                        measurer: some DiagramTextMeasuring) -> [IshikawaCategoryArrangement.Bone] {
        typealias Bone = IshikawaCategoryArrangement.Bone
        var bones: [Bone] = []
        bones.reserveCapacity(diagram.subtreeEnd(of: categoryIndex) - categoryIndex - 1)
        stack.removeAll(keepingCapacity: true)
        rows.removeAll(keepingCapacity: true)
        push(diagram.childIndices(of: categoryIndex), depth: 2, parentIndex: -1, isAbove: isAbove)
        while var frame = stack.popLast() {
            if frame.boneIndex >= 0 {
                rows.append(Int(frame.boneIndex))
                continue
            }
            let nodeIndex = Int(frame.nodeIndex)
            let index = bones.count
            bones.append(Bone(text: IshikawaCategoryArrangement.textBlock(of: nodeIndex, in: diagram, measurer: measurer, maximumWidth: 200),
                              depth: Int(frame.depth), parentIndex: frame.parentIndex < 0 ? nil : Int(frame.parentIndex), slot: Int(frame.slot),
                              childCount: diagram.childCount(of: nodeIndex)))
            if frame.depth % 2 == 0 {
                rows.append(index)
            } else {
                frame.boneIndex = Int32(index)
                stack.append(frame)
            }
            push(diagram.childIndices(of: nodeIndex), depth: frame.depth + 1, parentIndex: Int32(index), isAbove: isAbove)
        }
        return bones
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
