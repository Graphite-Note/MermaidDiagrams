/**
 * File: ReferenceClassDiagramBuilder.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: 0.7.0's ClassDiagramBuilder, kept unchanged but for its names, and for its parts kept in lists of their
 *              own that the diagram's façade is made from, as the reference the class reader on bytes is compared with
 *              (ClassReadingEquivalenceTests).
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

/// Collects a class diagram as its statements are read: classes by identifier, relations and notes within the limits,
/// and the namespaces open at each point, which take the classes and notes declared inside them. Classes, notes, the
/// interfaces of lollipop ends and the namespaces' boxes are the diagram's nodes, which `maximumNodeCount` bounds together.
struct ReferenceClassDiagramBuilder {
    /// The diagram's parts as 0.7.0 kept them, in lists, which the façade the diagram now is is made from.
    private var parts = ReferenceClassDiagramParts()
    private let limits: MermaidDiagramLimits
    private var classIndexByIdentifier: [String: Int] = [:]
    /// The identifier each note's `note for` names, by note index, found among the classes once all are declared.
    private var noteClassIdentifiers: [String?] = []
    private var interfaceCount = 0
    /// The namespace boxes the names written so far make at most: each part of a dotted name may be a box of its own.
    private var namespaceBoxCount = 0
    /// Indexes into `parts.namespaces` of the namespaces open now, outermost first.
    private var openNamespaceIndices: [Int] = []

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The diagram read, each note joined to the class its `note for` names when the diagram declares that class.
    func finished() -> ClassDiagram {
        var finished = parts
        for (noteIndex, identifier) in noteClassIdentifiers.enumerated() {
            finished.notes[noteIndex].classIndex = identifier.flatMap { identifier in classIndexByIdentifier[identifier] }
        }
        return finished.diagram
    }

    private var nodeCount: Int { parts.classes.count + parts.notes.count + interfaceCount + namespaceBoxCount }

    /// The index of the class `name` names, added the first time it is named, with its name as its label and the
    /// generic type written then.
    mutating func classIndex(for name: ReferenceClassDiagramName) throws(MermaidDiagramReadError) -> Int {
        if let existing = classIndexByIdentifier[name.identifier] { return existing }
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let index = parts.classes.count
        parts.classes.append(ClassDiagramClass(identifier: name.identifier, label: DiagramLabel(name.identifier), genericType: name.genericType))
        classIndexByIdentifier[name.identifier] = index
        return index
    }

    /// `class Name["Label"]`: a later label replaces an earlier one.
    mutating func setLabel(_ label: DiagramLabel, ofClassAt index: Int) {
        parts.classes[index].label = label
    }

    mutating func addAnnotation(_ annotation: String, toClassAt index: Int) {
        parts.classes[index].annotations.append(annotation)
    }

    /// A member as Mermaid sorts it: `<<…>>` is an annotation, text with a `)` after its first character a method
    /// (or an attribute when no `(` opens it), anything else an attribute. Empty text adds nothing.
    mutating func addMember(_ text: String, toClassAt index: Int) {
        guard !text.isEmpty else { return }
        if text.count >= 4, text.hasPrefix("<<"), text.hasSuffix(">>") {
            addAnnotation(String(text.dropFirst(2).dropLast(2)), toClassAt: index)
            return
        }
        let (member, isMethod) = ReferenceClassDiagramMemberSyntax.member(from: text)
        if isMethod { parts.classes[index].methods.append(member) } else { parts.classes[index].attributes.append(member) }
    }

    /// A relation between the classes its ends name, added when first named. A lollipop end facing no other mark
    /// names an interface of its own rather than a class (`bar ()-- foo`), as in Mermaid.
    mutating func addRelation(from sourceName: ReferenceClassDiagramName, to targetName: ReferenceClassDiagramName, operator relationOperator: ReferenceClassDiagramRelationOperator,
                              cardinalities: (source: String?, target: String?), label: DiagramLabel?) throws(MermaidDiagramReadError) {
        guard parts.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        let sourceIsInterface = relationOperator.sourceEnd == .lollipop && relationOperator.targetEnd == .none
        let targetIsInterface = relationOperator.targetEnd == .lollipop && relationOperator.sourceEnd == .none
        let source: ClassDiagramRelationEndpoint
        let target: ClassDiagramRelationEndpoint
        if sourceIsInterface {
            target = .classIndex(try classIndex(for: targetName))
            source = try interface(named: sourceName)
        } else {
            source = .classIndex(try classIndex(for: sourceName))
            target = targetIsInterface ? try interface(named: targetName) : .classIndex(try classIndex(for: targetName))
        }
        parts.relations.append(ClassDiagramRelation(source: source, target: target, sourceEnd: relationOperator.sourceEnd,
                                                      targetEnd: relationOperator.targetEnd, line: relationOperator.line,
                                                      sourceCardinality: cardinalities.source, targetCardinality: cardinalities.target, label: label))
    }

    private mutating func interface(named name: ReferenceClassDiagramName) throws(MermaidDiagramReadError) -> ClassDiagramRelationEndpoint {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        interfaceCount += 1
        return .interface(DiagramLabel(name.identifier))
    }

    /// `note "text"`, or `note for Name "text"` with the identifier of the class it names.
    mutating func addNote(_ text: DiagramLabel, forClassIdentifiedBy identifier: String?) throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        if let namespaceIndex = openNamespaceIndices.last { parts.namespaces[namespaceIndex].noteIndices.append(parts.notes.count) }
        parts.notes.append(ClassDiagramNote(text: text))
        noteClassIdentifiers.append(identifier)
    }

    /// Opens a namespace inside the innermost one open, its identifier joined to that one's by a dot. Each part of a
    /// dotted name may be a box of its own (`ClassDiagramNamespaceTree`), so each counts as a node before it is made.
    mutating func openNamespace(named name: String, title: DiagramLabel?) throws(MermaidDiagramReadError) {
        let partCount = name.utf8.reduce(1) { count, byte in byte == MermaidByte.period ? count + 1 : count }
        guard partCount <= limits.maximumNodeCount - nodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        namespaceBoxCount += partCount
        let identifier = innermostOpenNamespaceIdentifier.map { parent in parent + "." + name } ?? name
        var namespace = ClassDiagramNamespace(identifier: identifier, title: title ?? DiagramLabel(name))
        namespace.enclosingNamespaceIndex = openNamespaceIndices.last
        parts.namespaces.append(namespace)
        openNamespaceIndices.append(parts.namespaces.count - 1)
    }

    mutating func closeNamespace() {
        openNamespaceIndices.removeLast()
    }

    /// The identifier of the innermost namespace still open, or nil.
    var innermostOpenNamespaceIdentifier: String? {
        openNamespaceIndices.last.map { index in parts.namespaces[index].identifier }
    }

    /// A class declared inside the innermost namespace open.
    mutating func addToInnermostNamespace(classAt index: Int) {
        guard let namespaceIndex = openNamespaceIndices.last, !parts.namespaces[namespaceIndex].classIndices.contains(index) else { return }
        parts.namespaces[namespaceIndex].classIndices.append(index)
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        parts.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        parts.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        parts.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        parts.unappliedStatementCount += 1
    }
}

/// A class diagram's parts in lists, as 0.7.0's `ClassDiagram` held them, so that the reference reader builds them as it did.
struct ReferenceClassDiagramParts {
    var direction: FlowchartDirection = .topToBottom
    var classes: [ClassDiagramClass] = []
    var relations: [ClassDiagramRelation] = []
    var notes: [ClassDiagramNote] = []
    var namespaces: [ClassDiagramNamespace] = []
    var accessibilityTitle: String?
    var accessibilityDescription: String?
    var unappliedStatementCount = 0

    var diagram: ClassDiagram {
        ClassDiagram(direction: direction, classes: classes, relations: relations, notes: notes, namespaces: namespaces, accessibilityTitle: accessibilityTitle,
                     accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }
}
