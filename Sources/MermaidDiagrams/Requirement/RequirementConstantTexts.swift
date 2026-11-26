/**
 * File: RequirementConstantTexts.swift
 * ------------------------------------
 * Layer: Core
 * Description: The texts of a closed set a requirement diagram draws again and again (the stereotypes, the fields'
 *              names and the relations' kinds), each measured once a diagram into its measurement's lines, and the
 *              fields a box shows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
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
/// first time it is drawn, into the lines given: the stereotypes (`«Requirement»`, `«Element»`), the fields' names and
/// the relations' kinds (`«contains»`). A text measured once is the text measuring it again gives, and each is measured as
/// 0.7.0 made its block: a stereotype decoded as plain text, a relation's kind as a label written as is, and a field's name
/// as plain text, which decodes to the label 0.7.0 wrote of it.
struct RequirementConstantTexts<Measurer: DiagramTextMeasuring> {
    let body: DiagramFlatMeasurer<Measurer>
    private var stereotypes = [DiagramMeasuredText?](repeating: nil, count: RequirementConstantTextKinds.requirementKinds.count + 1)
    private var keys = [DiagramMeasuredText?](repeating: nil, count: RequirementConstantTextKinds.fieldKeyCount)
    private var relationTexts = [DiagramMeasuredText?](repeating: nil, count: RequirementConstantTextKinds.relationKinds.count)

    init(measurers: RequirementTextMeasurers<Measurer>) {
        body = DiagramFlatMeasurer(measurers.body)
    }

    /// The kinds in their declared order, made once rather than at each look-up.
    private static var requirementKinds: [RequirementKind] { RequirementConstantTextKinds.requirementKinds }
    private static var relationKinds: [RequirementRelationKind] { RequirementConstantTextKinds.relationKinds }

    mutating func stereotype(of kind: RequirementKind, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        stereotype(at: Self.requirementKinds.firstIndex(of: kind) ?? 0, kind: kind.rawValue, into: &lines)
    }

    mutating func elementStereotype(into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        stereotype(at: Self.requirementKinds.count, kind: "Element", into: &lines)
    }

    private mutating func stereotype(at slot: Int, kind: String, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        if let measured = stereotypes[slot] { return measured }
        let measured = DiagramFlatTextMeasuring.measure(written: "«\(kind)»", form: .plain, measurer: body, maximumWidth: RequirementMeasurement.unwrapped,
                                                        into: &lines)
        stereotypes[slot] = measured
        return measured
    }

    mutating func key(_ key: RequirementFieldKey, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        if let measured = keys[key.rawValue] { return measured }
        // A field's name is printable ASCII without markup or white space at its ends, so the label 0.7.0 wrote of it,
        // `DiagramLabel(key.name)`, is the label decoding it as plain text gives, and it is measured on the flat path.
        let measured = DiagramFlatTextMeasuring.measure(written: key.name, form: .plain, measurer: body, maximumWidth: RequirementMeasurement.unwrapped,
                                                        into: &lines)
        keys[key.rawValue] = measured
        return measured
    }

    mutating func relationText(of kind: RequirementRelationKind, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let slot = Self.relationKinds.firstIndex(of: kind) ?? 0
        if let measured = relationTexts[slot] { return measured }
        let measured = DiagramFlatTextMeasuring.measure(DiagramLabel("«\(kind.rawValue)»"), measurer: body, maximumWidth: RequirementMeasurement.unwrapped,
                                                        into: &lines)
        relationTexts[slot] = measured
        return measured
    }
}

/// The kinds the constant texts are kept by, in their declared order (`allCases` makes a new list each time it is read).
enum RequirementConstantTextKinds {
    static let requirementKinds = RequirementKind.allCases
    static let relationKinds = RequirementRelationKind.allCases
    static let fieldKeyCount = RequirementFieldKey.allCases.count
}
