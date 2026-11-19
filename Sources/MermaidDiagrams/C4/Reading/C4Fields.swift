/**
 * File: C4Fields.swift
 * --------------------
 * Layer: Core
 * Description: The fields of a C4 element and of a relation that a macro's places fill, and how a positional or a
 *              named argument fills them, as Pele's db.ts puts them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A field of an element a macro's place fills.
enum C4ElementField {
    case type, description, technology, sprite, tags, link, backgroundColor, fontColor, borderColor, shadowing, shape, legendText, legendSprite
}

/// A field of a relation a macro's place fills.
enum C4RelationField {
    case technology, description, sprite, tags, link, textColor, lineColor
}

extension C4Element {
    /// Pele's `label`: a positional label, nothing for none, or a named argument applied to what it names, the label
    /// left empty.
    mutating func applyLabel(_ argument: C4Argument?) {
        labelArgument = nil
        switch argument {
        case .positional(let text): label = text
        case .named(let named):
            label = ""
            labelArgument = named
            apply(named)
        case nil: label = ""
        }
    }

    /// Pele's `put`: a positional argument fills the field of its place, a named one the field it names.
    mutating func put(_ field: C4ElementField, _ argument: C4Argument?) {
        switch argument {
        case .positional(let text): set(field, text)
        case .named(let named): apply(named)
        case nil: break
        }
    }

    /// Pele's `text`: as `put`, and an empty text when the place is not written and the field holds none.
    mutating func fill(_ field: C4ElementField, from argument: C4Argument?) {
        guard argument == nil else { return put(field, argument) }
        if field == .description, description == nil { description = "" }
        if field == .technology, technology == nil { technology = "" }
    }

    private mutating func set(_ field: C4ElementField, _ text: String) {
        switch field {
        case .type: type = text
        case .description: description = text
        case .technology: technology = text
        case .sprite: sprite = text
        case .tags: tags = text
        case .link: link = text
        case .backgroundColor: backgroundColor = text
        case .fontColor: fontColor = text
        case .borderColor: borderColor = text
        case .shadowing: shadowing = text
        case .shape: shape = text
        case .legendText: legendText = text
        case .legendSprite: legendSprite = text
        }
    }
}

extension C4Relation {
    mutating func applyLabel(_ argument: C4Argument) {
        labelArgument = nil
        switch argument {
        case .positional(let text): label = text
        case .named(let named):
            label = ""
            labelArgument = named
            apply(named)
        }
    }

    mutating func put(_ field: C4RelationField, _ argument: C4Argument?) {
        switch argument {
        case .positional(let text): set(field, text)
        case .named(let named): apply(named)
        case nil: break
        }
    }

    mutating func fill(_ field: C4RelationField, from argument: C4Argument?) {
        guard argument == nil else { return put(field, argument) }
        if field == .description, description == nil { description = "" }
        if field == .technology, technology == nil { technology = "" }
    }

    private mutating func set(_ field: C4RelationField, _ text: String) {
        switch field {
        case .technology: technology = text
        case .description: description = text
        case .sprite: sprite = text
        case .tags: tags = text
        case .link: link = text
        case .textColor: textColor = text
        case .lineColor: lineColor = text
        }
    }
}
