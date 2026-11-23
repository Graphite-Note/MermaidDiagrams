/**
 * File: C4Token.swift
 * -------------------
 * Layer: Core
 * Description: The tokens of a C4 diagram, by the names Mermaid's Jison grammar gives them, the macro keywords they
 *              are read from, and the characters its lexer tests on UTF-16 code units.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A token of a C4 diagram, in the order of Pele's `tokens.ts`, by Jison's name (`PERSON`, `STR_KEY`). The order
/// matters: the shapes, boundaries, relations and updates are each a run of cases.
enum C4TokenKind: Int, Comparable {
    case end, error, directionTopToBottom, directionBottomToTop, directionRightToLeft, directionLeftToRight
    case title, accessibilityDescriptionStatement, accessibilityTitle, accessibilityTitleValue
    case accessibilityDescription, accessibilityDescriptionValue, accessibilityDescriptionMultilineValue, newline
    case context, container, component, dynamic, deployment
    case person, externalPerson, system, systemDatabase, systemQueue, externalSystem, externalSystemDatabase, externalSystemQueue
    case containerShape, containerDatabase, containerQueue, externalContainer, externalContainerDatabase, externalContainerQueue
    case componentShape, componentDatabase, componentQueue, externalComponent, externalComponentDatabase, externalComponentQueue
    case enterpriseBoundary, systemBoundary, boundary, containerBoundary, node, leftNode, rightNode
    case relation, bidirectionalRelation, relationUp, relationDown, relationLeft, relationRight, relationBack, relationIndex
    case updateElementStyle, updateRelationStyle, updateLayoutConfiguration
    case endOfFileInMacro, emptyArgument, string, namedArgumentKey, namedArgumentValue, openingBrace, closingBrace, endOfFile

    static func < (lhs: C4TokenKind, rhs: C4TokenKind) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Jison's name, as its messages give it.
    var grammarName: String { Self.grammarNames[rawValue] }

    /// A macro: a shape, a boundary, a relation or an update.
    var isMacro: Bool { self >= .person && self <= .updateLayoutConfiguration }

    /// A title or an accessibility statement.
    var isTitleOrAccessibility: Bool {
        self == .title || self == .accessibilityDescriptionStatement || self == .accessibilityTitle || self == .accessibilityDescription
            || self == .accessibilityDescriptionMultilineValue
    }

    /// The words the lexer reads as keywords, each to its token: the five headers, then the macros.
    static let keywords: [String: C4TokenKind] = [
        "C4Context": .context, "C4Container": .container, "C4Component": .component, "C4Dynamic": .dynamic, "C4Deployment": .deployment,
        "Person": .person, "Person_Ext": .externalPerson, "System": .system, "SystemDb": .systemDatabase, "SystemQueue": .systemQueue,
        "System_Ext": .externalSystem, "SystemDb_Ext": .externalSystemDatabase, "SystemQueue_Ext": .externalSystemQueue,
        "Container": .containerShape, "ContainerDb": .containerDatabase, "ContainerQueue": .containerQueue, "Container_Ext": .externalContainer,
        "ContainerDb_Ext": .externalContainerDatabase, "ContainerQueue_Ext": .externalContainerQueue,
        "Component": .componentShape, "ComponentDb": .componentDatabase, "ComponentQueue": .componentQueue, "Component_Ext": .externalComponent,
        "ComponentDb_Ext": .externalComponentDatabase, "ComponentQueue_Ext": .externalComponentQueue,
        "Enterprise_Boundary": .enterpriseBoundary, "System_Boundary": .systemBoundary, "Boundary": .boundary,
        "Container_Boundary": .containerBoundary, "Deployment_Node": .node, "Node": .node, "Node_L": .leftNode, "Node_R": .rightNode,
        "Rel": .relation, "BiRel": .bidirectionalRelation, "Rel_Up": .relationUp, "Rel_U": .relationUp, "Rel_Down": .relationDown,
        "Rel_D": .relationDown, "Rel_Left": .relationLeft, "Rel_L": .relationLeft, "Rel_Right": .relationRight, "Rel_R": .relationRight,
        "Rel_Back": .relationBack, "RelIndex": .relationIndex,
        "UpdateElementStyle": .updateElementStyle, "UpdateRelStyle": .updateRelationStyle, "UpdateLayoutConfig": .updateLayoutConfiguration,
    ]

    /// The longest keyword: a longer word is no keyword.
    static let longestKeywordLength = 19

    private static let grammarNames = [
        "$end", "INVALID", "direction_tb", "direction_bt", "direction_rl", "direction_lr", "title", "accDescription", "acc_title",
        "acc_title_value", "acc_descr", "acc_descr_value", "acc_descr_multiline_value", "NEWLINE", "C4_CONTEXT", "C4_CONTAINER",
        "C4_COMPONENT", "C4_DYNAMIC", "C4_DEPLOYMENT", "PERSON", "PERSON_EXT", "SYSTEM", "SYSTEM_DB", "SYSTEM_QUEUE", "SYSTEM_EXT",
        "SYSTEM_EXT_DB", "SYSTEM_EXT_QUEUE", "CONTAINER", "CONTAINER_DB", "CONTAINER_QUEUE", "CONTAINER_EXT", "CONTAINER_EXT_DB",
        "CONTAINER_EXT_QUEUE", "COMPONENT", "COMPONENT_DB", "COMPONENT_QUEUE", "COMPONENT_EXT", "COMPONENT_EXT_DB",
        "COMPONENT_EXT_QUEUE", "ENTERPRISE_BOUNDARY", "SYSTEM_BOUNDARY", "BOUNDARY", "CONTAINER_BOUNDARY", "NODE", "NODE_L", "NODE_R",
        "REL", "BIREL", "REL_U", "REL_D", "REL_L", "REL_R", "REL_B", "REL_INDEX", "UPDATE_EL_STYLE", "UPDATE_REL_STYLE",
        "UPDATE_LAYOUT_CONFIG", "EOF_IN_STRUCT", "ATTRIBUTE_EMPTY", "STR", "STR_KEY", "STR_VALUE", "LBRACE", "RBRACE", "EOF",
    ]
}

/// The tokens of a text: each one's kind and where its text starts and ends, in UTF-16 code units, as Pele keeps them.
struct C4Tokens {
    var kinds: [C4TokenKind] = []
    var starts: [Int] = []
    var ends: [Int] = []
}

/// The characters the lexer tests, on UTF-16 code units as Pele's `charCodeAt` reads them (`util/chars.ts`).
enum C4Characters {
    /// White space as JavaScript's `\s` sees it.
    static func isSpace(_ unit: UInt16) -> Bool {
        if unit < 128 { return unit == 32 || (unit >= 9 && unit <= 13) }
        return unit == 0xA0 || unit == 0x1680 || (unit >= 0x2000 && unit <= 0x200A) || unit == 0x2028 || unit == 0x2029 || unit == 0x202F
            || unit == 0x205F || unit == 0x3000 || unit == 0xFEFF
    }

    /// A character of `\w`: a letter, a digit or an underscore.
    static func isWord(_ unit: UInt16) -> Bool {
        (unit >= 48 && unit <= 57) || (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || unit == 95
    }

    /// A line terminator: what `.` does not match.
    static func isLineTerminator(_ unit: UInt16) -> Bool {
        unit == lineFeed || unit == carriageReturn || unit == 0x2028 || unit == 0x2029
    }

    /// `text` without white space at either end, as JavaScript's `trim` leaves it.
    static func trimmed(_ text: String) -> String {
        if let first = text.utf16.first, let last = text.utf16.last, !isSpace(first), !isSpace(last) { return text }
        let units = Array(text.utf16)
        guard let first = units.firstIndex(where: { unit in !isSpace(unit) }), let last = units.lastIndex(where: { unit in !isSpace(unit) }) else {
            return ""
        }
        if first == 0, last == units.count - 1 { return text }
        return String(decoding: units[first...last], as: UTF16.self)
    }

    static let lineFeed: UInt16 = 10
    static let carriageReturn: UInt16 = 13
    static let space: UInt16 = 32
    static let quotationMark: UInt16 = 34
    static let numberSign: UInt16 = 35
    static let dollarSign: UInt16 = 36
    static let percentSign: UInt16 = 37
    static let openingParenthesis: UInt16 = 40
    static let closingParenthesis: UInt16 = 41
    static let comma: UInt16 = 44
    static let colon: UInt16 = 58
    static let semicolon: UInt16 = 59
    static let equalsSign: UInt16 = 61
    static let lowercaseA: UInt16 = 97
    static let lowercaseT: UInt16 = 116
    static let openingBrace: UInt16 = 123
    static let closingBrace: UInt16 = 125
}
