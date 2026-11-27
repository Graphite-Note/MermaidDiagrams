/**
 * File: RequirementModelViews.swift
 * ---------------------------------
 * Layer: Core
 * Description: A requirement diagram's flat records made into the values a host reads (requirements, elements,
 *              relations and classes, with their Strings) when it reads them, and a model made from such values.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension RequirementModel {
    func requirement(at index: Int) -> RequirementDiagramRequirement {
        let record = nodes[index]
        return RequirementDiagramRequirement(name: string(record.name), kind: record.kind, identifier: string(record.firstField), text: string(record.secondField),
                                             risk: record.risk, verificationMethod: record.verificationMethod,
                                             styleDeclarations: styleDeclarations(of: record), classNames: classNames(of: record))
    }

    func element(at index: Int) -> RequirementDiagramElement {
        let record = nodes[requirementCount + index]
        return RequirementDiagramElement(name: string(record.name), type: string(record.firstField), documentReference: string(record.secondField),
                                         styleDeclarations: styleDeclarations(of: record), classNames: classNames(of: record))
    }

    func relation(at index: Int) -> RequirementDiagramRelation {
        let record = relations[index]
        return RequirementDiagramRelation(kind: record.kind, source: string(record.source), target: string(record.target))
    }

    /// A class, and the declarations it keeps for text: those that set a color, their first `fill` written `bgFill`.
    func styleClass(at index: Int) -> RequirementDiagramStyleClass {
        let record = styleClasses[index]
        let declarations = record.declarationIndices.map { position in declaration(numbers[position]) }
        return RequirementDiagramStyleClass(name: string(record.name), styleDeclarations: declarations,
                                            textStyleDeclarations: declarations.filter(RequirementDiagramBuilder.holdsColor)
                                                .map(RequirementDiagramBuilder.withBackgroundFill))
    }

    private func styleDeclarations(of record: RequirementNodeRecord) -> [String] {
        record.styleDeclarationIndices.map { position in declaration(numbers[position]) }
    }

    private func classNames(of record: RequirementNodeRecord) -> [String] {
        ["default"] + record.classNameIndices.map { position in string(ranges[position]) }
    }
}

extension RequirementModel {
    /// The model of values a reading made: their Strings, declarations included, written one after the other as its text,
    /// every node's classes after the `default` each reading gives it first, each relation's ends looked up by name (a
    /// requirement before an element), as the layout looked them up.
    init(requirements: [RequirementDiagramRequirement], elements: [RequirementDiagramElement], relations: [RequirementDiagramRelation],
         styleClasses: [RequirementDiagramStyleClass]) {
        var boxes: [String: Int32] = [:]
        for (index, requirement) in requirements.enumerated() where boxes[requirement.name] == nil { boxes[requirement.name] = Int32(index) }
        for (index, element) in elements.enumerated() where boxes[element.name] == nil { boxes[element.name] = Int32(requirements.count + index) }
        requirementCount = requirements.count
        for requirement in requirements {
            var record = RequirementNodeRecord(name: written(requirement.name), firstField: written(requirement.identifier),
                                               secondField: written(requirement.text), kind: requirement.kind, risk: requirement.risk,
                                               verificationMethod: requirement.verificationMethod)
            appendStyle(requirement.styleDeclarations, classNames: requirement.classNames, to: &record)
            nodes.append(record)
        }
        for element in elements {
            var record = RequirementNodeRecord(name: written(element.name), firstField: written(element.type), secondField: written(element.documentReference),
                                               kind: .requirement, risk: nil, verificationMethod: nil)
            appendStyle(element.styleDeclarations, classNames: element.classNames, to: &record)
            nodes.append(record)
        }
        for relation in relations {
            self.relations.append(RequirementRelationRecord(kind: relation.kind, source: written(relation.source), target: written(relation.target),
                                                            sourceBox: boxes[relation.source] ?? -1, targetBox: boxes[relation.target] ?? -1))
        }
        for styleClass in styleClasses {
            var record = RequirementStyleClassRecord(name: written(styleClass.name), firstDeclaration: Int32(numbers.count))
            for declaration in styleClass.styleDeclarations { numbers.append(writtenDeclaration(declaration)) }
            record.declarationCount = Int32(numbers.count) - record.firstDeclaration
            self.styleClasses.append(record)
        }
    }

    private mutating func appendStyle(_ declarations: [String], classNames: [String], to record: inout RequirementNodeRecord) {
        record.firstStyleDeclaration = Int32(numbers.count)
        for declaration in declarations { numbers.append(writtenDeclaration(declaration)) }
        record.styleDeclarationCount = Int32(numbers.count) - record.firstStyleDeclaration
        record.firstClassName = Int32(ranges.count)
        for name in classNames.dropFirst() { ranges.append(written(name)) }
        record.classNameCount = Int32(ranges.count) - record.firstClassName
    }

    private mutating func written(_ string: String) -> MermaidTextRange {
        let start = text.count
        text.append(contentsOf: string.utf8)
        return MermaidTextRange(start: start, end: text.count)
    }

    private mutating func writtenDeclaration(_ string: String) -> Int32 {
        ranges.append(written(string))
        return Int32(ranges.count - 1)
    }
}
