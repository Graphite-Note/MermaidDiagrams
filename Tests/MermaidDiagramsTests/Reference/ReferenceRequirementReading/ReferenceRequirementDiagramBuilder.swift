/**
 * File: ReferenceRequirementDiagramBuilder.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's RequirementDiagramBuilder, kept unchanged but for its names, and for the values it builds into,
 *              0.7.0's diagram's lists, which make the diagram at the end, as the reference the requirement reader on
 *              bytes is compared with (RequirementReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

/// Builds a requirement diagram as Mermaid's `requirementDb` does. The grammar reports a body's fields before the
/// requirement or element they belong to, so they are held until it comes, and dropped if it was declared before. A
/// requirement or element counts as a node of the limits and a relation as an edge, each before it is made. Applying a
/// class copies its declarations onto each node, so a short text can ask for hundreds of millions of copies: the
/// declarations copied and the classes given, together, are bounded by Pele's million.
struct ReferenceRequirementDiagramBuilder {
    /// Pele's `MAX_STYLE_COPIES`.
    static let maximumStyleCopyCount = 1_000_000

    private(set) var diagram = ReferenceRequirementDiagramValues()
    private let limits: MermaidDiagramLimits
    private var requirementIndices: [String: Int] = [:]
    private var elementIndices: [String: Int] = [:]
    private var styleClassIndices: [String: Int] = [:]
    /// Each node's classes as a set, by requirement and by element, so that a `classDef` finds the nodes that have it at once.
    private var requirementClassSets: [Set<String>] = []
    private var elementClassSets: [Set<String>] = []
    private var styleCopyCount = 0
    private var pendingIdentifier = ""
    private var pendingText = ""
    private var pendingRisk: RequirementRisk?
    private var pendingVerificationMethod: RequirementVerificationMethod?
    private var pendingType = ""
    private var pendingDocumentReference = ""

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// Why a statement could not be applied, which the parser reports at the statement's line.
    enum Refusal: Error, Equatable {
        case tooManyNodes, tooManyEdges, tooManyStyleCopies
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ text: String) {
        diagram.accessibilityTitle = text
    }

    /// The description with the whitespace after each line break left out, as Mermaid's `/\n\s+/g` replaces it.
    mutating func setAccessibilityDescription(_ text: String) {
        let bytes = Array(text.utf8)
        var kept: [UInt8] = []
        var position = 0
        while position < bytes.count {
            kept.append(bytes[position])
            position = bytes[position] == MermaidByte.newline ? JavaScriptWhitespace.endOfRun(in: bytes, from: position + 1) : position + 1
        }
        diagram.accessibilityDescription = String(decoding: kept, as: UTF8.self)
    }

    mutating func setPendingField(_ field: ReferenceRequirementFieldName, text: String) {
        switch field {
        case .identifier: pendingIdentifier = text
        case .text: pendingText = text
        case .type: pendingType = text
        case .documentReference: pendingDocumentReference = text
        case .risk, .verificationMethod: break
        }
    }

    mutating func setPendingRisk(_ risk: RequirementRisk) {
        pendingRisk = risk
    }

    mutating func setPendingVerificationMethod(_ method: RequirementVerificationMethod) {
        pendingVerificationMethod = method
    }

    /// The requirement named, with the fields held for it unless it was declared before; the fields are cleared either way.
    mutating func addRequirement(named name: String, kind: RequirementKind) throws(Refusal) {
        defer {
            pendingIdentifier = ""
            pendingText = ""
            pendingRisk = nil
            pendingVerificationMethod = nil
        }
        guard requirementIndices[name] == nil else { return }
        guard diagram.requirements.count + diagram.elements.count < limits.maximumNodeCount else { throw .tooManyNodes }
        requirementIndices[name] = diagram.requirements.count
        requirementClassSets.append(["default"])
        diagram.requirements.append(RequirementDiagramRequirement(name: name, kind: kind, identifier: pendingIdentifier, text: pendingText,
                                                                  risk: pendingRisk, verificationMethod: pendingVerificationMethod,
                                                                  styleDeclarations: [], classNames: ["default"]))
    }

    mutating func addElement(named name: String) throws(Refusal) {
        defer {
            pendingType = ""
            pendingDocumentReference = ""
        }
        guard elementIndices[name] == nil else { return }
        guard diagram.requirements.count + diagram.elements.count < limits.maximumNodeCount else { throw .tooManyNodes }
        elementIndices[name] = diagram.elements.count
        elementClassSets.append(["default"])
        diagram.elements.append(RequirementDiagramElement(name: name, type: pendingType, documentReference: pendingDocumentReference,
                                                          styleDeclarations: [], classNames: ["default"]))
    }

    mutating func addRelation(_ kind: RequirementRelationKind, from source: String, to target: String) throws(Refusal) {
        guard diagram.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges }
        diagram.relations.append(RequirementDiagramRelation(kind: kind, source: source, target: target))
    }
}

extension ReferenceRequirementDiagramBuilder {
    /// A node by name: the requirement of that name, else the element.
    private enum NodeReference {
        case requirement(Int), element(Int)
    }

    private func node(named name: String) -> NodeReference? {
        if let index = requirementIndices[name] { return .requirement(index) }
        return elementIndices[name].map(NodeReference.element)
    }

    private mutating func copy(_ declarations: [String], onto node: NodeReference) throws(Refusal) {
        try count(declarations.count)
        switch node {
        case .requirement(let index): diagram.requirements[index].styleDeclarations += declarations
        case .element(let index): diagram.elements[index].styleDeclarations += declarations
        }
    }

    private mutating func count(_ copies: Int) throws(Refusal) {
        styleCopyCount += copies
        guard styleCopyCount <= Self.maximumStyleCopyCount else { throw .tooManyStyleCopies }
    }

    /// `style a,b declarations`: Mermaid stops at the first name that is no node, leaving the rest of the list unstyled.
    mutating func setStyle(names: [String], declarations: [String]) throws(Refusal) {
        let split = declarations.flatMap { declaration in declaration.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        for name in names {
            guard let node = node(named: name) else { return }
            try copy(split, onto: node)
        }
    }

    /// `class a,b c1,c2` and `a:::c1,c2`: each class is given to each node named, with the declarations its class holds
    /// now; a name that is no node is passed over.
    mutating func setClasses(names: [String], classNames: [String]) throws(Refusal) {
        for name in names {
            guard let node = node(named: name) else { continue }
            for className in classNames {
                try count(1)
                switch node {
                case .requirement(let index):
                    diagram.requirements[index].classNames.append(className)
                    requirementClassSets[index].insert(className)
                case .element(let index):
                    diagram.elements[index].classNames.append(className)
                    elementClassSets[index].insert(className)
                }
                if let classIndex = styleClassIndices[className] { try copy(diagram.styleClasses[classIndex].styleDeclarations, onto: node) }
            }
        }
    }

    /// `classDef a,b declarations`: each class defined or extended, and its declarations copied onto every node that has
    /// it already; a declaration that sets a color is also kept for text, its first `fill` written `bgFill`.
    mutating func defineClasses(names: [String], declarations: [String]) throws(Refusal) {
        let split = declarations.flatMap { declaration in declaration.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        for name in names {
            let classIndex = styleClassIndices[name] ?? diagram.styleClasses.count
            if classIndex == diagram.styleClasses.count {
                styleClassIndices[name] = classIndex
                diagram.styleClasses.append(RequirementDiagramStyleClass(name: name, styleDeclarations: [], textStyleDeclarations: []))
            }
            for declaration in declarations {
                if declaration.contains("color") {
                    let text = declaration.range(of: "fill").map { range in declaration.replacingCharacters(in: range, with: "bgFill") } ?? declaration
                    diagram.styleClasses[classIndex].textStyleDeclarations.append(text)
                }
                diagram.styleClasses[classIndex].styleDeclarations.append(declaration)
            }
            for index in requirementClassSets.indices where requirementClassSets[index].contains(name) { try copy(split, onto: .requirement(index)) }
            for index in elementClassSets.indices where elementClassSets[index].contains(name) { try copy(split, onto: .element(index)) }
        }
    }
}

/// 0.7.0's requirement diagram as the lists the reference builds, made into the diagram when the reading ends.
struct ReferenceRequirementDiagramValues {
    var direction = FlowchartDirection.topToBottom
    var requirements: [RequirementDiagramRequirement] = []
    var elements: [RequirementDiagramElement] = []
    var relations: [RequirementDiagramRelation] = []
    var styleClasses: [RequirementDiagramStyleClass] = []
    var accessibilityTitle: String?
    var accessibilityDescription: String?

    var made: RequirementDiagram {
        RequirementDiagram(direction: direction, requirements: requirements, elements: elements, relations: relations, styleClasses: styleClasses,
                           accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription)
    }
}
