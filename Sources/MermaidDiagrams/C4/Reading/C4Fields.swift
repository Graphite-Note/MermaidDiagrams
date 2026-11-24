/**
 * File: C4Fields.swift
 * --------------------
 * Layer: Core
 * Description: The fields of a C4 element and of a relation that a macro's places fill, and how a positional or a
 *              named argument fills them, as Pele's db.ts puts them, on the records' texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// A field of an element a macro's place fills.
enum C4ElementField {
    case type, description, technology, sprite, tags, link, backgroundColor, fontColor, borderColor, shadowing, shape, legendText, legendSprite
}

/// A field of a relation a macro's place fills.
enum C4RelationField {
    case technology, description, sprite, tags, link, textColor, lineColor
}

/// What a named argument's key names: a field of an element or of a relation, by Mermaid's names of them.
enum C4NamedKey {
    case label, type, description, technology, sprite, tags, link, backgroundColor, fontColor, borderColor, shadowing, shape, legendText
    case legendSprite, offsetX, offsetY, textColor, lineColor

    /// The key `bytes` spell, compared byte for byte (no name holds a character another spelling of which Swift would
    /// hold equal), or nil for a key that names no field.
    static func of(_ bytes: UnsafeBufferPointer<UInt8>) -> C4NamedKey? {
        for (name, key) in names where name.count == bytes.count && name.elementsEqual(bytes) { return key }
        return nil
    }

    private static let names: [([UInt8], C4NamedKey)] = [
        ("label", .label), ("type", .type), ("descr", .description), ("techn", .technology), ("sprite", .sprite), ("tags", .tags), ("link", .link),
        ("bgColor", .backgroundColor), ("fontColor", .fontColor), ("borderColor", .borderColor), ("shadowing", .shadowing), ("shape", .shape),
        ("legendText", .legendText), ("legendSprite", .legendSprite), ("offsetX", .offsetX), ("offsetY", .offsetY), ("textColor", .textColor),
        ("lineColor", .lineColor),
    ].map { name, key in (Array(name.utf8), key) }
}

extension C4Diagram {
    private func key(of argument: Int32) -> C4NamedKey? {
        withBytes(of: namedArguments[Int(argument)].key) { bytes in C4NamedKey.of(bytes) }
    }

    // MARK: - Elements

    /// Pele's `label`: a positional label, nothing for none, or a named argument applied to what it names, the label
    /// left empty.
    mutating func applyLabel(_ argument: C4ArgumentRecord?, to element: inout C4ElementRecord) {
        element.labelArgument = -1
        guard let argument else {
            element.label = C4DerivedText.empty
            return
        }
        if argument.isNamed {
            element.label = C4DerivedText.empty
            element.labelArgument = argument.named
            apply(argument.named, to: &element)
        } else {
            element.label = argument.text
        }
    }

    /// Pele's `put`: a positional argument fills the field of its place, a named one the field it names.
    mutating func put(_ field: C4ElementField, _ argument: C4ArgumentRecord?, to element: inout C4ElementRecord) {
        guard let argument else { return }
        if argument.isNamed { apply(argument.named, to: &element) } else { Self.set(field, argument.text, of: &element) }
    }

    /// Pele's `text`: as `put`, and an empty text when the place is not written and the field holds none.
    mutating func fill(_ field: C4ElementField, from argument: C4ArgumentRecord?, to element: inout C4ElementRecord) {
        guard argument == nil else { return put(field, argument, to: &element) }
        if field == .description, element.description.isNone { element.description = C4DerivedText.empty }
        if field == .technology, element.technology.isNone { element.technology = C4DerivedText.empty }
    }

    /// Sets the field a named argument names (`$descr`, `$bgColor`), or keeps it among the other arguments.
    mutating func apply(_ argument: Int32, to element: inout C4ElementRecord) {
        let value = namedArguments[Int(argument)].value
        switch key(of: argument) {
        case .label: element.label = value
        case .type: element.type = value
        case .description: element.description = value
        case .technology: element.technology = value
        case .sprite: element.sprite = value
        case .tags: element.tags = value
        case .link: element.link = value
        case .backgroundColor: element.backgroundColor = value
        case .fontColor: element.fontColor = value
        case .borderColor: element.borderColor = value
        case .shadowing: element.shadowing = value
        case .shape: element.shape = value
        case .legendText: element.legendText = value
        case .legendSprite: element.legendSprite = value
        default: setOtherArgument(argument, in: &element.otherArguments)
        }
    }

    private static func set(_ field: C4ElementField, _ text: C4Text, of element: inout C4ElementRecord) {
        switch field {
        case .type: element.type = text
        case .description: element.description = text
        case .technology: element.technology = text
        case .sprite: element.sprite = text
        case .tags: element.tags = text
        case .link: element.link = text
        case .backgroundColor: element.backgroundColor = text
        case .fontColor: element.fontColor = text
        case .borderColor: element.borderColor = text
        case .shadowing: element.shadowing = text
        case .shape: element.shape = text
        case .legendText: element.legendText = text
        case .legendSprite: element.legendSprite = text
        }
    }

    // MARK: - Relations

    mutating func applyLabel(_ argument: C4ArgumentRecord, to relation: inout C4RelationRecord) {
        relation.labelArgument = -1
        if argument.isNamed {
            relation.label = C4DerivedText.empty
            relation.labelArgument = argument.named
            apply(argument.named, to: &relation)
        } else {
            relation.label = argument.text
        }
    }

    mutating func put(_ field: C4RelationField, _ argument: C4ArgumentRecord?, to relation: inout C4RelationRecord) {
        guard let argument else { return }
        if argument.isNamed { apply(argument.named, to: &relation) } else { Self.set(field, argument.text, of: &relation) }
    }

    mutating func fill(_ field: C4RelationField, from argument: C4ArgumentRecord?, to relation: inout C4RelationRecord) {
        guard argument == nil else { return put(field, argument, to: &relation) }
        if field == .description, relation.description.isNone { relation.description = C4DerivedText.empty }
        if field == .technology, relation.technology.isNone { relation.technology = C4DerivedText.empty }
    }

    /// Sets the field a named argument names, the offsets read as numbers, or keeps it among the other arguments.
    mutating func apply(_ argument: Int32, to relation: inout C4RelationRecord) {
        let value = namedArguments[Int(argument)].value
        switch key(of: argument) {
        case .offsetX: relation.labelOffsetX = integer(value)
        case .offsetY: relation.labelOffsetY = integer(value)
        case .label: relation.label = value
        case .description: relation.description = value
        case .technology: relation.technology = value
        case .sprite: relation.sprite = value
        case .tags: relation.tags = value
        case .link: relation.link = value
        case .textColor: relation.textColor = value
        case .lineColor: relation.lineColor = value
        default: setOtherArgument(argument, in: &relation.otherArguments)
        }
    }

    private static func set(_ field: C4RelationField, _ text: C4Text, of relation: inout C4RelationRecord) {
        switch field {
        case .technology: relation.technology = text
        case .description: relation.description = text
        case .sprite: relation.sprite = text
        case .tags: relation.tags = text
        case .link: relation.link = text
        case .textColor: relation.textColor = text
        case .lineColor: relation.lineColor = text
        }
    }

    // MARK: - Other arguments

    /// The named argument kept among an element's or a relation's other arguments: in place of one with the same key, as
    /// a String key finds it, else after the others.
    private mutating func setOtherArgument(_ argument: Int32, in list: inout Int32) {
        let record = namedArguments[Int(argument)]
        if list < 0 {
            list = Int32(otherArgumentLists.count)
            otherArgumentLists.append([record])
            return
        }
        let key = text(record.key)
        if let index = otherArgumentLists[Int(list)].firstIndex(where: { other in text(other.key) == key }) {
            otherArgumentLists[Int(list)][index] = record
        } else {
            otherArgumentLists[Int(list)].append(record)
        }
    }
}
