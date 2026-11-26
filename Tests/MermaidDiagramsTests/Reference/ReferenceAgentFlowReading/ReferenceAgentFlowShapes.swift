/**
 * File: ReferenceAgentFlowShapes.swift
 * ------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowShapes.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

enum ReferenceAgentFlowShapes {
    /// The names authors give the shapes that carry meaning in an agent flow.
    static let aliases: [String: String] = [
        "task": "roundedRect", "tool": "subroutine", "input": "lean-right", "decision": "diamond", "refdoc": "lin-doc",
        "action": "hexagon", "round": "rect",
    ]

    static let removedShapes: Set<String> = [
        "doc", "stadium", "terminal", "circle", "trapezoid", "inv_trapezoid", "inv-trapezoid", "doublecircle", "double-circle",
        "typeDeclaration", "procs", "lean_left", "lean-left", "in-out", "cylinder", "ellipse", "odd", "tag-rect", "tagged-rectangle",
        "delay", "half-rounded-rectangle", "lin-rect", "lined-rectangle", "win-pane", "window-pane", "curv-trap", "curved-trapezoid",
    ]

    static let allowedShapes: Set<String> = [
        "roundedRect", "subroutine", "subprocess", "subproc", "framed-rectangle", "lean-right", "diamond", "lin-doc", "lined-document",
        "hexagon", "hex", "connector", "collapsedGroup",
    ]

    static let defaultShape = "roundedRect"

    /// The shapes Mermaid's flowchart accepts by name without documenting them (Pele's `INTERNAL`).
    private static let undocumentedShapes: Set<String> = [
        "state", "choice", "note", "composite", "rectWithTitle", "labelRect", "block_arrow", "collapsedGroup", "iconSquare", "iconCircle",
        "icon", "iconRounded", "imageSquare", "anchor", "kanbanItem", "mindmapCircle", "defaultMindmapNode", "classBox", "erBox",
        "requirementBox", "usecaseActor", "usecaseActorHollow", "usecaseActorAwesome", "usecaseActorIcon", "usecaseBusiness",
        "usecaseEllipse", "usecaseJsonTable",
    ]

    static func resolvingAlias(_ shape: String) -> String {
        aliases[shape] ?? shape
    }

    /// Whether Mermaid's flowchart knows the shape; it looks a name up with `in` on a plain object, so `constructor`
    /// passes too.
    static func isValidShape(_ name: String) -> Bool {
        FlowchartNodeShape(shapeName: name) != nil || undocumentedShapes.contains(name) || name == "constructor"
    }

    /// A node's shape reduced to one an agent flow draws, and the diagnostic with Pele's words when it was removed or is
    /// not supported.
    static func normalized(_ shape: String?) -> (shape: String, problem: (identifier: AgentFlowDiagnostic.Identifier, message: String)?) {
        let written = shape == nil || shape == "squareRect" || shape == "rect" ? defaultShape : shape ?? defaultShape
        if removedShapes.contains(written) {
            return (defaultShape, (.shapeRemoved, "shape \"\(written)\" was removed in v0.8.1, using \"\(defaultShape)\""))
        }
        if !allowedShapes.contains(written) {
            return (defaultShape, (.shapeUnsupported, "shape \"\(written)\" is not supported, using \"\(defaultShape)\""))
        }
        return (written, nil)
    }

    /// The flowchart shape an agent flow's shape is drawn in (Pele's `canonicalShape`): a connector is a rectangle.
    static func drawnShape(_ shape: String) -> FlowchartNodeShape {
        switch shape {
        case "diamond": .diamond
        case "hexagon": .hexagon
        default: FlowchartNodeShape(shapeName: shape) ?? .rectangle
        }
    }

    /// What a node means by its shape: a tool definition, an action, an input, a reference document, a decision, or a
    /// task (Pele's `vertexKind`).
    static func kind(of vertex: AgentFlowVertex) -> AgentFlowVertexKind {
        if let type = vertex.type, toolShapes.contains(type) { return .tool }
        switch vertex.type.map(resolvingAlias) {
        case "hexagon", "hex": return .action
        case "lean-right", "lean_right": return .input
        case "lin-doc", "lined-document": return .refdoc
        case "diamond": return .decision
        default: return .task
        }
    }

    static let toolShapes: Set<String> = ["subroutine", "subprocess", "subproc", "framed-rectangle", "tool"]
}
