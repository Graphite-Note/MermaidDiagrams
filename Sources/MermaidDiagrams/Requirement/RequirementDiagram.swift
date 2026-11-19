/**
 * File: RequirementDiagram.swift
 * ------------------------------
 * Layer: Core
 * Description: A Mermaid requirement diagram as its text describes it: requirements, elements, the relations between
 *              them, the styles and classes written for them, and the direction.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A requirement diagram (`requirementDiagram`) as Mermaid's database holds it: the requirements and the elements in the
/// order they are first declared (a name declared again keeps its first declaration), the relations in the order they are
/// written, whether or not they name anything declared, and the style classes.
public struct RequirementDiagram: Equatable, Sendable {
    /// `direction TB`, `BT`, `LR` or `RL`; top to bottom by default.
    public internal(set) var direction: FlowchartDirection
    public internal(set) var requirements: [RequirementDiagramRequirement]
    public internal(set) var elements: [RequirementDiagramElement]
    public internal(set) var relations: [RequirementDiagramRelation]
    /// The `classDef` classes, in the order they are first defined.
    public internal(set) var styleClasses: [RequirementDiagramStyleClass]
    /// The front matter's `title:`, or nil: the grammar has no `title` statement.
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?

    init(direction: FlowchartDirection = .topToBottom, requirements: [RequirementDiagramRequirement] = [], elements: [RequirementDiagramElement] = [],
         relations: [RequirementDiagramRelation] = [], styleClasses: [RequirementDiagramStyleClass] = [], title: String? = nil,
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.direction = direction
        self.requirements = requirements
        self.elements = elements
        self.relations = relations
        self.styleClasses = styleClasses
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
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
public enum RequirementRelationKind: String, Equatable, Sendable, CaseIterable {
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
