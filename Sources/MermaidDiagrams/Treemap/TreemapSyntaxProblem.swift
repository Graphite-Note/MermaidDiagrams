/**
 * File: TreemapSyntaxProblem.swift
 * --------------------------------
 * Layer: Core
 * Description: What a treemap's text can get wrong that no other diagram can.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A problem of a treemap's own syntax.
public enum TreemapSyntaxProblem: Equatable, Sendable {
    /// A row starts with something other than a quoted name or `classDef`.
    case expectedNameOrClassDefinition
    /// A leaf's `:` or `,` is not followed by its value: digits, with `.`, `,` and `_`.
    case expectedValue
    /// `:::` is not followed by a class's name.
    case expectedClassName
}
