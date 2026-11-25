/**
 * File: ClassDiagramBox.swift
 * ---------------------------
 * Layer: Core
 * Description: A class's box measured around its text in Pele's measurements, its compartments and where its
 *              annotations, name and members are placed.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics

/// A class's box measured around its text, in Pele's measurements: the title compartment (annotations above the
/// name) 8 points from its top and bottom, then the attributes and the methods, each 6 points from its lines or
/// 10 points tall when empty, 12 points of padding on each side and 64 points wide at least. With `hideEmptyMembersBox`, a
/// class with no member has neither compartment nor divider (Pele's `sections`).
struct ClassDiagramBox {
    static let titlePadding: CGFloat = 8
    static let sectionPadding: CGFloat = 6
    static let emptySectionHeight: CGFloat = 10
    static let horizontalPadding: CGFloat = 12
    static let minimumWidth: CGFloat = 64
    static let markRowHeightRatio: CGFloat = 1.4
    /// The name's row is at least one line of the name's font: 1.5 times its size, rounded.
    static let nameRowHeightRatio: CGFloat = 1.5

    /// Widened later when many relations meet one of its sides.
    var size: CGSize
    private let annotations: [DiagramTextBlock]
    private let name: DiagramTextBlock
    /// The attributes then the methods, in one list; the first `attributeCount` are the attributes.
    private let members: [ClassDiagramLayoutMember]
    private let attributeCount: Int
    private let titleHeight: CGFloat
    private let attributesHeight: CGFloat
    private let markRowHeight: CGFloat
    private let memberLineHeight: CGFloat
    private let hasSections: Bool

    init<Measurer: DiagramTextMeasuring>(_ declared: ClassDiagramClass, measurers: ClassDiagramTextMeasurers<Measurer>, hidesEmptySections: Bool = false) {
        func line(_ text: String, _ measurer: Measurer) -> DiagramTextBlock {
            DiagramTextBlock(label: DiagramLabel(text), measurer: measurer, maximumWidth: .greatestFiniteMagnitude)
        }
        annotations = declared.annotations.map { annotation in
            line("«" + ClassDiagramMemberSyntax.trimmed(DiagramLabelDecoder.decodingEntities(annotation)) + "»", measurers.marks)
        }
        name = DiagramTextBlock(label: declared.displayedName, measurer: measurers.names, maximumWidth: .greatestFiniteMagnitude)
        var members: [ClassDiagramLayoutMember] = []
        members.reserveCapacity(declared.attributes.count + declared.methods.count)
        for member in declared.attributes { members.append(ClassDiagramLayoutMember(text: line(member.text, measurers.members), classifier: member.classifier)) }
        for member in declared.methods { members.append(ClassDiagramLayoutMember(text: line(member.text, measurers.members), classifier: member.classifier)) }
        self.members = members
        attributeCount = declared.attributes.count
        let methodCount = members.count - attributeCount
        markRowHeight = measurers.markRowHeight
        memberLineHeight = measurers.members.lineHeight
        let nameHeight = max(name.size.height, (measurers.names.fontSize * Self.nameRowHeightRatio).rounded())
        titleHeight = 2 * Self.titlePadding + CGFloat(annotations.count) * markRowHeight + nameHeight
        hasSections = !(hidesEmptySections && members.isEmpty)
        attributesHeight = hasSections ? Self.sectionHeight(lineCount: attributeCount, lineHeight: memberLineHeight) : 0
        let methodsHeight = hasSections ? Self.sectionHeight(lineCount: methodCount, lineHeight: memberLineHeight) : 0
        var widest = name.size.width
        for annotation in annotations { widest = max(widest, annotation.size.width) }
        for member in members { widest = max(widest, member.text.size.width) }
        size = CGSize(width: max(widest + 2 * Self.horizontalPadding, Self.minimumWidth), height: titleHeight + attributesHeight + methodsHeight)
    }

    private static func sectionHeight(lineCount: Int, lineHeight: CGFloat) -> CGFloat {
        lineCount > 0 ? 2 * sectionPadding + CGFloat(lineCount) * lineHeight : emptySectionHeight
    }

    /// The box at `center`, moved by `offset`: annotations centered from the top padding down, the name centered in the
    /// rest of the title, and each member left-aligned in its row; each place found as at `center` and then moved.
    func placed(at center: CGPoint, offset: CGVector) -> ClassDiagramLayoutClass {
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        var y = frame.minY + Self.titlePadding
        var placedAnnotations: [DiagramTextBlock] = []
        placedAnnotations.reserveCapacity(annotations.count)
        for annotation in annotations {
            placedAnnotations.append(centered(annotation, at: CGPoint(x: frame.midX, y: y + markRowHeight / 2).translated(by: offset)))
            y += markRowHeight
        }
        let titleBottom = frame.minY + titleHeight
        let placedName = centered(name, at: CGPoint(x: frame.midX, y: (y + titleBottom - Self.titlePadding) / 2).translated(by: offset))
        let methodsTop = titleBottom + attributesHeight
        var placedMembers: [ClassDiagramLayoutMember] = []
        placedMembers.reserveCapacity(members.count)
        appendLeftAligned(members[..<attributeCount], top: titleBottom, left: frame.minX, offset: offset, to: &placedMembers)
        appendLeftAligned(members[attributeCount...], top: methodsTop, left: frame.minX, offset: offset, to: &placedMembers)
        return ClassDiagramLayoutClass(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy),
                                       dividerYs: hasSections ? [titleBottom + offset.dy, methodsTop + offset.dy] : [],
                                       annotations: placedAnnotations, name: placedName, members: placedMembers)
    }

    private func appendLeftAligned(_ lines: ArraySlice<ClassDiagramLayoutMember>, top: CGFloat, left: CGFloat, offset: CGVector,
                                   to members: inout [ClassDiagramLayoutMember]) {
        for (index, member) in lines.enumerated() {
            let center = CGPoint(x: left + Self.horizontalPadding + member.text.size.width / 2,
                                 y: top + Self.sectionPadding + (CGFloat(index) + 0.5) * memberLineHeight)
            members.append(ClassDiagramLayoutMember(text: centered(member.text, at: center.translated(by: offset)), classifier: member.classifier))
        }
    }

    private func centered(_ block: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var placed = block
        placed.center = center
        return placed
    }
}
