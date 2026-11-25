/**
 * File: C4DiagramBuilderRelations.swift
 * -------------------------------------
 * Layer: Core
 * Description: The relations of a C4 diagram's building and the macros that update what is written (`UpdateElementStyle`,
 *              `UpdateRelStyle`, `UpdateLayoutConfig`), as Pele's db.ts applies them, on ranges and interned names.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension C4DiagramBuilder {
    /// `from, to, label, ?techn, ?descr, ?sprite, ?tags, $link`; nothing without the first three. A relation between two
    /// aliases already related is that relation again, of the new kind.
    mutating func addRelation(_ kind: C4RelationKind, arguments: ScratchSpan<C4ArgumentRecord>) throws(MermaidDiagramReadError) {
        guard arguments.count >= 3 else { return }
        let fromName = arguments[0].isNamed ? -1 : name(of: arguments[0].text)
        let toName = arguments[1].isNamed ? -1 : name(of: arguments[1].text)
        let ends: UInt64? = fromName >= 0 && toName >= 0 ? Self.endsKey(fromName, toName) : nil
        let index: Int
        if let ends, let known = relationIndexByEnds[ends] {
            index = Int(known)
        } else {
            guard diagram.relationRecords.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
            index = diagram.relationRecords.count
            var relation = C4RelationRecord(kind: kind)
            if let ends { relationIndexByEnds[ends] = Int32(index) }
            if arguments[0].isNamed { relation.fromArgument = arguments[0].named } else { relation.from = arguments[0].text }
            if arguments[1].isNamed { relation.toArgument = arguments[1].named } else { relation.to = arguments[1].text }
            relation.fromName = fromName
            relation.toName = toName
            diagram.relationRecords.append(relation)
        }
        var relation = diagram.relationRecords[index]
        relation.kind = kind
        diagram.applyLabel(arguments[2], to: &relation)
        diagram.fill(.technology, from: Self.argument(arguments, 3), to: &relation)
        diagram.fill(.description, from: Self.argument(arguments, 4), to: &relation)
        diagram.put(.sprite, Self.argument(arguments, 5), to: &relation)
        diagram.put(.tags, Self.argument(arguments, 6), to: &relation)
        diagram.put(.link, Self.argument(arguments, 7), to: &relation)
        diagram.relationRecords[index] = relation
    }

    /// The key of a relation between two names.
    private static func endsKey(_ from: Int32, _ to: Int32) -> UInt64 {
        UInt64(UInt32(bitPattern: from)) << 32 | UInt64(UInt32(bitPattern: to))
    }

    // MARK: - Updates

    /// `elementName, ?bgColor, ?fontColor, ?borderColor, ?shadowing, ?shape, ?sprite, ?techn, ?legendText, ?legendSprite`.
    mutating func updateElementStyle(_ arguments: ScratchSpan<C4ArgumentRecord>) {
        guard !arguments[0].isNamed else { return }
        let name = Int(name(of: arguments[0].text))
        if shapeIndexByName[name] >= 0 {
            let index = Int(shapeIndexByName[name])
            var element = diagram.shapeRecords[index].element
            updateStyle(of: &element, arguments: arguments)
            diagram.shapeRecords[index].element = element
        } else if boundaryIndexByName[name] >= 0 {
            let index = Int(boundaryIndexByName[name])
            var element = diagram.boundaryRecords[index].element
            updateStyle(of: &element, arguments: arguments)
            diagram.boundaryRecords[index].element = element
        }
    }

    private mutating func updateStyle(of element: inout C4ElementRecord, arguments: ScratchSpan<C4ArgumentRecord>) {
        for (offset, field) in Self.styleFields.enumerated() { diagram.put(field, Self.argument(arguments, offset + 1), to: &element) }
    }

    private static let styleFields: [C4ElementField] = [.backgroundColor, .fontColor, .borderColor, .shadowing, .shape, .sprite, .technology, .legendText,
                                                        .legendSprite]

    /// `from, to, ?textColor, ?lineColor, ?offsetX, ?offsetY`, for a relation already written.
    mutating func updateRelationStyle(_ arguments: ScratchSpan<C4ArgumentRecord>) {
        guard arguments.count >= 2, !arguments[0].isNamed, !arguments[1].isNamed else { return }
        let ends = Self.endsKey(name(of: arguments[0].text), name(of: arguments[1].text))
        guard let known = relationIndexByEnds[ends] else { return }
        let index = Int(known)
        var relation = diagram.relationRecords[index]
        diagram.put(.textColor, Self.argument(arguments, 2), to: &relation)
        diagram.put(.lineColor, Self.argument(arguments, 3), to: &relation)
        if let offset = Self.argument(arguments, 4) {
            if offset.isNamed { diagram.apply(offset.named, to: &relation) } else { relation.labelOffsetX = diagram.integer(offset.text) }
        }
        if let offset = Self.argument(arguments, 5) {
            if offset.isNamed { diagram.apply(offset.named, to: &relation) } else { relation.labelOffsetY = diagram.integer(offset.text) }
        }
        diagram.relationRecords[index] = relation
    }

    /// `?c4ShapeInRow, ?c4BoundaryInRow`. As in Mermaid, the place decides which one a value sets, not its name; a value
    /// under one is left out.
    mutating func updateLayoutConfiguration(_ arguments: ScratchSpan<C4ArgumentRecord>) {
        func count(_ argument: C4ArgumentRecord?) -> Int? {
            guard let argument else { return nil }
            let text = argument.isNamed ? diagram.namedArguments[Int(argument.named)].value : argument.text
            guard let value = diagram.integer(text), value >= 1 else { return nil }
            return Int(min(value, Self.largestRowCount))
        }
        if let shapes = count(Self.argument(arguments, 0)) { diagram.shapesPerRow = shapes }
        if let boundaries = count(Self.argument(arguments, 1)) { diagram.boundariesPerRow = boundaries }
    }

    /// A row holds at most this many: more than any diagram within the limits has, so that it acts as Mermaid's any.
    private static let largestRowCount: Double = 1_000_000_000
}

extension C4Diagram {
    /// JavaScript's `parseInt` of a text, read on its bytes.
    func integer(_ text: C4Text) -> Double? {
        withBytes(of: text) { bytes in JavaScriptInteger.parsed(utf8: bytes) }
    }
}
