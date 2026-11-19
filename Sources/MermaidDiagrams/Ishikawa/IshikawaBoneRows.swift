/**
 * File: IshikawaBoneRows.swift
 * ----------------------------
 * Layer: Core
 * Description: Gives every cause of an Ishikawa category a row of its own, so that no two texts meet, and measures how
 *              far its bones rise from the spine and reach toward the tail, as Pele's arrange does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
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
    init<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, categoryIndex: Int, isAbove: Bool, measurers: DiagramTextMeasurerSet<Measurer>) {
        label = DiagramTextBlock(label: DiagramLabelDecoder.label(from: diagram.nodes[categoryIndex].text, form: .plain), measurer: measurers.regular,
                                 maximumWidth: 180)
        boxSize = CGSize(width: label.size.width + 2 * Self.boxPaddingAcross, height: label.size.height + 2 * Self.boxPaddingDown)
        let walked = Self.walk(diagram, categoryIndex: categoryIndex, isAbove: isAbove, measurer: measurers.small)
        bones = walked.bones
        var nextRise = Self.firstRow
        for index in walked.rows {
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

    /// The category's causes as bones, in the order they are made, and the order their rows go out from the spine: a
    /// level bone's row as it is reached, a slanted twig's after everything that hangs off it.
    private static func walk(_ diagram: IshikawaDiagram, categoryIndex: Int, isAbove: Bool,
                             measurer: some DiagramTextMeasuring) -> (bones: [Bone], rows: [Int]) {
        var bones: [Bone] = []
        var rows: [Int] = []
        var stack: [(nodeIndex: Int, depth: Int, parentIndex: Int?, slot: Int, boneIndex: Int?)] = []
        func push(_ children: [Int], depth: Int, parentIndex: Int?) {
            for slot in children.indices.reversed() {
                stack.append((children[isAbove ? children.count - 1 - slot : slot], depth, parentIndex, slot, nil))
            }
        }
        push(diagram.nodes[categoryIndex].childIndices, depth: 2, parentIndex: nil)
        while var frame = stack.popLast() {
            if let boneIndex = frame.boneIndex {
                rows.append(boneIndex)
                continue
            }
            let node = diagram.nodes[frame.nodeIndex]
            let index = bones.count
            bones.append(Bone(text: DiagramTextBlock(label: DiagramLabelDecoder.label(from: node.text, form: .plain), measurer: measurer, maximumWidth: 200),
                              depth: frame.depth, parentIndex: frame.parentIndex, slot: frame.slot, childCount: node.childIndices.count))
            if frame.depth % 2 == 0 {
                rows.append(index)
            } else {
                frame.boneIndex = index
                stack.append(frame)
            }
            push(node.childIndices, depth: frame.depth + 1, parentIndex: index)
        }
        return (bones, rows)
    }
}
