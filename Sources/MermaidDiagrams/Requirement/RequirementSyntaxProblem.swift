/**
 * File: RequirementSyntaxProblem.swift
 * ------------------------------------
 * Layer: Core
 * Description: What the requirement diagram reader found where the syntax of Mermaid's requirement grammar broke.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What the requirement diagram reader found where the syntax broke, beyond the problems every type shares, by what Pele's
/// parser and Mermaid's grammar expected there.
public enum RequirementSyntaxProblem: Equatable, Sendable {
    /// The keyword is not `requirementDiagram` (in any case) on its own: `requirement` alone, or more of a name after it.
    case expectedKeyword
    /// A line break was expected: after the keyword, after a field's value, after a body's opening brace.
    case expectedLineBreak
    /// A name, quoted or not, was expected: a requirement's or an element's, a field's value, a relation's second end.
    case expectedName
    /// `{` was expected after a requirement's or an element's name and classes.
    case expectedOpeningBrace
    /// A field was expected in a requirement's body (`id`, `text`, `risk`, `verifymethod`) or `}`.
    case expectedRequirementField
    /// A field was expected in an element's body (`type`, `docref`) or `}`.
    case expectedElementField
    /// `:` was expected after a field's name.
    case expectedColon
    /// `low`, `medium` or `high` was expected after `risk:`.
    case expectedRisk
    /// `analysis`, `demonstration`, `inspection` or `test` was expected after `verifymethod:`.
    case expectedVerificationMethod
    /// A relation's kind was expected after `-` or `<-`: `contains`, `copies`, `derives`, `satisfies`, `verifies`,
    /// `refines` or `traces`.
    case expectedRelationKind
    /// `->` was expected after `- kind`, or `-` after `<- kind`.
    case expectedArrow
    /// A list of names was expected: after `style`, `classDef` or `class`, after `:::`, or after a comma.
    case expectedNameList
    /// A style declaration was expected after `style` or `classDef` and the names: letters, digits, `:`, `;`, `-`, `#`.
    case expectedStyle
    /// `:::` and classes, `-` or `<-` was expected after a name at the start of a statement.
    case expectedNameStatement
    /// A statement was expected: a requirement, an element, a relation, a direction, a style, a class or an
    /// accessibility statement.
    case expectedStatement
    /// The styles copied onto nodes by `style`, `class`, `classDef` and `:::`, with the classes given, are more than
    /// `limit`: Pele's refusal of a short text that asks for hundreds of millions of copies.
    case tooManyStyleCopies(limit: Int)
}
