/**
 * File: ReferenceIshikawaLayout.swift
 * -----------------------------------
 * Layer: Tests
 * Description: 0.7.0's Ishikawa fishbone layout, frozen as main ba176e5 laid it out: every text a block of its decoded
 *              label, each category with lists of its own bones and causes, moved into place one category at a time,
 *              which the layout of flat records is compared with.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// 0.7.0's `IshikawaLayout` across: its categories and head as it kept them.
struct ReferenceIshikawaLayout: Equatable {
    let size: CGSize
    let font: DiagramFont
    let title: DiagramTextBlock?
    let spine: DiagramPath?
    let spineArrow: DiagramEdgeMark?
    let categories: [IshikawaLayoutCategory]
    let head: IshikawaLayoutHead?
    let outlineEntries: [IshikawaLayoutOutlineEntry]
    let outlineConnectors: [DiagramPath]

    /// What the layout of flat records gives when read.
    init(_ layout: IshikawaLayout) {
        self.init(size: layout.size, font: layout.font, title: layout.title, spine: layout.spine, spineArrow: layout.spineArrow,
                  categories: layout.categories, head: layout.head, outlineEntries: layout.outlineEntries, outlineConnectors: layout.outlineConnectors)
    }

    init(size: CGSize, font: DiagramFont, title: DiagramTextBlock?, spine: DiagramPath?, spineArrow: DiagramEdgeMark?, categories: [IshikawaLayoutCategory],
         head: IshikawaLayoutHead?, outlineEntries: [IshikawaLayoutOutlineEntry], outlineConnectors: [DiagramPath]) {
        self.size = size
        self.font = font
        self.title = title
        self.spine = spine
        self.spineArrow = spineArrow
        self.categories = categories
        self.head = head
        self.outlineEntries = outlineEntries
        self.outlineConnectors = outlineConnectors
    }
}

enum ReferenceIshikawaLayoutEngine {
    static let slant: CGFloat = 0.5
    static let slantLength = (slant * slant + 1).squareRoot()
    static let pairGap: CGFloat = 26
    static let headGap: CGFloat = 34
    static let tail: CGFloat = 28
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// Below this width a diagram that does not fit turns to run down, as Pele's breakpoint.
    static let breakpoint: CGFloat = 640

    /// The fishbone, its head's left end at the origin on the spine, then moved inside the padding and below the title.
    static func fishbone<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, measurers: DiagramTextMeasurerSet<Measurer>,
                                                         font: DiagramFont) -> ReferenceIshikawaLayout {
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.bold, maximumWidth: 4_000) }
        let titleHeight = title.map { title in title.lineCount == 0 ? 0 : title.size.height + titleGap } ?? 0
        var fish = ReferenceIshikawaFishbone()
        if diagram.nodeCount > 0 { fish.lay(diagram, measurers: measurers) }
        let bounds = fish.bounds
        let inner = max(bounds.width, title?.size.width ?? 0)
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: padding + (inner - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        var categories = fish.categories
        for index in categories.indices { categories[index].referenceTranslate(by: offset) }
        return ReferenceIshikawaLayout(size: size, font: font, title: placedTitle, spine: fish.spine?.translated(by: offset),
                              spineArrow: fish.spineArrow?.translated(by: offset), categories: categories,
                              head: fish.head.map { head in IshikawaLayoutHead(frame: head.frame.offsetBy(dx: offset.dx, dy: offset.dy),
                                                                              label: head.label.translated(by: offset)) },
                              outlineEntries: [], outlineConnectors: [])
    }
}

/// The fishbone on a page whose origin is the head's left end on the spine: the spine runs left from it, the head right.
struct ReferenceIshikawaFishbone {
    private(set) var spine: DiagramPath?
    private(set) var spineArrow: DiagramEdgeMark?
    private(set) var categories: [IshikawaLayoutCategory] = []
    private(set) var head: IshikawaLayoutHead?
    /// What is drawn, Pele's way: the spine's and the head's extent, the boxes and the causes' texts across.
    private(set) var bounds = CGRect.zero

    /// Lays out the diagram whose effect, its first node, is there.
    mutating func lay<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, measurers: DiagramTextMeasurerSet<Measurer>) {
        var headLabel = ReferenceIshikawaCategoryArrangement.textBlock(of: 0, in: diagram, measurer: measurers.bold, maximumWidth: 200)
        let headHeight = max(headLabel.size.height + 24, 48)
        let headWidth = headLabel.size.width + 24 + headHeight / 2
        headLabel.center = CGPoint(x: 12 + headLabel.size.width / 2, y: 0)
        head = IshikawaLayoutHead(frame: CGRect(x: 0, y: -headHeight / 2, width: headWidth, height: headHeight), label: headLabel)
        var walk = ReferenceIshikawaCategoryWalk()
        var arrangements = diagram.childIndices(of: 0).enumerated().map { order, index in
            ReferenceIshikawaCategoryArrangement(diagram, categoryIndex: Int(index), isAbove: order % 2 == 0, measurers: measurers, walk: &walk)
        }
        for index in arrangements.indices { arrangements[index].rise = max(arrangements[index].rise, headHeight / 2 + 14) }
        // Categories meet the spine in pairs, each pair as far toward the tail from the one before as the wider needs.
        var meetings: [CGFloat] = []
        meetings.reserveCapacity(arrangements.count + 1)
        categories.reserveCapacity(arrangements.count)
        var meeting = -ReferenceIshikawaLayoutEngine.headGap
        for first in stride(from: 0, to: arrangements.count, by: 2) {
            if first > 0 {
                var room: CGFloat = 0
                for side in 0..<2 where first - 2 + side < arrangements.count {
                    let next = first + side < arrangements.count ? arrangements[first + side].boxSize.width / 2 : 0
                    room = max(room, arrangements[first - 2 + side].reach + next)
                }
                meeting -= room + ReferenceIshikawaLayoutEngine.pairGap
            }
            meetings.append(meeting)
            meetings.append(meeting)
        }
        let tailEnd = arrangements.isEmpty ? -ReferenceIshikawaLayoutEngine.headGap : meeting - ReferenceIshikawaLayoutEngine.tail
        var extent = (minX: tailEnd, maxX: headWidth, minY: -headHeight / 2, maxY: headHeight / 2)
        for (order, arrangement) in arrangements.enumerated() {
            categories.append(Self.category(arrangement, meeting: meetings[order], sign: order % 2 == 0 ? -1 : 1, extent: &extent))
        }
        let trim = DiagramEdgeMark.arrowLength - 1
        spine = DiagramPath(start: CGPoint(x: tailEnd, y: 0), segments: [.line(to: CGPoint(x: -trim, y: 0))])
        spineArrow = DiagramEdgeMark(arrowhead: .arrow, tip: .zero, direction: CGVector(dx: 1, dy: 0))
        bounds = CGRect(x: extent.minX, y: extent.minY, width: extent.maxX - extent.minX, height: extent.maxY - extent.minY)
    }

    /// A category's bone, arrow, box and causes, its bone meeting the spine at `meeting`, above it for a `sign` of -1.
    private static func category(_ arrangement: ReferenceIshikawaCategoryArrangement, meeting: CGFloat, sign: CGFloat,
                                 extent: inout (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)) -> IshikawaLayoutCategory {
        let slant = ReferenceIshikawaLayoutEngine.slant
        let length = ReferenceIshikawaLayoutEngine.slantLength
        func across(_ alongBone: CGFloat, _ rise: CGFloat) -> CGFloat { meeting + alongBone - rise * slant }
        let end = CGPoint(x: across(0, arrangement.rise), y: sign * arrangement.rise)
        // The bone stops short of the spine to leave its arrowhead a clean point.
        let trim = DiagramEdgeMark.arrowLength - 1
        var bones = [IshikawaBoneLine(start: CGPoint(x: meeting - slant / length * trim, y: sign * trim / length), end: end)]
        bones.reserveCapacity(arrangement.bones.count + 1)
        var causes: [IshikawaLayoutCause] = []
        causes.reserveCapacity(arrangement.bones.count)
        for bone in arrangement.bones {
            let rowY = sign * bone.rise
            if bone.depth % 2 == 0 {
                bones.append(IshikawaBoneLine(start: CGPoint(x: across(bone.meeting, bone.rise), y: rowY),
                                              end: CGPoint(x: across(bone.textEnd + ReferenceIshikawaCategoryArrangement.textGap, bone.rise), y: rowY)))
            } else if let parentIndex = bone.parentIndex {
                let from = arrangement.bones[parentIndex].rise
                bones.append(IshikawaBoneLine(start: CGPoint(x: across(bone.meeting, from), y: sign * from),
                                              end: CGPoint(x: across(bone.meeting, bone.rise), y: rowY)))
            }
            let right = across(bone.textEnd, bone.rise)
            var text = bone.text
            text.center = CGPoint(x: right - text.size.width / 2, y: rowY)
            causes.append(IshikawaLayoutCause(text: text, isMuted: bone.depth > 2))
            extent.minX = min(extent.minX, right - text.size.width)
        }
        let boxSize = arrangement.boxSize
        let box = CGRect(x: end.x - boxSize.width / 2, y: end.y + sign * boxSize.height / 2 - boxSize.height / 2, width: boxSize.width, height: boxSize.height)
        extent = (min(extent.minX, box.minX), max(extent.maxX, box.maxX), min(extent.minY, box.minY), max(extent.maxY, box.maxY))
        var label = arrangement.label
        label.center = CGPoint(x: box.midX, y: box.midY)
        return IshikawaLayoutCategory(boneLines: bones, arrow: DiagramEdgeMark(arrowhead: .arrow, tip: CGPoint(x: meeting, y: 0),
                                                                          direction: CGVector(dx: slant / length, dy: -sign / length)),
                                      box: box, label: label, causes: causes)
    }
}

extension IshikawaLayoutCategory {
    /// Moves everything by `offset`, in place.
    mutating func referenceTranslate(by offset: CGVector) {
        for index in boneLines.indices {
            boneLines[index].start = CGPoint(x: boneLines[index].start.x + offset.dx, y: boneLines[index].start.y + offset.dy)
            boneLines[index].end = CGPoint(x: boneLines[index].end.x + offset.dx, y: boneLines[index].end.y + offset.dy)
        }
        arrow = arrow.translated(by: offset)
        box = box.offsetBy(dx: offset.dx, dy: offset.dy)
        label = label.translated(by: offset)
        for index in causes.indices { causes[index].text = causes[index].text.translated(by: offset) }
    }
}

struct ReferenceIshikawaCategoryArrangement {
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
                                         walk: inout ReferenceIshikawaCategoryWalk) {
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
struct ReferenceIshikawaCategoryWalk {
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
                        measurer: some DiagramTextMeasuring) -> [ReferenceIshikawaCategoryArrangement.Bone] {
        typealias Bone = ReferenceIshikawaCategoryArrangement.Bone
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
            bones.append(Bone(text: ReferenceIshikawaCategoryArrangement.textBlock(of: nodeIndex, in: diagram, measurer: measurer, maximumWidth: 200),
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
