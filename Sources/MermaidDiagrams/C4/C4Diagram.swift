/**
 * File: C4Diagram.swift
 * ---------------------
 * Layer: Core
 * Description: A Mermaid C4 diagram (`C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment`) as Pele's
 *              model holds it: its shapes, its boundaries nested in one another, its relations and its row counts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A Mermaid C4 diagram as Pele's `C4Db` holds it once read. Shapes and boundaries are listed in the order first
/// written; an alias written again changes the element it names and keeps its place.
public struct C4Diagram: Equatable, Sendable {
    /// The keyword the diagram starts with.
    public internal(set) var level: C4DiagramLevel
    /// `title …` or `accTitle: …` (which Mermaid's grammar hands to the title), else `title:` in the front matter.
    public internal(set) var title: String?
    /// `accDescr: …`, `accDescr { … }` or `accDescription …`.
    public internal(set) var accessibilityDescription: String?
    public internal(set) var shapes: [C4Shape]
    /// The boundaries, the first the unnamed one that holds everything at the top level (`global`).
    public internal(set) var boundaries: [C4Boundary]
    public internal(set) var relations: [C4Relation]
    /// `UpdateLayoutConfig`'s first value: how many shapes a row of a boundary holds, 4 unless set to one or more.
    public internal(set) var shapesPerRow: Int
    /// Its second: how many boundaries a row holds, 2 unless set.
    public internal(set) var boundariesPerRow: Int

    init(level: C4DiagramLevel = .context) {
        self.level = level
        shapes = []
        boundaries = [C4Boundary(element: C4Element(alias: "global", label: "global", type: "global"), deploymentNode: nil)]
        relations = []
        shapesPerRow = 4
        boundariesPerRow = 2
    }

    /// The shape or else the boundary written with `alias`, as Pele's `getC4Shape` finds a relation's end.
    public func element(named alias: String) -> C4ElementReference? {
        if let index = shapes.firstIndex(where: { shape in shape.element.alias == alias && shape.element.aliasArgument == nil }) {
            return .shape(index)
        }
        let boundaryIndex = boundaries.indices.dropFirst().first { index in
            boundaries[index].element.alias == alias && boundaries[index].element.aliasArgument == nil
        }
        return boundaryIndex.map(C4ElementReference.boundary)
    }
}

/// The keyword a C4 diagram starts with. Only a dynamic diagram draws differently: its relations are numbered.
public enum C4DiagramLevel: String, CaseIterable, Sendable {
    case context = "C4Context"
    case container = "C4Container"
    case component = "C4Component"
    case dynamic = "C4Dynamic"
    case deployment = "C4Deployment"
}

/// A shape or a boundary of a diagram, by its index in its list.
public enum C4ElementReference: Hashable, Sendable {
    case shape(Int)
    case boundary(Int)
}

/// What a shape and a boundary share: the fields Mermaid's macros and `UpdateElementStyle` set.
public struct C4Element: Equatable, Sendable {
    /// Empty when the alias's place held a named argument (`aliasArgument`).
    public internal(set) var alias: String
    public internal(set) var label: String
    /// A named argument written where the alias or the label belongs, applied to the field it names.
    public internal(set) var aliasArgument: C4NamedArgument?
    public internal(set) var labelArgument: C4NamedArgument?
    /// The boundary it was last written in, by its index in the diagram's boundaries; nil for the top level's own.
    public internal(set) var parentBoundaryIndex: Int?
    public internal(set) var type: String?
    public internal(set) var description: String?
    public internal(set) var technology: String?
    public internal(set) var sprite: String?
    public internal(set) var tags: String?
    public internal(set) var link: String?
    public internal(set) var backgroundColor: String?
    public internal(set) var fontColor: String?
    public internal(set) var borderColor: String?
    public internal(set) var shadowing: String?
    public internal(set) var shape: String?
    public internal(set) var legendText: String?
    public internal(set) var legendSprite: String?
    /// The named arguments that set no field, by name, in the order first written.
    public internal(set) var otherArguments: C4OtherArguments

    init(alias: String = "", label: String = "", type: String? = nil) {
        self.alias = alias
        self.label = label
        self.type = type
        otherArguments = C4OtherArguments()
    }

    /// Sets the field a named argument names (`$descr`, `$bgColor`), or keeps it among the other arguments.
    mutating func apply(_ argument: C4NamedArgument) {
        let value = argument.value
        switch argument.key {
        case "label": label = value
        case "type": type = value
        case "descr": description = value
        case "techn": technology = value
        case "sprite": sprite = value
        case "tags": tags = value
        case "link": link = value
        case "bgColor": backgroundColor = value
        case "fontColor": fontColor = value
        case "borderColor": borderColor = value
        case "shadowing": shadowing = value
        case "shape": shape = value
        case "legendText": legendText = value
        case "legendSprite": legendSprite = value
        default: otherArguments.set(argument)
        }
    }
}

/// A person, a system, a container or a component, of its kind and drawn in a boundary.
public struct C4Shape: Equatable, Sendable {
    public internal(set) var element: C4Element
    /// The kind its last macro gave it.
    public internal(set) var kind: C4ShapeKind
}

/// A boundary that holds shapes and other boundaries: an enterprise, system, container or plain boundary, or a
/// deployment node.
public struct C4Boundary: Equatable, Sendable {
    public internal(set) var element: C4Element
    /// The kind of deployment node (`Node`, `Node_L`, `Node_R`), nil for the other boundaries.
    public internal(set) var deploymentNode: C4DeploymentNodeKind?
}

/// Mermaid's `typeC4Shape`: the kind of a shape, by the macro that wrote it.
public enum C4ShapeKind: String, CaseIterable, Sendable {
    case person
    case externalPerson = "external_person"
    case system
    case systemDatabase = "system_db"
    case systemQueue = "system_queue"
    case externalSystem = "external_system"
    case externalSystemDatabase = "external_system_db"
    case externalSystemQueue = "external_system_queue"
    case container
    case containerDatabase = "container_db"
    case containerQueue = "container_queue"
    case externalContainer = "external_container"
    case externalContainerDatabase = "external_container_db"
    case externalContainerQueue = "external_container_queue"
    case component
    case componentDatabase = "component_db"
    case componentQueue = "component_queue"
    case externalComponent = "external_component"
    case externalComponentDatabase = "external_component_db"
    case externalComponentQueue = "external_component_queue"

    /// Whether it is drawn hollow with a dashed border.
    public var isExternal: Bool { rawValue.hasPrefix("external") }

    /// Whether its macro takes a technology before the description: a container's or a component's.
    var takesTechnology: Bool { Self.kindsTakingTechnology.contains(self) }

    /// The kinds whose name holds `container` or `component`, found once rather than searched for at every shape.
    private static let kindsTakingTechnology = Set(allCases.filter { kind in
        kind.rawValue.contains("container") || kind.rawValue.contains("component")
    })

    /// The kind's name as a shape's first line writes it between guillemets: `«external system»`.
    var guillemetedName: String { Self.guillemetedNames[self] ?? "" }

    private static let guillemetedNames = Dictionary(uniqueKeysWithValues: allCases.map { kind in
        (kind, "«" + kind.rawValue.replacingOccurrences(of: "_", with: " ") + "»")
    })
}

/// Mermaid's `nodeType` of a deployment node.
public enum C4DeploymentNodeKind: String, Sendable {
    case node
    case leftNode = "nodeL"
    case rightNode = "nodeR"
}

/// A relation from one element to another, with its label, its kind and its style.
public struct C4Relation: Equatable, Sendable {
    public internal(set) var kind: C4RelationKind
    /// The alias of each end, empty when a named argument stood there (`fromArgument`, `toArgument`).
    public internal(set) var from: String
    public internal(set) var to: String
    public internal(set) var label: String
    public internal(set) var fromArgument: C4NamedArgument?
    public internal(set) var toArgument: C4NamedArgument?
    public internal(set) var labelArgument: C4NamedArgument?
    public internal(set) var technology: String?
    public internal(set) var description: String?
    public internal(set) var sprite: String?
    public internal(set) var tags: String?
    public internal(set) var link: String?
    public internal(set) var textColor: String?
    public internal(set) var lineColor: String?
    /// `UpdateRelStyle`'s offsets as JavaScript's `parseInt` reads them; nil where it reads no number.
    public internal(set) var labelOffsetX: Double?
    public internal(set) var labelOffsetY: Double?
    public internal(set) var otherArguments: C4OtherArguments

    init(kind: C4RelationKind) {
        self.kind = kind
        from = ""
        to = ""
        label = ""
        otherArguments = C4OtherArguments()
    }

    /// Sets the field a named argument names, the offsets read as numbers, or keeps it among the other arguments.
    mutating func apply(_ argument: C4NamedArgument) {
        let value = argument.value
        switch argument.key {
        case "offsetX": labelOffsetX = JavaScriptInteger.parsed(value)
        case "offsetY": labelOffsetY = JavaScriptInteger.parsed(value)
        case "label": label = value
        case "descr": description = value
        case "techn": technology = value
        case "sprite": sprite = value
        case "tags": tags = value
        case "link": link = value
        case "textColor": textColor = value
        case "lineColor": lineColor = value
        default: otherArguments.set(argument)
        }
    }
}

/// Mermaid's type of a relation, by its macro: `Rel_Up` and `Rel_U` are `relUp`, `RelIndex` is `relation`.
public enum C4RelationKind: String, Sendable {
    case relation = "rel"
    case bidirectional = "birel"
    case relationUp = "rel_u"
    case relationDown = "rel_d"
    case relationLeft = "rel_l"
    case relationRight = "rel_r"
    case relationBack = "rel_b"

    /// Whether an arrowhead is drawn at the relation's start: both ways, or back.
    var pointsAtStart: Bool { self == .bidirectional || self == .relationBack }
    /// Whether one is drawn at its end: every kind but back.
    var pointsAtEnd: Bool { self != .relationBack }
}

/// A `$key="value"` argument.
public struct C4NamedArgument: Hashable, Sendable {
    public let key: String
    public let value: String
}

/// The named arguments that set no field, each name once with its last value, in the order first written.
public struct C4OtherArguments: Equatable, Sendable {
    public private(set) var arguments: [C4NamedArgument] = []
    private var indexByKey: [String: Int] = [:]

    public subscript(key: String) -> String? {
        indexByKey[key].map { index in arguments[index].value }
    }

    mutating func set(_ argument: C4NamedArgument) {
        if let index = indexByKey[argument.key] {
            arguments[index] = argument
        } else {
            indexByKey[argument.key] = arguments.count
            arguments.append(argument)
        }
    }
}

/// What broke a C4 diagram's syntax, as the parser Jison generates from Mermaid's grammar finds it.
public enum C4SyntaxProblem: Equatable, Sendable {
    /// Text no rule of the lexer reads (a space between a macro and its parenthesis, an unknown word).
    case unrecognizedText
    /// A token the grammar does not take where it stands, by Jison's name of it, with what the grammar expected there.
    case unexpectedToken(found: String, expected: C4ExpectedSyntax)
}

/// What the grammar expected where a C4 diagram's syntax broke, as Jison's message lists it.
public enum C4ExpectedSyntax: Equatable, Sendable {
    /// One of the five keywords (or a direction) at the start.
    case header
    /// A statement: a title, an accessibility statement, a macro.
    case statement
    /// A macro's arguments.
    case arguments
    /// The quoted value after `$key=`.
    case namedValue
    /// The value after `accTitle:` or `accDescr:`.
    case accessibilityValue
    case lineBreak
    case openingBrace
    /// After a boundary's arguments: its brace, or a line break before it.
    case lineBreakOrOpeningBrace
    /// After a statement: a line break, or the end of the text at the top level, or a boundary's closing brace in one.
    case lineBreakOrEnd
    case lineBreakOrClosingBrace
    /// The end of the text after its last line.
    case end
}
