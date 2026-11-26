/**
 * File: ClassDiagram.swift
 * ------------------------
 * Layer: Core
 * Description: A Mermaid class diagram as its text describes it, a façade over the flat records the reader writes
 *              (`ClassDiagramModel`): its classes, relations and notes made from them when asked.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

/// A Mermaid class diagram (`classDiagram` or `classDiagram-v2`) as its text describes it: the classes in the order
/// they first appear, the relations between them and the notes in the order they are written, and the groups and
/// statements read but not drawn.
public struct ClassDiagram: Equatable, Sendable {
    /// The way ranks of classes follow each other: `direction TB`, `BT`, `LR` or `RL`, top to bottom by default.
    public internal(set) var direction: FlowchartDirection
    /// The classes, relations and notes as records over the diagram's text, which the layout reads.
    let model: ClassDiagramModel
    /// The `namespace … { … }` groups, in the order they open, each statement once; drawn as boxes around their classes
    /// (`ClassDiagramNamespaceTree`).
    public internal(set) var namespaces: [ClassDiagramNamespace]
    /// The front matter's `class: hierarchicalNamespaces`: true unless it is false, when only the namespaces the text
    /// declares are drawn, side by side, each titled with its full name.
    public internal(set) var hierarchicalNamespaces = true
    /// The front matter's `class: hideEmptyMembersBox: true`: a class with no attribute and no method is drawn as its title
    /// alone, without its two empty compartments and their dividers, as Pele draws it.
    public internal(set) var hidesEmptyMemberBoxes = false
    /// The diagram's title, from `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Statements that change only how the diagram looks (`style`, `classDef`, `cssClass`, `:::`) or what a click
    /// does (`click`, `link`, `callback`). They are read and not applied.
    public internal(set) var unappliedStatementCount: Int

    init(direction: FlowchartDirection = .topToBottom, classes: [ClassDiagramClass] = [], relations: [ClassDiagramRelation] = [],
         notes: [ClassDiagramNote] = [], namespaces: [ClassDiagramNamespace] = [], title: String? = nil, accessibilityTitle: String? = nil,
         accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.init(direction: direction, model: ClassDiagramModel(ClassDiagramRecords(classes: classes, relations: relations, notes: notes)),
                  namespaces: namespaces,
                  title: title, accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription,
                  unappliedStatementCount: unappliedStatementCount)
    }

    init(direction: FlowchartDirection, model: ClassDiagramModel, namespaces: [ClassDiagramNamespace], title: String? = nil,
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil, unappliedStatementCount: Int = 0) {
        self.direction = direction
        self.model = model
        self.namespaces = namespaces
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.unappliedStatementCount = unappliedStatementCount
    }

    /// The classes in the order they first appear, made from the records: `class(at:)` makes one.
    public var classes: [ClassDiagramClass] { (0..<classCount).map(model.materializedClass(at:)) }
    /// The relations in the order they are written.
    public var relations: [ClassDiagramRelation] { (0..<relationCount).map(model.materializedRelation(at:)) }
    /// The notes in the order they are written.
    public var notes: [ClassDiagramNote] { (0..<noteCount).map(model.materializedNote(at:)) }

    public var classCount: Int { model.classes.count }
    public var relationCount: Int { model.relations.count }
    public var noteCount: Int { model.notes.count }

    public func `class`(at index: Int) -> ClassDiagramClass { model.materializedClass(at: index) }
    public func relation(at index: Int) -> ClassDiagramRelation { model.materializedRelation(at: index) }
    public func note(at index: Int) -> ClassDiagramNote { model.materializedNote(at: index) }

    public static func == (left: ClassDiagram, right: ClassDiagram) -> Bool {
        left.direction == right.direction && left.namespaces == right.namespaces && left.hierarchicalNamespaces == right.hierarchicalNamespaces
            && left.hidesEmptyMemberBoxes == right.hidesEmptyMemberBoxes && left.title == right.title && left.accessibilityTitle == right.accessibilityTitle
            && left.accessibilityDescription == right.accessibilityDescription && left.unappliedStatementCount == right.unappliedStatementCount
            && left.classCount == right.classCount && left.relationCount == right.relationCount && left.noteCount == right.noteCount
            && left.classes == right.classes && left.relations == right.relations && left.notes == right.notes
    }
}

/// A note: `note "text"` stands alone, `note for Name "text"` is joined to its class by a dotted line.
public struct ClassDiagramNote: Equatable, Sendable {
    public let text: DiagramLabel
    /// Index into `ClassDiagram.classes` of the class `note for` names, or nil for a note on its own or one whose
    /// class the diagram never declares.
    public internal(set) var classIndex: Int?

    init(text: DiagramLabel, classIndex: Int? = nil) {
        self.text = text
        self.classIndex = classIndex
    }
}

/// A `namespace Name { … }` group: its identifier (a nested one's joined to its parents' by dots), its title, and
/// the classes and notes declared inside it.
public struct ClassDiagramNamespace: Equatable, Sendable {
    public let identifier: String
    public let title: DiagramLabel
    /// Indexes into `ClassDiagram.classes`, in the order the classes appear in the group.
    public internal(set) var classIndices: [Int]
    /// Indexes into `ClassDiagram.notes` of the notes written inside the group.
    public internal(set) var noteIndices: [Int] = []
    /// Index into `ClassDiagram.namespaces` of the namespace this one is written inside, or nil at the top level.
    var enclosingNamespaceIndex: Int?

    init(identifier: String, title: DiagramLabel, classIndices: [Int] = []) {
        self.identifier = identifier
        self.title = title
        self.classIndices = classIndices
    }
}
