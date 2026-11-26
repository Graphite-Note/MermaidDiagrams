/**
 * File: RequirementConstantTexts.swift
 * ------------------------------------
 * Layer: Core
 * Description: The texts of a closed set a requirement diagram draws again and again (the stereotypes, the fields'
 *              names, the relations' kinds and the risks' and methods' values), each measured once a diagram into its
 *              measurement's lines, the closed texts past ASCII from widths kept per face, and the fields a box shows.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// A field a box shows, by its name.
enum RequirementFieldKey: Int, CaseIterable {
    case identifier
    case text
    case risk
    case verification
    case type
    case documentReference

    /// The name drawn before the field's value.
    var name: String {
        switch self {
        case .identifier: "ID"
        case .text: "Text"
        case .risk: "Risk"
        case .verification: "Verification"
        case .type: "Type"
        case .documentReference: "Doc Ref"
        }
    }
}

/// The texts of a closed set a diagram's boxes and relations draw again and again, each measured once a diagram, the
/// first time it is drawn, into the lines given: the stereotypes (`«Requirement»`, `«Element»`) and the relations' kinds
/// (`«contains»`), past ASCII, whose widths are kept once per face for the whole process (`DiagramConstantTexts`); the
/// fields' names; and the values of `risk` and `verifymethod`. A text measured once is the text measuring it again gives,
/// and each is measured as 0.7.0 made its block: a stereotype decoded as plain text, a relation's kind as a label written
/// as is (both one line without markup, as their kept widths measure them), a field's name as plain text, which decodes to
/// the label 0.7.0 wrote of it, and a value as the Markdown text 0.7.0 measured.
struct RequirementConstantTexts<Measurer: DiagramTextMeasuring> {
    let body: DiagramFlatMeasurer<Measurer>
    private let widths: DiagramConstantTextWidths
    /// Each text once measured, by slot: the closed texts', the fields' names' after them, the values' last; a text not
    /// yet measured has a line count of -1. A span of the thread's arena.
    private let measured: ScratchSpan<DiagramMeasuredText>

    init(measurers: RequirementTextMeasurers<Measurer>, arena: DiagramScratchArena) {
        body = DiagramFlatMeasurer(measurers.body)
        widths = RequirementConstantTextKinds.closedTexts.widths(for: measurers.body)
        measured = arena.span(count: RequirementConstantTextKinds.slotCount,
                              repeating: DiagramMeasuredText(firstLine: 0, lineCount: -1, width: 0, height: 0, lineHeight: 0, fontSize: 0))
    }

    mutating func stereotype(of kind: RequirementKind, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        closedText(at: RequirementConstantTextKinds.slot(of: kind), into: &lines)
    }

    mutating func elementStereotype(into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        closedText(at: RequirementConstantTextKinds.elementSlot, into: &lines)
    }

    mutating func relationText(of kind: RequirementRelationKind, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        closedText(at: RequirementConstantTextKinds.slot(of: kind), into: &lines)
    }

    private mutating func closedText(at slot: Int, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        if measured[slot].lineCount >= 0 { return measured[slot] }
        let text = widths.measure(slot, measurer: body, maximumWidth: RequirementMeasurement.unwrapped, into: &lines)
        measured[slot] = text
        return text
    }

    mutating func key(_ key: RequirementFieldKey, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let slot = RequirementConstantTextKinds.slot(of: key)
        if measured[slot].lineCount >= 0 { return measured[slot] }
        // A field's name is printable ASCII without markup or white space at its ends, so the label 0.7.0 wrote of it,
        // `DiagramLabel(key.name)`, is the label decoding it as plain text gives, and it is measured on the flat path.
        let text = DiagramFlatTextMeasuring.measure(written: key.name, form: .plain, measurer: body, maximumWidth: RequirementMeasurement.unwrapped,
                                                    into: &lines)
        measured[slot] = text
        return text
    }

    /// A risk's value as the row shows it (`Low`), Markdown as 0.7.0 measured it.
    mutating func value(of risk: RequirementRisk, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        value(at: RequirementConstantTextKinds.slot(of: risk), written: risk.rawValue, into: &lines)
    }

    mutating func value(of method: RequirementVerificationMethod, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        value(at: RequirementConstantTextKinds.slot(of: method), written: method.rawValue, into: &lines)
    }

    private mutating func value(at slot: Int, written text: String, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        if measured[slot].lineCount >= 0 { return measured[slot] }
        let value = DiagramFlatTextMeasuring.measure(markdownWritten: text, measurer: body, maximumWidth: RequirementMeasurement.valueWrappingWidth,
                                                     into: &lines)
        measured[slot] = value
        return value
    }
}

/// The closed texts and the slots they are kept in: the stereotypes of the requirements' kinds in their declared order,
/// the element's, then the relations' kinds; and the slots of the risks and the verification methods' values.
enum RequirementConstantTextKinds {
    static let requirementKinds = RequirementKind.allCases
    static let relationKinds = RequirementRelationKind.allCases
    static let fieldKeyCount = RequirementFieldKey.allCases.count
    static let risks = RequirementRisk.allCases
    static let verificationMethods = RequirementVerificationMethod.allCases
    static let elementSlot = requirementKinds.count
    /// The first slot of the fields' names, and of the values, after the closed texts.
    static let firstKeySlot = requirementKinds.count + 1 + relationKinds.count
    static let firstValueSlot = firstKeySlot + fieldKeyCount
    static let slotCount = firstValueSlot + risks.count + verificationMethods.count

    /// `«kind»` for each requirement kind, `«Element»`, then `«kind»` for each relation kind.
    static let closedTexts = DiagramConstantTexts(requirementKinds.map { kind in "«\(kind.rawValue)»" } + ["«Element»"]
                                                    + relationKinds.map { kind in "«\(kind.rawValue)»" })

    static func slot(of kind: RequirementKind) -> Int {
        requirementKinds.firstIndex(of: kind) ?? 0
    }

    static func slot(of kind: RequirementRelationKind) -> Int {
        elementSlot + 1 + (relationKinds.firstIndex(of: kind) ?? 0)
    }

    static func slot(of key: RequirementFieldKey) -> Int {
        firstKeySlot + key.rawValue
    }

    static func slot(of risk: RequirementRisk) -> Int {
        firstValueSlot + (risks.firstIndex(of: risk) ?? 0)
    }

    static func slot(of method: RequirementVerificationMethod) -> Int {
        firstValueSlot + risks.count + (verificationMethods.firstIndex(of: method) ?? 0)
    }
}
