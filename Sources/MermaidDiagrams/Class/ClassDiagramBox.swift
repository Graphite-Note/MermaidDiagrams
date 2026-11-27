/**
 * File: ClassDiagramBox.swift
 * ---------------------------
 * Layer: Core
 * Description: A class's box measured around its text in Pele's measurements, its texts measured into the
 *              measurement's one list of lines, its compartments and where its annotations, name and members are placed.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
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
    private let name: DiagramMeasuredText
    /// The annotations, a run of the measurement's annotation texts.
    private let annotations: Range<Int>
    /// The attributes then the methods, a run of the measurement's member texts; the first `attributeCount` are the
    /// attributes.
    private let members: Range<Int>
    private let attributeCount: Int
    private let titleHeight: CGFloat
    private let attributesHeight: CGFloat
    private let markRowHeight: CGFloat
    private let memberLineHeight: CGFloat
    private let hasSections: Bool

    /// The box of the class at `index`, its texts measured into `texts`.
    init<Measurer: DiagramTextMeasuring>(classAt index: Int, of model: ClassDiagramModel, measuring: ClassDiagramTextMeasuring<Measurer>,
                                         hidesEmptySections: Bool, into texts: inout ClassDiagramMeasuredTexts) {
        let record = model.classes[index]
        let annotationStart = texts.annotations.count
        for annotationIndex in record.annotationIndices {
            let annotation = "«" + ClassDiagramMemberSyntax.trimmed(DiagramLabelDecoder.decodingEntities(model.annotations[annotationIndex])) + "»"
            texts.annotations.append(DiagramFlatTextMeasuring.measure(writtenLine: annotation, measurer: measuring.marks,
                                                                      maximumWidth: .greatestFiniteMagnitude, into: &texts.lines))
        }
        annotations = annotationStart..<texts.annotations.count
        name = measuring.measureName(ofClassAt: index, of: model, into: &texts.lines)
        let memberStart = texts.members.count
        model.memberBytes.withUnsafeBufferPointer { memberBytes in
            for memberIndex in record.memberIndices {
                let member = model.members[memberIndex]
                let measured = DiagramFlatTextMeasuring.measure(writtenLine: memberBytes, MermaidTextRange(start: Int(member.start), end: Int(member.end)),
                                                                measurer: measuring.members, maximumWidth: .greatestFiniteMagnitude, into: &texts.lines)
                texts.lines.deriveLines(of: measured, source: memberBytes)
                texts.members.append(ClassDiagramPlacedMember(text: measured, classifier: member.classifier))
            }
        }
        members = memberStart..<texts.members.count
        attributeCount = Int(record.attributeCount)
        markRowHeight = measuring.markRowHeight
        memberLineHeight = measuring.members.singleLineHeight
        let nameHeight = max(name.height, (measuring.names.fontSize * Self.nameRowHeightRatio).rounded())
        titleHeight = 2 * Self.titlePadding + CGFloat(annotations.count) * markRowHeight + nameHeight
        hasSections = !(hidesEmptySections && members.isEmpty)
        attributesHeight = hasSections ? Self.sectionHeight(lineCount: attributeCount, lineHeight: memberLineHeight) : 0
        let methodsHeight = hasSections ? Self.sectionHeight(lineCount: members.count - attributeCount, lineHeight: memberLineHeight) : 0
        var widest = name.width
        for annotation in annotations { widest = max(widest, texts.annotations[annotation].width) }
        for member in members { widest = max(widest, texts.members[member].text.width) }
        size = CGSize(width: max(widest + 2 * Self.horizontalPadding, Self.minimumWidth), height: titleHeight + attributesHeight + methodsHeight)
    }

    private static func sectionHeight(lineCount: Int, lineHeight: CGFloat) -> CGFloat {
        lineCount > 0 ? 2 * sectionPadding + CGFloat(lineCount) * lineHeight : emptySectionHeight
    }

    /// The box at `center`, moved by `offset`: annotations centered from the top padding down, the name centered in the
    /// rest of the title, and each member left-aligned in its row; each place found as at `center` and then moved. The
    /// placed annotations and members are appended to the layout's lists.
    func placed(at center: CGPoint, offset: CGVector, texts: ClassDiagramMeasuredTexts, annotations placedAnnotations: inout [DiagramMeasuredText],
                members placedMembers: inout [ClassDiagramPlacedMember]) -> ClassDiagramPlacedClass {
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        var y = frame.minY + Self.titlePadding
        let firstAnnotation = placedAnnotations.count
        for annotation in annotations {
            placedAnnotations.append(texts.annotations[annotation].centered(at: CGPoint(x: frame.midX, y: y + markRowHeight / 2).translated(by: offset)))
            y += markRowHeight
        }
        let titleBottom = frame.minY + titleHeight
        let placedName = name.centered(at: CGPoint(x: frame.midX, y: (y + titleBottom - Self.titlePadding) / 2).translated(by: offset))
        let methodsTop = titleBottom + attributesHeight
        let firstMember = placedMembers.count
        appendLeftAligned(members.lowerBound..<(members.lowerBound + attributeCount), of: texts, top: titleBottom, left: frame.minX, offset: offset,
                          to: &placedMembers)
        appendLeftAligned((members.lowerBound + attributeCount)..<members.upperBound, of: texts, top: methodsTop, left: frame.minX, offset: offset,
                          to: &placedMembers)
        return ClassDiagramPlacedClass(frame: frame.offsetBy(dx: offset.dx, dy: offset.dy), hasDividers: hasSections,
                                       dividerYs: (titleBottom + offset.dy, methodsTop + offset.dy),
                                       annotations: Int32(firstAnnotation)..<Int32(placedAnnotations.count), name: placedName,
                                       members: Int32(firstMember)..<Int32(placedMembers.count))
    }

    private func appendLeftAligned(_ lines: Range<Int>, of texts: ClassDiagramMeasuredTexts, top: CGFloat, left: CGFloat, offset: CGVector,
                                   to members: inout [ClassDiagramPlacedMember]) {
        for (index, memberIndex) in lines.enumerated() {
            let member = texts.members[memberIndex]
            let center = CGPoint(x: left + Self.horizontalPadding + member.text.width / 2,
                                 y: top + Self.sectionPadding + (CGFloat(index) + 0.5) * memberLineHeight)
            members.append(ClassDiagramPlacedMember(text: member.text.centered(at: center.translated(by: offset)), classifier: member.classifier))
        }
    }
}
