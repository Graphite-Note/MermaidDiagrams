/**
 * File: RequirementDiagram.swift
 * ------------------------------
 * Layer: Core
 * Description: A Mermaid requirement diagram as its text describes it, over the flat records its reading made:
 *              requirements, elements, the relations between them, the styles and classes written for them, and the
 *              direction, made into values when a host reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

/// A requirement diagram (`requirementDiagram`) as Mermaid's database holds it: the requirements and the elements in the
/// order they are first declared (a name declared again keeps its first declaration), the relations in the order they are
/// written, whether or not they name anything declared, and the style classes.
///
/// The diagram keeps the flat records its reading made (`RequirementModel`): `requirements`, `elements`, `relations` and
/// `styleClasses` are made from them each time they are read, so a loop over a diagram's requirements reads
/// `requirementCount` and `requirement(at:)` instead.
public struct RequirementDiagram: Equatable, Sendable {
    /// `direction TB`, `BT`, `LR` or `RL`; top to bottom by default.
    public internal(set) var direction: FlowchartDirection
    /// The requirements, elements, relations and classes, as the reading made them.
    private(set) var model: RequirementModel
    /// The front matter's `title:`, or nil: the grammar has no `title` statement.
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?

    init(direction: FlowchartDirection = .topToBottom, model: RequirementModel = RequirementModel(), title: String? = nil,
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.direction = direction
        self.model = model
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }

    init(direction: FlowchartDirection = .topToBottom, requirements: [RequirementDiagramRequirement], elements: [RequirementDiagramElement] = [],
         relations: [RequirementDiagramRelation] = [], styleClasses: [RequirementDiagramStyleClass] = [], title: String? = nil,
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.init(direction: direction, model: RequirementModel(requirements: requirements, elements: elements, relations: relations, styleClasses: styleClasses),
                  title: title, accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription)
    }

    /// The requirements in the order they are first declared, made from the model on each read.
    public var requirements: [RequirementDiagramRequirement] { (0..<requirementCount).map(model.requirement(at:)) }
    /// The elements in the order they are first declared, made from the model on each read.
    public var elements: [RequirementDiagramElement] { (0..<elementCount).map(model.element(at:)) }
    /// The relations in the order they are written, made from the model on each read.
    public var relations: [RequirementDiagramRelation] { (0..<relationCount).map(model.relation(at:)) }
    /// The `classDef` classes, in the order they are first defined, made from the model on each read.
    public var styleClasses: [RequirementDiagramStyleClass] { model.styleClasses.indices.map(model.styleClass(at:)) }

    public var requirementCount: Int { model.requirementCount }
    public var elementCount: Int { model.elementCount }
    public var relationCount: Int { model.relations.count }

    public func requirement(at index: Int) -> RequirementDiagramRequirement { model.requirement(at: index) }
    public func element(at index: Int) -> RequirementDiagramElement { model.element(at: index) }
    public func relation(at index: Int) -> RequirementDiagramRelation { model.relation(at: index) }

    /// Diagrams are equal when they read the same: the same requirements, elements, relations, classes, direction and
    /// texts, whatever text their models index.
    public static func == (left: RequirementDiagram, right: RequirementDiagram) -> Bool {
        left.direction == right.direction && left.title == right.title && left.accessibilityTitle == right.accessibilityTitle
            && left.accessibilityDescription == right.accessibilityDescription && left.requirementCount == right.requirementCount
            && left.elementCount == right.elementCount && left.relationCount == right.relationCount
            && left.model.styleClasses.count == right.model.styleClasses.count && left.requirements == right.requirements
            && left.elements == right.elements && left.relations == right.relations && left.styleClasses == right.styleClasses
    }
}

/// A requirement: `requirement name { id: … text: … risk: … verifymethod: … }` or one of its five other kinds. A field
/// left out is empty text, as in Mermaid.
public struct RequirementDiagramRequirement: Equatable, Sendable {
    public let name: String
    public let kind: RequirementKind
    public internal(set) var identifier: String
    public internal(set) var text: String
    /// `low`, `medium` or `high`, or nil when the body sets none.
    public internal(set) var risk: RequirementRisk?
    public internal(set) var verificationMethod: RequirementVerificationMethod?
    /// The style declarations given to it, in the order they were given: its own `style` statements' and its classes'.
    public internal(set) var styleDeclarations: [String]
    /// `default`, then the classes given to it in the order they were given.
    public internal(set) var classNames: [String]
}

/// An element: `element name { type: … docref: … }`.
public struct RequirementDiagramElement: Equatable, Sendable {
    public let name: String
    public internal(set) var type: String
    public internal(set) var documentReference: String
    public internal(set) var styleDeclarations: [String]
    public internal(set) var classNames: [String]
}

/// A relation, `source - kind -> target` or `target <- kind - source`, by the names written.
public struct RequirementDiagramRelation: Equatable, Sendable {
    public let kind: RequirementRelationKind
    public let source: String
    public let target: String
}

/// A `classDef` class: its declarations, and those that set a color, for text (`fill` written `bgFill` in them).
public struct RequirementDiagramStyleClass: Equatable, Sendable {
    public let name: String
    public internal(set) var styleDeclarations: [String]
    public internal(set) var textStyleDeclarations: [String]
}

/// A requirement's kind, by the words Mermaid's database gives it and the stereotype draws.
public enum RequirementKind: String, Equatable, Sendable, CaseIterable {
    case requirement = "Requirement"
    case functionalRequirement = "Functional Requirement"
    case interfaceRequirement = "Interface Requirement"
    case performanceRequirement = "Performance Requirement"
    case physicalRequirement = "Physical Requirement"
    case designConstraint = "Design Constraint"
}

public enum RequirementRisk: String, Equatable, Sendable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

public enum RequirementVerificationMethod: String, Equatable, Sendable, CaseIterable {
    case analysis = "Analysis"
    case demonstration = "Demonstration"
    case inspection = "Inspection"
    case test = "Test"
}

/// What a relation says, by the word written, which the relation's text draws in guillemets.
public enum RequirementRelationKind: String, Equatable, Sendable, CaseIterable, BitwiseCopyable {
    case contains, copies, derives, satisfies, verifies, refines, traces
}

extension RequirementDiagram: TitledMermaidDiagram {}

extension RequirementDiagram {
    /// The requirement diagram turned to run down, or nil when it does not run across: from the top down whichever way it
    /// ran across, as Pele's requirement renderer draws it turned.
    public var turnedToRunDown: RequirementDiagram? {
        guard direction.runsAcross else { return nil }
        var turned = self
        turned.direction = .topToBottom
        return turned
    }
}
