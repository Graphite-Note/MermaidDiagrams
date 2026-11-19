/**
 * File: FlowchartNodeShapeNames.swift
 * -----------------------------------
 * Layer: Core
 * Description: Mermaid's names for each flowchart node shape, and the names it accepts without documenting them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension FlowchartNodeShape {
    /// Mermaid's documented names for each shape, the short name first, in the order and spelling of Pele's
    /// `flowchart/shapes.ts`; `odd` is `asymmetric`.
    static let documentedNames: [(FlowchartNodeShape, [String])] = [
        (.rectangle, ["rect", "proc", "process", "rectangle", "squareRect"]),
        (.roundedRectangle, ["rounded", "event", "roundedRect"]),
        (.stadium, ["stadium", "terminal", "pill"]),
        (.subroutine, ["fr-rect", "subprocess", "subproc", "framed-rectangle", "subroutine"]),
        (.cylinder, ["cyl", "db", "database", "cylinder"]),
        (.dataStore, ["datastore", "data-store"]),
        (.folder, ["folder", "directory"]),
        (.bucket, ["bucket"]),
        (.console, ["console"]),
        (.browser, ["browser"]),
        (.person, ["person"]),
        (.circle, ["circle", "circ"]),
        (.bang, ["bang"]),
        (.cloud, ["cloud"]),
        (.diamond, ["diam", "decision", "diamond", "question"]),
        (.hexagon, ["hex", "hexagon", "prepare"]),
        (.leanRight, ["lean-r", "lean-right", "in-out", "lean_right"]),
        (.leanLeft, ["lean-l", "lean-left", "out-in", "lean_left"]),
        (.trapezoid, ["trap-b", "priority", "trapezoid-bottom", "trapezoid"]),
        (.invertedTrapezoid, ["trap-t", "manual", "trapezoid-top", "inv-trapezoid", "inv_trapezoid"]),
        (.doubleCircle, ["dbl-circ", "double-circle", "doublecircle"]),
        (.text, ["text"]),
        (.card, ["notch-rect", "card", "notched-rectangle"]),
        (.linedRectangle, ["lin-rect", "lined-rectangle", "lined-process", "lin-proc", "shaded-process"]),
        (.smallCircle, ["sm-circ", "start", "small-circle", "stateStart"]),
        (.framedCircle, ["fr-circ", "stop", "framed-circle", "stateEnd"]),
        (.forkJoin, ["fork", "join", "forkJoin"]),
        (.hourglass, ["hourglass", "collate"]),
        (.leftBrace, ["brace", "comment", "brace-l"]),
        (.rightBrace, ["brace-r"]),
        (.braces, ["braces"]),
        (.lightningBolt, ["bolt", "com-link", "lightning-bolt"]),
        (.document, ["doc", "document"]),
        (.delay, ["delay", "half-rounded-rectangle"]),
        (.horizontalCylinder, ["h-cyl", "das", "horizontal-cylinder"]),
        (.linedCylinder, ["lin-cyl", "disk", "lined-cylinder"]),
        (.curvedTrapezoid, ["curv-trap", "curved-trapezoid", "display"]),
        (.dividedRectangle, ["div-rect", "div-proc", "divided-rectangle", "divided-process"]),
        (.triangle, ["tri", "extract", "triangle"]),
        (.windowPane, ["win-pane", "internal-storage", "window-pane"]),
        (.filledCircle, ["f-circ", "junction", "filled-circle"]),
        (.notchedPentagon, ["notch-pent", "loop-limit", "notched-pentagon"]),
        (.flippedTriangle, ["flip-tri", "manual-file", "flipped-triangle"]),
        (.slopedRectangle, ["sl-rect", "manual-input", "sloped-rectangle"]),
        (.stackedDocument, ["docs", "documents", "st-doc", "stacked-document"]),
        (.stackedRectangle, ["st-rect", "procs", "processes", "stacked-rectangle"]),
        (.bowTieRectangle, ["bow-rect", "stored-data", "bow-tie-rectangle"]),
        (.crossedCircle, ["cross-circ", "summary", "crossed-circle"]),
        (.taggedDocument, ["tag-doc", "tagged-document"]),
        (.taggedRectangle, ["tag-rect", "tagged-rectangle", "tag-proc", "tagged-process"]),
        (.paperTape, ["flag", "paper-tape"]),
        (.asymmetric, ["odd", "rect_left_inv_arrow"]),
        (.linedDocument, ["lin-doc", "lined-document"]),
    ]

    /// The shapes Mermaid accepts by name without documenting them, in lowercase (the others are refused for their
    /// capitals): Pele draws each as a rectangle.
    static let undocumentedLowercaseNames: Set<String> = ["state", "choice", "note", "composite", "anchor", "icon"]

    /// The shape a `shape:` attribute's value names, as Pele's flowchart database reads it: a name with a capital or
    /// an underscore, or one Mermaid does not know, is refused; an undocumented one is drawn as a rectangle.
    static func named(_ name: String, line: Int) throws(MermaidDiagramReadError) -> FlowchartNodeShape {
        guard name == name.lowercased(), !name.contains("_") else {
            throw .invalidSyntax(line: line, problem: .shapeNameNotLowercase(name))
        }
        if let shape = FlowchartNodeShape(shapeName: name) { return shape }
        guard undocumentedLowercaseNames.contains(name) else { throw .invalidSyntax(line: line, problem: .unknownShape(name)) }
        return .rectangle
    }
}
