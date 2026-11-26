/**
 * File: IshikawaLayoutEngine.swift
 * --------------------------------
 * Layer: Core
 * Description: Lays an Ishikawa diagram out with Pele's measurements: a fishbone across, its categories in pairs along
 *              the spine, or for a narrow column an indented list down the page.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// Lays an Ishikawa diagram out as Pele's renderer does: a horizontal spine to the effect's head with an arrowhead;
/// categories meeting the spine in pairs, one above and one below, each pair as far toward the tail from the one before
/// as the wider of the two needs; their bones slanting half a point toward the tail per point they rise, each ending at
/// the category's box; every cause on a row of its own (`IshikawaCategoryArrangement`). When the fishbone is wider than
/// `maximumWidth` and that is under Pele's 640-point breakpoint, the diagram runs down instead, as an indented list,
/// when that is narrower (`IshikawaOutlinePlacement`).
public enum IshikawaLayoutEngine {
    static let slant: CGFloat = 0.5
    static let slantLength = (slant * slant + 1).squareRoot()
    static let pairGap: CGFloat = 26
    static let headGap: CGFloat = 34
    static let tail: CGFloat = 28
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// Below this width a diagram that does not fit turns to run down, as Pele's breakpoint.
    static let breakpoint: CGFloat = 640

    public static func layout(_ diagram: IshikawaDiagram, typography: DiagramTypography, maximumWidth: CGFloat? = nil) -> IshikawaLayout {
        layout(diagram, measurers: DiagramTextMeasurerSet(typography: typography), font: typography.font, maximumWidth: maximumWidth)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, measurers: DiagramTextMeasurerSet<Measurer>, font: DiagramFont,
                                                       maximumWidth: CGFloat?) -> IshikawaLayout {
        let across = fishbone(diagram, measurers: measurers, font: font)
        guard let maximumWidth, maximumWidth > 0, maximumWidth.isFinite, across.size.width > maximumWidth, maximumWidth < breakpoint else { return across }
        let down = IshikawaOutlinePlacement.layout(diagram, measurers: measurers, font: font, maximumWidth: maximumWidth)
        return down.size.width < across.size.width ? down : across
    }

    /// The fishbone, its head's left end at the origin on the spine, then moved inside the padding and below the title.
    static func fishbone<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, measurers: DiagramTextMeasurerSet<Measurer>,
                                                         font: DiagramFont) -> IshikawaLayout {
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.bold, maximumWidth: 4_000) }
        let titleHeight = title.map { title in title.lineCount == 0 ? 0 : title.size.height + titleGap } ?? 0
        var fish = IshikawaFishbone()
        if diagram.nodeCount > 0 { fish.lay(diagram, measurers: measurers) }
        let bounds = fish.bounds
        let inner = max(bounds.width, title?.size.width ?? 0)
        let size = CGSize(width: (inner + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        let offset = CGVector(dx: padding + (inner - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + (title?.size.height ?? 0) / 2)
        var records = fish.records
        records.translate(by: offset)
        return IshikawaLayout(size: size, font: font, title: placedTitle, spine: fish.spine?.translated(by: offset),
                              spineArrow: fish.spineArrow?.translated(by: offset), fishbone: records, outlineEntries: [], outlineConnectors: [])
    }
}

/// The fishbone on a page whose origin is the head's left end on the spine: the spine runs left from it, the head right.
struct IshikawaFishbone {
    private(set) var spine: DiagramPath?
    private(set) var spineArrow: DiagramEdgeMark?
    /// The categories, causes and head, with their texts.
    private(set) var records = IshikawaFishboneRecords()
    /// What is drawn, Pele's way: the spine's and the head's extent, the boxes and the causes' texts across.
    private(set) var bounds = CGRect.zero

    /// Lays out the diagram whose effect, its first node, is there.
    mutating func lay<Measurer: DiagramTextMeasuring>(_ diagram: IshikawaDiagram, measurers textMeasurers: DiagramTextMeasurerSet<Measurer>) {
        let measurers = IshikawaMeasurers(textMeasurers)
        records.bytes = diagram.bytes
        records.lines.reserveCapacity(lines: diagram.nodeCount + 4, derivedBytes: 0)
        var bones: [IshikawaCategoryArrangement.Bone] = []
        bones.reserveCapacity(diagram.nodeCount)
        let categoryIndices = diagram.childIndices(of: 0)
        var arrangements: [IshikawaCategoryArrangement] = []
        arrangements.reserveCapacity(categoryIndices.count)
        var headLabel = DiagramMeasuredText(firstLine: 0, lineCount: 0, width: 0, height: 0, lineHeight: 0, fontSize: 0)
        diagram.bytes.withUnsafeBufferPointer { source in
            headLabel = measurers.measure(0, of: diagram, source: source, measurer: measurers.bold, maximumWidth: 200, into: &records.lines)
            var walk = IshikawaCategoryWalk()
            for (order, index) in categoryIndices.enumerated() {
                arrangements.append(IshikawaCategoryArrangement(diagram, categoryIndex: Int(index), isAbove: order % 2 == 0, measurers: measurers,
                                                                source: source, bones: &bones, texts: &records.lines, walk: &walk))
            }
        }
        let headHeight = max(headLabel.height + 24, 48)
        let headWidth = headLabel.width + 24 + headHeight / 2
        headLabel.center = CGPoint(x: 12 + headLabel.width / 2, y: 0)
        records.headFrame = CGRect(x: 0, y: -headHeight / 2, width: headWidth, height: headHeight)
        records.headLabel = headLabel
        for index in arrangements.indices { arrangements[index].rise = max(arrangements[index].rise, headHeight / 2 + 14) }
        let meetings = Self.meetings(of: arrangements)
        let tailEnd = arrangements.isEmpty ? -IshikawaLayoutEngine.headGap : meetings.last - IshikawaLayoutEngine.tail
        var extent = (minX: tailEnd, maxX: headWidth, minY: -headHeight / 2, maxY: headHeight / 2)
        records.boneLines.reserveCapacity(bones.count + arrangements.count)
        records.causes.reserveCapacity(bones.count)
        records.categoryRecords.reserveCapacity(arrangements.count)
        for (order, arrangement) in arrangements.enumerated() {
            addCategory(arrangement, bones: bones, meeting: meetings.pairs[order / 2], sign: order % 2 == 0 ? -1 : 1, extent: &extent)
        }
        let trim = DiagramEdgeMark.arrowLength - 1
        spine = DiagramPath(start: CGPoint(x: tailEnd, y: 0), segments: [.line(to: CGPoint(x: -trim, y: 0))])
        spineArrow = DiagramEdgeMark(arrowhead: .arrow, tip: .zero, direction: CGVector(dx: 1, dy: 0))
        bounds = CGRect(x: extent.minX, y: extent.minY, width: extent.maxX - extent.minX, height: extent.maxY - extent.minY)
    }

    /// Where each pair of categories meets the spine: each pair as far toward the tail from the one before as the wider
    /// of the two needs, and the last pair's. Both of a pair meet it at the same place.
    private static func meetings(of arrangements: [IshikawaCategoryArrangement]) -> (pairs: [CGFloat], last: CGFloat) {
        var pairMeetings: [CGFloat] = []
        pairMeetings.reserveCapacity(arrangements.count / 2 + 1)
        var meeting = -IshikawaLayoutEngine.headGap
        for first in stride(from: 0, to: arrangements.count, by: 2) {
            if first > 0 {
                var room: CGFloat = 0
                for side in 0..<2 where first - 2 + side < arrangements.count {
                    let next = first + side < arrangements.count ? arrangements[first + side].boxSize.width / 2 : 0
                    room = max(room, arrangements[first - 2 + side].reach + next)
                }
                meeting -= room + IshikawaLayoutEngine.pairGap
            }
            pairMeetings.append(meeting)
        }
        return (pairMeetings, meeting)
    }

    /// A category's bone, arrow, box and causes, its bone meeting the spine at `meeting`, above it for a `sign` of -1.
    private mutating func addCategory(_ arrangement: IshikawaCategoryArrangement, bones: [IshikawaCategoryArrangement.Bone], meeting: CGFloat,
                                      sign: CGFloat, extent: inout (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)) {
        let slant = IshikawaLayoutEngine.slant
        let length = IshikawaLayoutEngine.slantLength
        func across(_ alongBone: CGFloat, _ rise: CGFloat) -> CGFloat { meeting + alongBone - rise * slant }
        let end = CGPoint(x: across(0, arrangement.rise), y: sign * arrangement.rise)
        // The bone stops short of the spine to leave its arrowhead a clean point.
        let trim = DiagramEdgeMark.arrowLength - 1
        let firstBone = Int32(records.boneLines.count)
        let firstCause = Int32(records.causes.count)
        records.boneLines.append(IshikawaBoneLine(start: CGPoint(x: meeting - slant / length * trim, y: sign * trim / length), end: end))
        let categoryBones = bones[arrangement.firstBone..<arrangement.firstBone + arrangement.boneCount]
        for bone in categoryBones {
            let rowY = sign * bone.rise
            if bone.depth % 2 == 0 {
                records.boneLines.append(IshikawaBoneLine(start: CGPoint(x: across(bone.meeting, bone.rise), y: rowY),
                                                          end: CGPoint(x: across(bone.textEnd + IshikawaCategoryArrangement.textGap, bone.rise), y: rowY)))
            } else if bone.parentIndex >= 0 {
                let from = bones[arrangement.firstBone + Int(bone.parentIndex)].rise
                records.boneLines.append(IshikawaBoneLine(start: CGPoint(x: across(bone.meeting, from), y: sign * from),
                                                          end: CGPoint(x: across(bone.meeting, bone.rise), y: rowY)))
            }
            let right = across(bone.textEnd, bone.rise)
            var text = bone.text
            text.center = CGPoint(x: right - text.width / 2, y: rowY)
            records.causes.append(IshikawaPlacedCause(text: text, isMuted: bone.depth > 2))
            extent.minX = min(extent.minX, right - text.width)
        }
        let boxSize = arrangement.boxSize
        let box = CGRect(x: end.x - boxSize.width / 2, y: end.y + sign * boxSize.height / 2 - boxSize.height / 2, width: boxSize.width, height: boxSize.height)
        extent = (min(extent.minX, box.minX), max(extent.maxX, box.maxX), min(extent.minY, box.minY), max(extent.maxY, box.maxY))
        var label = arrangement.label
        label.center = CGPoint(x: box.midX, y: box.midY)
        records.categoryRecords.append(IshikawaPlacedCategory(firstBone: firstBone, boneCount: Int32(records.boneLines.count) - firstBone,
                                                              firstCause: firstCause, causeCount: Int32(records.causes.count) - firstCause,
                                                              arrow: DiagramEdgeMark(arrowhead: .arrow, tip: CGPoint(x: meeting, y: 0),
                                                                                     direction: CGVector(dx: slant / length, dy: -sign / length)),
                                                              box: box, label: label))
    }
}
