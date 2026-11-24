/**
 * File: C4DiagramRecords.swift
 * ----------------------------
 * Layer: Core
 * Description: The small records a C4 diagram is read into: texts as ranges of its source's bytes or of its own derived
 *              bytes, each element's fields, shapes, boundaries, relations and named arguments, with no String.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A text of a C4 diagram: a range of its source's bytes, or of its derived bytes (the texts the reading makes, the
/// names it writes in) from `derivedOffset` on; `none` for a field not written.
struct C4Text: Equatable, Sendable {
    var start: Int32
    var end: Int32

    /// Offsets from here on are the derived bytes', less this.
    static let derivedOffset: Int32 = 1 << 30
    static let none = C4Text(start: -1, end: -1)

    init(start: Int32, end: Int32) {
        self.start = start
        self.end = end
    }

    init(start: Int, end: Int) {
        self.start = Int32(truncatingIfNeeded: start)
        self.end = Int32(truncatingIfNeeded: end)
    }

    /// A range of the derived bytes, `start` and `end` counted from their first byte.
    static func derived(start: Int, end: Int) -> C4Text {
        C4Text(start: derivedOffset + Int32(truncatingIfNeeded: start), end: derivedOffset + Int32(truncatingIfNeeded: end))
    }

    var isNone: Bool { start < 0 }
    var isDerived: Bool { start >= Self.derivedOffset }
    var count: Int { isNone ? 0 : Int(end - start) }
    /// Written and empty: a field Pele sets to `""`.
    var isEmptyText: Bool { !isNone && end == start }
    /// Not written or empty, as a Swift `String?` that is nil or empty.
    var isNoneOrEmpty: Bool { end <= start }
}

/// A `$key="value"` argument: its key's and its value's texts.
struct C4NamedArgumentRecord: Equatable, Sendable {
    var key: C4Text
    var value: C4Text
}

/// What a shape and a boundary share: the fields Mermaid's macros and `UpdateElementStyle` set, as texts. `name` is
/// the alias's interned name (`C4NameTable`), -1 when a named argument stood in the alias's place.
struct C4ElementRecord: Equatable, Sendable {
    var alias: C4Text
    var name: Int32 = -1
    var label: C4Text
    /// The named arguments written where the alias or the label belongs, by index in the diagram's list, or -1.
    var aliasArgument: Int32 = -1
    var labelArgument: Int32 = -1
    /// The boundary it was last written in, by index in the diagram's boundaries; -1 for the top level's own.
    var parentBoundaryIndex: Int32 = -1
    var type = C4Text.none
    var description = C4Text.none
    var technology = C4Text.none
    var sprite = C4Text.none
    var tags = C4Text.none
    var link = C4Text.none
    var backgroundColor = C4Text.none
    var fontColor = C4Text.none
    var borderColor = C4Text.none
    var shadowing = C4Text.none
    var shape = C4Text.none
    var legendText = C4Text.none
    var legendSprite = C4Text.none
    /// The named arguments that set no field, by index in the diagram's lists of other arguments, or -1 for none.
    var otherArguments: Int32 = -1

    init(alias: C4Text = .none, label: C4Text = .none, type: C4Text = .none) {
        self.alias = alias
        self.label = label
        self.type = type
    }
}

struct C4ShapeRecord: Equatable, Sendable {
    var element: C4ElementRecord
    var kind: C4ShapeKind
}

struct C4BoundaryRecord: Equatable, Sendable {
    var element: C4ElementRecord
    var deploymentNode: C4DeploymentNodeKind?
}

/// A relation's fields as texts; `fromName` and `toName` are its ends' interned names, -1 where a named argument stood.
struct C4RelationRecord: Equatable, Sendable {
    var kind: C4RelationKind
    var from = C4Text.none
    var to = C4Text.none
    var fromName: Int32 = -1
    var toName: Int32 = -1
    var label = C4Text.none
    var fromArgument: Int32 = -1
    var toArgument: Int32 = -1
    var labelArgument: Int32 = -1
    var technology = C4Text.none
    var description = C4Text.none
    var sprite = C4Text.none
    var tags = C4Text.none
    var link = C4Text.none
    var textColor = C4Text.none
    var lineColor = C4Text.none
    var labelOffsetX: Double?
    var labelOffsetY: Double?
    var otherArguments: Int32 = -1

    init(kind: C4RelationKind) {
        self.kind = kind
    }
}
