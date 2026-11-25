/**
 * File: ClassDiagramBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a class diagram as its statements are read, within the limits.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// Collects a class diagram as its statements are read: classes by identifier, relations and notes within the limits,
/// and the namespaces open at each point, which take the classes and notes declared inside them. Classes, notes, the
/// interfaces of lollipop ends and the namespaces' boxes are the diagram's nodes, which `maximumNodeCount` bounds together.
struct ClassDiagramBuilder {
    private var diagram = ClassDiagram()
    private let limits: MermaidDiagramLimits
    private let bytes: GraphDiagramBytes
    /// The names read, interned from their bytes; the class each names by its number, -1 for none.
    private var names: GraphDiagramNameTable
    private var classIndexByName: [Int32] = []
    /// The number of the name each note's `note for` names, -1 for none, by note index, found among the classes once
    /// all are declared.
    private var noteClassNames: [Int32] = []
    /// The bytes of the text a member shows, written member after member into one list.
    private var shownMemberBytes: [UInt8] = []
    private var interfaceCount = 0
    /// The namespace boxes the names written so far make at most: each part of a dotted name may be a box of its own.
    private var namespaceBoxCount = 0
    /// Indexes into `diagram.namespaces` of the namespaces open now, outermost first.
    private var openNamespaceIndices: [Int] = []

    init(limits: MermaidDiagramLimits, bytes: GraphDiagramBytes) {
        self.limits = limits
        self.bytes = bytes
        names = GraphDiagramNameTable(isASCII: bytes.isASCII)
        let nameCount = min((bytes.buffer.count - bytes.position) / Self.bytesPerName + 4, limits.maximumNodeCount, Self.mostReserved)
        names.reserveCapacity(nameCount)
        classIndexByName.reserveCapacity(nameCount)
        diagram.classes.reserveCapacity(nameCount)
    }

    /// About the bytes a class's name takes with what is written around it.
    private static let bytesPerName = 32
    /// The most names made room for at once; a longer text's lists grow.
    private static let mostReserved = 2_048

    /// The number of the name `range` spells.
    private mutating func number(of range: MermaidTextRange) -> Int {
        let (number, isNew) = names.intern(bytes.buffer, range)
        if isNew { classIndexByName.append(-1) }
        return number
    }

    /// The diagram read, each note joined to the class its `note for` names when the diagram declares that class.
    func finished() -> ClassDiagram {
        var finished = diagram
        for (noteIndex, name) in noteClassNames.enumerated() where name >= 0 {
            let classIndex = classIndexByName[Int(name)]
            finished.notes[noteIndex].classIndex = classIndex >= 0 ? Int(classIndex) : nil
        }
        return finished
    }

    private var nodeCount: Int { diagram.classes.count + diagram.notes.count + interfaceCount + namespaceBoxCount }

    /// The index of the class `name` names, added the first time it is named, with its name as its label and the
    /// generic type written then.
    mutating func classIndex(for name: ClassDiagramName) throws(MermaidDiagramReadError) -> Int {
        let number = number(of: name.identifier)
        if classIndexByName[number] >= 0 { return Int(classIndexByName[number]) }
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let index = diagram.classes.count
        let identifier = bytes.text(name.identifier)
        diagram.classes.append(ClassDiagramClass(identifier: identifier, label: DiagramLabel(identifier), genericType: name.genericType.map(bytes.text)))
        classIndexByName[number] = Int32(index)
        return index
    }

    /// `class Name["Label"]`: a later label replaces an earlier one.
    mutating func setLabel(_ label: DiagramLabel, ofClassAt index: Int) {
        diagram.classes[index].label = label
    }

    mutating func addAnnotation(_ annotation: String, toClassAt index: Int) {
        diagram.classes[index].annotations.append(annotation)
    }

    /// The member written at `range`, trimmed as `addMember(_:toClassAt:)` takes it: read on its bytes when they are
    /// ASCII, where each byte is a character, else as a String.
    mutating func addMember(at range: MermaidTextRange, toClassAt index: Int) {
        let member = UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound])
        guard bytes.isASCII || GraphDiagramNameTable.isASCII(member) else { return addMember(bytes.text(range), toClassAt: index) }
        guard !member.isEmpty else { return }
        let count = member.count
        if count >= 4, member[0] == MermaidByte.lessThan, member[1] == MermaidByte.lessThan, member[count - 2] == MermaidByte.greaterThan,
           member[count - 1] == MermaidByte.greaterThan {
            addAnnotation(String(decoding: UnsafeBufferPointer(rebasing: member[2..<(count - 2)]), as: UTF8.self), toClassAt: index)
            return
        }
        let (read, isMethod) = ClassDiagramMemberBytes.member(from: member, shownInto: &shownMemberBytes)
        if isMethod { diagram.classes[index].methods.append(read) } else { diagram.classes[index].attributes.append(read) }
    }

    /// A member as Mermaid sorts it: `<<…>>` is an annotation, text with a `)` after its first character a method
    /// (or an attribute when no `(` opens it), anything else an attribute. Empty text adds nothing.
    mutating func addMember(_ text: String, toClassAt index: Int) {
        guard !text.isEmpty else { return }
        if text.count >= 4, text.hasPrefix("<<"), text.hasSuffix(">>") {
            addAnnotation(String(text.dropFirst(2).dropLast(2)), toClassAt: index)
            return
        }
        let (member, isMethod) = ClassDiagramMemberSyntax.member(from: text)
        if isMethod { diagram.classes[index].methods.append(member) } else { diagram.classes[index].attributes.append(member) }
    }

    /// A relation between the classes its ends name, added when first named. A lollipop end facing no other mark
    /// names an interface of its own rather than a class (`bar ()-- foo`), as in Mermaid.
    mutating func addRelation(from sourceName: ClassDiagramName, to targetName: ClassDiagramName, operator relationOperator: ClassDiagramRelationOperator,
                              cardinalities: (source: String?, target: String?), label: DiagramLabel?) throws(MermaidDiagramReadError) {
        guard diagram.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
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
        diagram.relations.append(ClassDiagramRelation(source: source, target: target, sourceEnd: relationOperator.sourceEnd,
                                                      targetEnd: relationOperator.targetEnd, line: relationOperator.line,
                                                      sourceCardinality: cardinalities.source, targetCardinality: cardinalities.target, label: label))
    }

    private mutating func interface(named name: ClassDiagramName) throws(MermaidDiagramReadError) -> ClassDiagramRelationEndpoint {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        interfaceCount += 1
        return .interface(DiagramLabel(bytes.text(name.identifier)))
    }

    /// `note "text"`, or `note for Name "text"` with the identifier of the class it names.
    mutating func addNote(_ text: DiagramLabel, forClassIdentifiedBy identifier: MermaidTextRange?) throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        if let namespaceIndex = openNamespaceIndices.last { diagram.namespaces[namespaceIndex].noteIndices.append(diagram.notes.count) }
        diagram.notes.append(ClassDiagramNote(text: text))
        noteClassNames.append(identifier.map { identifier in Int32(number(of: identifier)) } ?? -1)
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
        diagram.namespaces.append(namespace)
        openNamespaceIndices.append(diagram.namespaces.count - 1)
    }

    mutating func closeNamespace() {
        openNamespaceIndices.removeLast()
    }

    /// The identifier of the innermost namespace still open, or nil.
    var innermostOpenNamespaceIdentifier: String? {
        openNamespaceIndices.last.map { index in diagram.namespaces[index].identifier }
    }

    /// A class declared inside the innermost namespace open.
    mutating func addToInnermostNamespace(classAt index: Int) {
        guard let namespaceIndex = openNamespaceIndices.last, !diagram.namespaces[namespaceIndex].classIndices.contains(index) else { return }
        diagram.namespaces[namespaceIndex].classIndices.append(index)
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
