/**
 * File: ReferenceC4Fields.swift
 * -----------------------------
 * Layer: Tests
 * Description: The 0.7.0 C4Fields kept as the reference the flat C4 reader is checked against: the fields of a C4
 *              element and of a relation that a macro's places fill, and how a positional or a named argument fills
 *              them, as Pele's db.ts puts them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// A field of an element a macro's place fills.
enum ReferenceC4ElementField {
    case type, description, technology, sprite, tags, link, backgroundColor, fontColor, borderColor, shadowing, shape, legendText, legendSprite
}

/// A field of a relation a macro's place fills.
enum ReferenceC4RelationField {
    case technology, description, sprite, tags, link, textColor, lineColor
}

extension C4Element {
    /// Pele's `label`: a positional label, nothing for none, or a named argument applied to what it names, the label
    /// left empty.
    mutating func referenceApplyLabel(_ argument: ReferenceC4Argument?) {
        labelArgument = nil
        switch argument {
        case .positional(let text): label = text
        case .named(let named):
            label = ""
            labelArgument = named
            referenceApply(named)
        case nil: label = ""
        }
    }

    /// Pele's `put`: a positional argument fills the field of its place, a named one the field it names.
    mutating func referencePut(_ field: ReferenceC4ElementField, _ argument: ReferenceC4Argument?) {
        switch argument {
        case .positional(let text): referenceSet(field, text)
        case .named(let named): referenceApply(named)
        case nil: break
        }
    }

    /// Pele's `text`: as `put`, and an empty text when the place is not written and the field holds none.
    mutating func referenceFill(_ field: ReferenceC4ElementField, from argument: ReferenceC4Argument?) {
        guard argument == nil else { return referencePut(field, argument) }
        if field == .description, description == nil { description = "" }
        if field == .technology, technology == nil { technology = "" }
    }

    private mutating func referenceSet(_ field: ReferenceC4ElementField, _ text: String) {
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
    mutating func referenceApplyLabel(_ argument: ReferenceC4Argument) {
        labelArgument = nil
        switch argument {
        case .positional(let text): label = text
        case .named(let named):
            label = ""
            labelArgument = named
            referenceApply(named)
        }
    }

    mutating func referencePut(_ field: ReferenceC4RelationField, _ argument: ReferenceC4Argument?) {
        switch argument {
        case .positional(let text): referenceSet(field, text)
        case .named(let named): referenceApply(named)
        case nil: break
        }
    }

    mutating func referenceFill(_ field: ReferenceC4RelationField, from argument: ReferenceC4Argument?) {
        guard argument == nil else { return referencePut(field, argument) }
        if field == .description, description == nil { description = "" }
        if field == .technology, technology == nil { technology = "" }
    }

    private mutating func referenceSet(_ field: ReferenceC4RelationField, _ text: String) {
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
