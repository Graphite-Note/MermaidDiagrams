/**
 * File: EventModelSyntaxProblem.swift
 * -----------------------------------
 * Layer: Core
 * Description: What the event model reader found where the syntax of Mermaid's event modeling grammar broke.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// What the event model reader found where the syntax broke, beyond the problems every type shares.
public enum EventModelSyntaxProblem: Equatable, Sendable {
    /// `eventmodeling` is followed by more of a name (`eventmodelingx`): the keyword ends only at whitespace or a comment.
    case expectedKeyword
    /// A frame's number, one to three digits, was expected: after `tf`, `rf`, `->>`, `note` or `gwt`.
    case expectedFrameNumber
    /// A kind of entity was expected: `ui`, `cmd`, `command`, `evt`, `event`, `rmo`, `readmodel`, `pcr` or `processor`.
    case expectedEntityKind
    /// A name was expected: an entity's, a part of a qualified name after `.`, a data block's or one inside `[[ ]]`.
    case expectedName
    /// `[[` and a name are not followed by `]]`.
    case expectedClosingReference
    /// A data type between backticks was expected: `json`, `jsobj`, `figma`, `salt`, `uri`, `md`, `html` or `text`, then
    /// a backtick.
    case expectedDataType
    /// Data in braces or quotes on one line was expected after a frame's data type.
    case expectedInlineData
    /// A block was expected after `data` or `note`: `{`, a line break, its lines, and `}` at the start of a line.
    case expectedDataBlock
    /// A specification has no `given`, or no `then` after its statements.
    case expectedGiven
    case expectedThen
    /// A statement was expected: a frame, an entity, a data block, a note or a specification.
    case expectedStatement
    /// Two frames have the same number: Mermaid refuses the diagram.
    case duplicateFrame(identifier: String)
}
