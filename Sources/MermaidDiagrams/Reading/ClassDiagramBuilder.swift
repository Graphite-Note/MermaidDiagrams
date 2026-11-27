/**
 * File: ClassDiagramBuilder.swift
 * -------------------------------
 * Layer: Core
 * Description: Collects a class diagram as its statements are read, within the limits, as records over its text:
 *              classes by their interned names, members as runs of one list of shown bytes, texts as ranges where the
 *              decoder reads them as written.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// Collects a class diagram as its statements are read: classes by identifier, relations and notes within the limits,
/// and the namespaces open at each point, which take the classes and notes declared inside them. Classes, notes, the
/// interfaces of lollipop ends and the namespaces' boxes are the diagram's nodes, which `maximumNodeCount` bounds together.
struct ClassDiagramBuilder {
    private var model: ClassDiagramRecords
    private var direction = FlowchartDirection.topToBottom
    private var namespaces: [ClassDiagramNamespace] = []
    private var accessibilityTitle: String?
    private var accessibilityDescription: String?
    private var unappliedStatementCount = 0
    private let limits: MermaidDiagramLimits
    private let bytes: GraphDiagramBytes
    /// The thread's working lists, given back when the reading ends: the names read, interned from their bytes (`names`);
    /// the class each names by its number, -1 for none (`indexByName`); the number of the name each note's `note for`
    /// names, -1 for none, by note index, found among the classes once all are declared (`firstNumbers`); the class each
    /// member and each annotation is written for, in the order written, which `finished` puts in a run a class
    /// (`secondNumbers`, `thirdNumbers`); the bytes a member shows, written into one list (`bytes`).
    private var lists = GraphDiagramReadingLists()
    /// The namespace boxes the names written so far make at most: each part of a dotted name may be a box of its own.
    private var namespaceBoxCount = 0
    /// Indexes into `namespaces` of the namespaces open now, outermost first.
    private var openNamespaceIndices: [Int] = []

    /// - Parameter lists: The thread's working lists, emptied for this text, which the builder holds until `finished`
    ///   gives them back.
    init(text: MermaidSourceText, limits: MermaidDiagramLimits, bytes: GraphDiagramBytes, lists: inout GraphDiagramReadingLists) {
        model = ClassDiagramRecords(text: text)
        self.limits = limits
        self.bytes = bytes
        swap(&self.lists, &lists)
        let nameCount = min((bytes.buffer.count - bytes.position) / Self.bytesPerName + 4, limits.maximumNodeCount, Self.mostReserved)
        self.lists.names.reserveCapacity(nameCount)
        self.lists.indexByName.reserveCapacity(nameCount)
        model.classes.reserveCapacity(nameCount)
    }

    /// About the bytes a class's name takes with what is written around it.
    private static let bytesPerName = 32
    /// The most names made room for at once; a longer text's lists grow.
    private static let mostReserved = 2_048

    /// The number of the name `range` spells.
    private mutating func number(of range: MermaidTextRange) -> Int {
        let (number, isNew) = lists.names.intern(bytes.buffer, range)
        if isNew { lists.indexByName.append(-1) }
        return number
    }

    /// The diagram read: each class's annotations and members put in runs, each note joined to the class its `note for`
    /// names when the diagram declares that class.
    /// The working lists are given back to `lists`, the records moved out, not copied.
    mutating func finished(returning lists: inout GraphDiagramReadingLists) -> ClassDiagram {
        for (noteIndex, name) in self.lists.firstNumbers.enumerated() where name >= 0 {
            let classIndex = self.lists.indexByName[Int(name)]
            model.notes[noteIndex].classIndex = classIndex >= 0 ? classIndex : -1
        }
        ClassDiagramMemberRuns.group(&model, memberOwners: self.lists.secondNumbers, annotationOwners: self.lists.thirdNumbers)
        swap(&self.lists, &lists)
        var records = ClassDiagramRecords(text: model.text)
        swap(&records, &model)
        return ClassDiagram(direction: direction, model: ClassDiagramModel(records), namespaces: namespaces, accessibilityTitle: accessibilityTitle,
                            accessibilityDescription: accessibilityDescription, unappliedStatementCount: unappliedStatementCount)
    }

    private var nodeCount: Int { model.classes.count + model.notes.count + model.interfaces.count + namespaceBoxCount }

    /// The index of the class `name` names, added the first time it is named, labelled by its identifier, with the
    /// generic type written then.
    mutating func classIndex(for name: ClassDiagramName) throws(MermaidDiagramReadError) -> Int {
        let number = number(of: name.identifier)
        if lists.indexByName[number] >= 0 { return Int(lists.indexByName[number]) }
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        let index = model.classes.count
        var record = ClassDiagramClassRecord(identifier: name.identifier)
        if let genericType = name.genericType {
            record.genericStart = genericType.start
            record.genericEnd = genericType.end
        }
        model.classes.append(record)
        lists.indexByName[number] = Int32(index)
        return index
    }

    /// `class Name["Label"]`: a later label replaces an earlier one.
    mutating func setLabel(_ label: ClassDiagramReadText, ofClassAt index: Int) {
        model.classes[index].label = kept(label)
    }

    mutating func addAnnotation(_ annotation: String, toClassAt index: Int) {
        if lists.thirdNumbers.isEmpty { lists.thirdNumbers.reserveCapacity(Self.firstListCapacity) }
        model.annotations.append(annotation)
        lists.thirdNumbers.append(Int32(index))
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
        reserveMembers()
        let read = ClassDiagramMemberBytes.member(from: member, shownInto: &lists.bytes, appendingTo: &model.memberBytes)
        model.members.append(ClassDiagramMemberRecord(start: Int32(read.start), end: Int32(read.end), classifier: read.classifier, isMethod: read.isMethod))
        lists.secondNumbers.append(Int32(index))
    }

    /// A member as Mermaid sorts it: `<<…>>` is an annotation, text with a `)` after its first character a method
    /// (or an attribute when no `(` opens it), anything else an attribute. Empty text adds nothing.
    mutating func addMember(_ text: String, toClassAt index: Int) {
        guard !text.isEmpty else { return }
        if text.count >= 4, text.hasPrefix("<<"), text.hasSuffix(">>") {
            addAnnotation(String(text.dropFirst(2).dropLast(2)), toClassAt: index)
            return
        }
        reserveMembers()
        let (member, isMethod) = ClassDiagramMemberSyntax.member(from: text)
        let start = model.memberBytes.count
        model.memberBytes.append(contentsOf: member.text.utf8)
        model.members.append(ClassDiagramMemberRecord(start: Int32(start), end: Int32(model.memberBytes.count), classifier: member.classifier,
                                                      isMethod: isMethod))
        lists.secondNumbers.append(Int32(index))
    }

    /// Room for the members of a few classes, made when the first is read.
    private mutating func reserveMembers() {
        guard lists.secondNumbers.isEmpty else { return }
        lists.secondNumbers.reserveCapacity(Self.firstListCapacity)
        model.members.reserveCapacity(Self.firstListCapacity)
        model.memberBytes.reserveCapacity(Self.firstListCapacity * Self.bytesPerMember)
    }

    /// The members or annotations made room for when the first is read, and about the bytes a member shows.
    private static let firstListCapacity = 32
    private static let bytesPerMember = 16

    /// A relation between the classes its ends name, added when first named. A lollipop end facing no other mark
    /// names an interface of its own rather than a class (`bar ()-- foo`), as in Mermaid.
    mutating func addRelation(from sourceName: ClassDiagramName, to targetName: ClassDiagramName, operator relationOperator: ClassDiagramRelationOperator,
                              cardinalities: (source: String?, target: String?), label: ClassDiagramReadText?) throws(MermaidDiagramReadError) {
        guard model.relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
        let sourceIsInterface = relationOperator.sourceEnd == .lollipop && relationOperator.targetEnd == .none
        let targetIsInterface = relationOperator.targetEnd == .lollipop && relationOperator.sourceEnd == .none
        let source: Int32
        let target: Int32
        if sourceIsInterface {
            target = Int32(try classIndex(for: targetName))
            source = try interface(named: sourceName)
        } else {
            source = Int32(try classIndex(for: sourceName))
            target = targetIsInterface ? try interface(named: targetName) : Int32(try classIndex(for: targetName))
        }
        model.relations.append(ClassDiagramRelationRecord(source: source, target: target, sourceEnd: relationOperator.sourceEnd,
                                                          targetEnd: relationOperator.targetEnd, line: relationOperator.line,
                                                          sourceCardinality: cardinalities.source, targetCardinality: cardinalities.target,
                                                          label: label.map { kept($0) } ?? .none))
    }

    private mutating func interface(named name: ClassDiagramName) throws(MermaidDiagramReadError) -> Int32 {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        model.interfaces.append(ClassDiagramText(range: name.identifier))
        return ClassDiagramRelationRecord.interfaceEnd(model.interfaces.count - 1)
    }

    /// `note "text"`, or `note for Name "text"` with the identifier of the class it names.
    mutating func addNote(_ text: ClassDiagramReadText, forClassIdentifiedBy identifier: MermaidTextRange?) throws(MermaidDiagramReadError) {
        guard nodeCount < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        if let namespaceIndex = openNamespaceIndices.last { namespaces[namespaceIndex].noteIndices.append(model.notes.count) }
        model.notes.append(ClassDiagramNoteRecord(text: kept(text)))
        let name = identifier.map { identifier in Int32(number(of: identifier)) } ?? -1
        lists.firstNumbers.append(name)
    }

    /// The text as a record: its range, or its label kept among the model's.
    private mutating func kept(_ text: ClassDiagramReadText) -> ClassDiagramText {
        switch text {
        case .range(let range): ClassDiagramText(range: range)
        case .label(let label): model.written(label)
        }
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
        namespaces.append(namespace)
        openNamespaceIndices.append(namespaces.count - 1)
    }

    mutating func closeNamespace() {
        openNamespaceIndices.removeLast()
    }

    /// The identifier of the innermost namespace still open, or nil.
    var innermostOpenNamespaceIdentifier: String? {
        openNamespaceIndices.last.map { index in namespaces[index].identifier }
    }

    /// A class declared inside the innermost namespace open.
    mutating func addToInnermostNamespace(classAt index: Int) {
        guard let namespaceIndex = openNamespaceIndices.last, !namespaces[namespaceIndex].classIndices.contains(index) else { return }
        namespaces[namespaceIndex].classIndices.append(index)
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        self.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        unappliedStatementCount += 1
    }
}

/// A text read for a class's label, a relation or a note: a range of the text the label decoder reads as written, or
/// the label it decoded.
enum ClassDiagramReadText: Equatable {
    case range(MermaidTextRange)
    case label(DiagramLabel)

    /// The text of `range` decoded in `form`: the range itself when the decoder reads it as written (one line, trimmed,
    /// whatever its form), else its label.
    static func text(_ bytes: GraphDiagramBytes, _ range: MermaidTextRange, form: DiagramLabelDecoder.Form) -> ClassDiagramReadText {
        let written = UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound])
        guard DiagramLabelLineBreaks.isUnmarked(written, isLiteral: false) else { return .label(DiagramLabelDecoder.label(fromUTF8: written, form: form)) }
        return .range(range)
    }

    /// The text as its label: a range decoded, which reads it as written.
    func label(in bytes: GraphDiagramBytes) -> DiagramLabel {
        switch self {
        case .label(let label): label
        case .range(let range):
            DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes.buffer[range.lowerBound..<range.upperBound]), form: .plain)
        }
    }
}

/// Puts the members and annotations read, in the order written, in one run a class, in the classes' order: a class's
/// attributes, then its methods. Written so already, as they mostly are, they stay where they are.
enum ClassDiagramMemberRuns {
    static func group(_ model: inout ClassDiagramRecords, memberOwners: [Int32], annotationOwners: [Int32]) {
        if !memberOwners.isEmpty { groupMembers(&model, owners: memberOwners) }
        if !annotationOwners.isEmpty { groupAnnotations(&model, owners: annotationOwners) }
    }

    private static func groupMembers(_ model: inout ClassDiagramRecords, owners: [Int32]) {
        // In place when the owners never go back and no class's attribute follows one of its methods.
        var isInPlace = true
        for (index, owner) in owners.enumerated() {
            if model.members[index].isMethod { model.classes[Int(owner)].methodCount += 1 } else { model.classes[Int(owner)].attributeCount += 1 }
            guard index > 0 else { continue }
            let previous = owners[index - 1]
            if owner < previous || (owner == previous && model.members[index - 1].isMethod && !model.members[index].isMethod) { isInPlace = false }
        }
        var next: Int32 = 0
        for index in model.classes.indices {
            model.classes[index].firstMember = next
            next += model.classes[index].attributeCount + model.classes[index].methodCount
        }
        guard !isInPlace else { return }
        var placed = model.members
        var attributesPlaced = [Int32](repeating: 0, count: model.classes.count)
        var methodsPlaced = [Int32](repeating: 0, count: model.classes.count)
        for (index, owner) in owners.enumerated() {
            let record = model.classes[Int(owner)]
            let member = model.members[index]
            let slot = member.isMethod ? record.firstMember + record.attributeCount + methodsPlaced[Int(owner)] : record.firstMember + attributesPlaced[Int(owner)]
            if member.isMethod { methodsPlaced[Int(owner)] += 1 } else { attributesPlaced[Int(owner)] += 1 }
            placed[Int(slot)] = member
        }
        model.members = placed
    }

    private static func groupAnnotations(_ model: inout ClassDiagramRecords, owners: [Int32]) {
        var isInPlace = true
        for (index, owner) in owners.enumerated() {
            model.classes[Int(owner)].annotationCount += 1
            if index > 0, owner < owners[index - 1] { isInPlace = false }
        }
        var next: Int32 = 0
        for index in model.classes.indices {
            model.classes[index].firstAnnotation = next
            next += model.classes[index].annotationCount
        }
        guard !isInPlace else { return }
        var placed = model.annotations
        var written = [Int32](repeating: 0, count: model.classes.count)
        for (index, owner) in owners.enumerated() {
            placed[Int(model.classes[Int(owner)].firstAnnotation + written[Int(owner)])] = model.annotations[index]
            written[Int(owner)] += 1
        }
        model.annotations = placed
    }
}
