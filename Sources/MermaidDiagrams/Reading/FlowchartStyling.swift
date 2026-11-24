/**
 * File: FlowchartStyling.swift
 * ----------------------------
 * Layer: Core
 * Description: What a flowchart's `classDef`, `class`, `:::`, `style` and `linkStyle` statements set, recorded as they
 *              are read and given to the nodes and edges once the text is read, only when a statement styled anything.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 24/11/2026
 */

/// What the statements that style a flowchart set, by name index, in the order written.
struct FlowchartStyling {
    /// What each `classDef` sets, by class name (a class defined again keeps what it set and takes what the new one sets).
    var classStyles: [String: DiagramElementStyle] = [:]
    /// The classes given to nodes by `class` and `:::`, in the order written; resolved when the text ends, since `classDef`
    /// may come after them.
    var classAssignments: [(name: Int32, className: String)] = []
    /// What `style` sets, by node name, in the order written.
    var nodeStyleStatements: [(name: Int32, style: DiagramElementStyle)] = []
    /// What `linkStyle` sets for every edge (`default`) or for the edges at some indexes, in the order written.
    var linkStyleStatements: [(indices: [Int]?, style: DiagramElementStyle)] = []
}

extension FlowchartParser {
    /// Records what a statement that styles the diagram sets; a statement that could not be read is counted as not applied.
    mutating func apply(_ statement: FlowchartStyleStatement?) {
        if styling == nil { styling = FlowchartStyling() }
        guard let statement else {
            unappliedStatementCount += 1
            return
        }
        switch statement {
        case .classDefinition(let names, let declarations):
            let (style, hasUnappliedDeclaration) = (declarations.style, declarations.hasUnappliedDeclaration)
            for name in names {
                let merged = (styling?.classStyles[name] ?? DiagramElementStyle()).overridden(by: style)
                styling?.classStyles[name] = merged
            }
            if hasUnappliedDeclaration { unappliedStatementCount += 1 }
        case .classAssignment(let identifiers, let className):
            for identifier in identifiers {
                let name = Int32(lists.names.intern(Array(identifier.utf8), in: bytes))
                styling?.classAssignments.append((name, className))
            }
        case .nodeStyle(let identifier, let declarations):
            let name = lists.names.intern(Array(identifier.utf8), in: bytes)
            addNodeNamedByStyle(name)
            let (style, hasUnappliedDeclaration) = (declarations.style, declarations.hasUnappliedDeclaration)
            styling?.nodeStyleStatements.append((Int32(name), style))
            if hasUnappliedDeclaration { unappliedStatementCount += 1 }
        case .linkStyle(let indices, let declarations):
            var (style, hasUnappliedDeclaration) = (declarations.style, declarations.hasUnappliedDeclaration)
            // An edge has no inside to fill; its text color is not set from here.
            style.fill = nil
            if style.textColor != nil {
                style.textColor = nil
                hasUnappliedDeclaration = true
            }
            styling?.linkStyleStatements.append((indices, style))
            if hasUnappliedDeclaration { unappliedStatementCount += 1 }
        }
    }

    /// `A:::name`: the node named `name` takes the class.
    mutating func assignClass(toNodeNamed name: Int, className: String) {
        if styling == nil { styling = FlowchartStyling() }
        styling?.classAssignments.append((Int32(name), className))
    }

    /// `style X …` adds X as a node when nothing has named it yet, as Pele's database does (its style statement calls
    /// `addVertex`), without making it a member of an open group, as Pele's parser lists no member for a style statement.
    /// A group's own identifier is left to the group, and past the node limit nothing is added (the style is then unapplied).
    private mutating func addNodeNamedByStyle(_ name: Int) {
        let entry = lists.names.names[name]
        guard entry.nodeIndex < 0, entry.endedGroupIndex < 0, !lists.openGroups.contains(where: { group in group.writtenName == Int32(name) }),
              parts.nodes.count < limits.maximumNodeCount else { return }
        let identifier = parts.sideRange(of: lists.names.bytes(of: name, in: bytes))
        lists.names.names[name].nodeIndex = Int32(parts.nodes.count)
        let label = decoded(DiagramLabelDecoder.label(from: parts.string(identifier, in: bytes), form: .plain))
        parts.nodes.append(FlowchartNodeRecord(identifier: identifier, label: label, shape: .rectangle))
    }

    /// Gives the nodes and edges the styles the statements set, and counts the statements that named a node or a link
    /// that is not there: a node takes the `default` class, then its classes in the order they were given, then its own
    /// `style`; an edge takes `linkStyle default`, then the `linkStyle` of its index.
    mutating func applyStyles() {
        guard let styling else { return }
        let defaultStyle = styling.classStyles["default"] ?? DiagramElementStyle()
        // Each node's style is built in its list's place, in the order the statements were written: the `default`
        // class, then each class given to it, then its own `style` statements.
        var styles = [DiagramElementStyle](repeating: defaultStyle, count: parts.nodes.count)
        for assignment in styling.classAssignments {
            let node = Int(lists.names.names[Int(assignment.name)].nodeIndex)
            guard node >= 0 else {
                unappliedStatementCount += 1
                continue
            }
            styles[node] = styles[node].overridden(by: styling.classStyles[assignment.className] ?? DiagramElementStyle())
        }
        var ownStyles = [DiagramElementStyle?](repeating: nil, count: parts.nodes.count)
        for statement in styling.nodeStyleStatements {
            let node = Int(lists.names.names[Int(statement.name)].nodeIndex)
            guard node >= 0 else {
                unappliedStatementCount += 1
                continue
            }
            ownStyles[node] = (ownStyles[node] ?? DiagramElementStyle()).overridden(by: statement.style)
        }
        parts.rare.nodeStyles = parts.nodes.indices.map { node in
            let style = ownStyles[node].map { own in styles[node].overridden(by: own) } ?? styles[node]
            return style.isEmpty ? nil : style
        }
        styleEdges(styling.linkStyleStatements)
    }

    private mutating func styleEdges(_ statements: [(indices: [Int]?, style: DiagramElementStyle)]) {
        var defaultEdgeStyle = DiagramElementStyle()
        var edgeStyles = [DiagramElementStyle?](repeating: nil, count: parts.edges.count)
        for statement in statements {
            guard let indices = statement.indices else {
                defaultEdgeStyle = defaultEdgeStyle.overridden(by: statement.style)
                continue
            }
            for index in indices {
                guard parts.edges.indices.contains(index) else {
                    unappliedStatementCount += 1
                    continue
                }
                edgeStyles[index] = (edgeStyles[index] ?? DiagramElementStyle()).overridden(by: statement.style)
            }
        }
        parts.rare.edgeStyles = parts.edges.indices.map { edge in
            let style = defaultEdgeStyle.overridden(by: edgeStyles[edge] ?? DiagramElementStyle())
            return style.isEmpty ? nil : style
        }
    }
}
