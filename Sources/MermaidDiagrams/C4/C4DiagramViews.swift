/**
 * File: C4DiagramViews.swift
 * --------------------------
 * Layer: Core
 * Description: A C4 diagram's records made into the value types its views hand out: an element, a shape, a boundary
 *              and a relation with their texts as Strings, their named arguments and their other arguments.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension C4Diagram {
    /// The element a record holds, as Pele's `C4Db` holds it.
    func element(of record: C4ElementRecord) -> C4Element {
        var element = C4Element(alias: text(record.alias), label: text(record.label), type: string(record.type))
        element.aliasArgument = namedArgument(record.aliasArgument)
        element.labelArgument = namedArgument(record.labelArgument)
        element.parentBoundaryIndex = record.parentBoundaryIndex < 0 ? nil : Int(record.parentBoundaryIndex)
        element.description = string(record.description)
        element.technology = string(record.technology)
        element.sprite = string(record.sprite)
        element.tags = string(record.tags)
        element.link = string(record.link)
        element.backgroundColor = string(record.backgroundColor)
        element.fontColor = string(record.fontColor)
        element.borderColor = string(record.borderColor)
        element.shadowing = string(record.shadowing)
        element.shape = string(record.shape)
        element.legendText = string(record.legendText)
        element.legendSprite = string(record.legendSprite)
        element.otherArguments = otherArguments(record.otherArguments)
        return element
    }

    /// The relation a record holds.
    func relation(of record: C4RelationRecord) -> C4Relation {
        var relation = C4Relation(kind: record.kind)
        relation.from = text(record.from)
        relation.to = text(record.to)
        relation.label = text(record.label)
        relation.fromArgument = namedArgument(record.fromArgument)
        relation.toArgument = namedArgument(record.toArgument)
        relation.labelArgument = namedArgument(record.labelArgument)
        relation.technology = string(record.technology)
        relation.description = string(record.description)
        relation.sprite = string(record.sprite)
        relation.tags = string(record.tags)
        relation.link = string(record.link)
        relation.textColor = string(record.textColor)
        relation.lineColor = string(record.lineColor)
        relation.labelOffsetX = record.labelOffsetX
        relation.labelOffsetY = record.labelOffsetY
        relation.otherArguments = otherArguments(record.otherArguments)
        return relation
    }

    /// The named argument at `index` of the diagram's list, nil for -1.
    func namedArgument(_ index: Int32) -> C4NamedArgument? {
        guard index >= 0 else { return nil }
        let record = namedArguments[Int(index)]
        return C4NamedArgument(key: text(record.key), value: text(record.value))
    }

    private func otherArguments(_ index: Int32) -> C4OtherArguments {
        var arguments = C4OtherArguments()
        guard index >= 0 else { return arguments }
        for record in otherArgumentLists[Int(index)] { arguments.set(C4NamedArgument(key: text(record.key), value: text(record.value))) }
        return arguments
    }
}

extension C4Diagram: CustomReflectable {
    /// The diagram as 0.7.0 stored it: its level, texts, shapes, boundaries, relations and row counts, in that order, so
    /// that what reflects on a diagram sees its content rather than its records.
    public var customMirror: Mirror {
        Mirror(self, children: ["level": level, "title": title as Any, "accessibilityDescription": accessibilityDescription as Any, "shapes": shapes,
                                "boundaries": boundaries, "relations": relations, "shapesPerRow": shapesPerRow, "boundariesPerRow": boundariesPerRow],
               displayStyle: .struct)
    }
}
