/**
 * File: FlatFlowchartStyles.swift
 * -------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: `classDef`, `class`, `:::`, `style` and `linkStyle` recorded as FlowchartDiagramBuilder records them,
 *              names by their interned index, and applied when the text ends; nothing is made for a diagram that no
 *              statement styles.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

struct FlatStyling {
    var classStyles: [String: DiagramElementStyle] = [:]
    /// `class` and `:::` in the order written, by the name of the node they give the class.
    var classAssignments: [(name: Int32, className: String)] = []
    var nodeStyleStatements: [(name: Int32, style: DiagramElementStyle)] = []
    var linkStyleStatements: [(indices: [Int]?, style: DiagramElementStyle)] = []
}

extension FlatFlowchartReader {
    enum StyleKeyword {
        case classDefinition, classAssignment, style, linkStyle

        var text: String {
            switch self {
            case .classDefinition: "classDef"
            case .classAssignment: "class"
            case .style: "style"
            case .linkStyle: "linkStyle"
            }
        }
    }

    /// The statement after its keyword, checked as Pele's grammar reads it, then recorded.
    mutating func readStyleStatement(_ keyword: StyleKeyword) throws(FlatReadingBailOut) {
        let statementStart = position
        skipStatement()
        guard bytes.isStyleReadByPele(keywordIsClass: keyword == .classAssignment, keywordIsLinkStyle: keyword == .linkStyle, from: statementStart,
                                      to: position) else { throw FlatReadingBailOut() }
        var start = statementStart
        var end = position
        while start < end, MermaidByte.isWhitespace(bytes.base[start]) { start += 1 }
        while end > start, MermaidByte.isWhitespace(bytes.base[end - 1]) { end -= 1 }
        let statement = FlowchartStyleSyntax.statement(keyword: keyword.text, text: string(from: start, to: end))
        try apply(statement, statementStart: start)
    }

    private mutating func apply(_ statement: FlowchartStyleStatement?, statementStart: Int) throws(FlatReadingBailOut) {
        if styling == nil { styling = FlatStyling() }
        guard let statement else {
            document.unappliedStatementCount += 1
            return
        }
        switch statement {
        case .classDefinition(let names, let declarations):
            let (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            for name in names { styling!.classStyles[name] = (styling!.classStyles[name] ?? DiagramElementStyle()).overridden(by: style) }
            if hasUnappliedDeclaration { document.unappliedStatementCount += 1 }
        case .classAssignment(let identifiers, let className):
            for identifier in identifiers { styling!.classAssignments.append((Int32(intern(identifier)), className)) }
        case .nodeStyle(let identifier, let declarations):
            try addNodeNamedByStyle(identifier, statementStart: statementStart)
            let (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            styling!.nodeStyleStatements.append((Int32(intern(identifier)), style))
            if hasUnappliedDeclaration { document.unappliedStatementCount += 1 }
        case .linkStyle(let indices, let declarations):
            var (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            style.fill = nil
            if style.textColor != nil {
                style.textColor = nil
                hasUnappliedDeclaration = true
            }
            styling!.linkStyleStatements.append((indices, style))
            if hasUnappliedDeclaration { document.unappliedStatementCount += 1 }
        }
    }

    /// `:::name` after a node.
    mutating func assignClass(nodeName: Int, classRange: Range<Int>) {
        if styling == nil { styling = FlatStyling() }
        styling!.classAssignments.append((Int32(nodeName), string(from: classRange.lowerBound, to: classRange.upperBound)))
    }

    /// FlowchartDiagramBuilder.addNodeNamedByStyle: the node is the identifier's bytes where the statement writes them.
    private mutating func addNodeNamedByStyle(_ identifier: String, statementStart: Int) throws(FlatReadingBailOut) {
        let name = intern(identifier)
        guard names[name].nodeIndex < 0, names[name].endedSubgraphIndex < 0,
              !openSubgraphs.contains(where: { group in group.writtenName == Int32(name) }), document.nodes.count < limits.maximumNodeCount else { return }
        let length = identifier.utf8.count
        guard statementStart + length <= bytes.count,
              UnsafeBufferPointer(rebasing: bytes.buffer[statementStart..<statementStart + length]).elementsEqual(identifier.utf8) else {
            throw FlatReadingBailOut()
        }
        let range = FlatTextRange(start: Int32(statementStart), end: Int32(statementStart + length))
        names[name].nodeIndex = Int32(document.nodes.count)
        document.nodes.append(FlatFlowchartNode(identifier: range, label: writtenLabel(range, form: .plain), shape: .rectangle))
    }

    /// FlowchartDiagramBuilder.styleNodes and styleEdges, when any statement styles the diagram.
    mutating func applyStyles() {
        guard let styling else { return }
        var unappliedCount = 0
        var classNamesByNode: [Int: [String]] = [:]
        for assignment in styling.classAssignments {
            let node = Int(names[Int(assignment.name)].nodeIndex)
            guard node >= 0 else {
                unappliedCount += 1
                continue
            }
            classNamesByNode[node, default: []].append(assignment.className)
        }
        var ownStylesByNode: [Int: DiagramElementStyle] = [:]
        for statement in styling.nodeStyleStatements {
            let node = Int(names[Int(statement.name)].nodeIndex)
            guard node >= 0 else {
                unappliedCount += 1
                continue
            }
            ownStylesByNode[node] = (ownStylesByNode[node] ?? DiagramElementStyle()).overridden(by: statement.style)
        }
        let defaultStyle = styling.classStyles["default"] ?? DiagramElementStyle()
        var nodeStyles: [DiagramElementStyle?] = []
        nodeStyles.reserveCapacity(document.nodes.count)
        for node in document.nodes.indices {
            var style = defaultStyle
            for className in classNamesByNode[node] ?? [] { style = style.overridden(by: styling.classStyles[className] ?? DiagramElementStyle()) }
            style = style.overridden(by: ownStylesByNode[node] ?? DiagramElementStyle())
            nodeStyles.append(style.isEmpty ? nil : style)
        }
        var defaultEdgeStyle = DiagramElementStyle()
        var edgeStyleByIndex: [Int: DiagramElementStyle] = [:]
        for statement in styling.linkStyleStatements {
            guard let indices = statement.indices else {
                defaultEdgeStyle = defaultEdgeStyle.overridden(by: statement.style)
                continue
            }
            for index in indices {
                guard document.edges.indices.contains(index) else {
                    unappliedCount += 1
                    continue
                }
                edgeStyleByIndex[index] = (edgeStyleByIndex[index] ?? DiagramElementStyle()).overridden(by: statement.style)
            }
        }
        var edgeStyles: [DiagramElementStyle?] = []
        edgeStyles.reserveCapacity(document.edges.count)
        for edge in document.edges.indices {
            let style = defaultEdgeStyle.overridden(by: edgeStyleByIndex[edge] ?? DiagramElementStyle())
            edgeStyles.append(style.isEmpty ? nil : style)
        }
        document.rare.nodeStyles = nodeStyles
        document.rare.edgeStyles = edgeStyles
        document.unappliedStatementCount += unappliedCount
    }
}
