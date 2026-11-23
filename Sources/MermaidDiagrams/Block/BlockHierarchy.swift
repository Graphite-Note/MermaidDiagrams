/**
 * File: BlockHierarchy.swift
 * --------------------------
 * Layer: Core
 * Description: Sets a block diagram's statements into their hierarchy as Pele's setHierarchy does: blocks merged by
 *              identifier, spaces made one block per cell, classes and styles waiting for their block, edges counted.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Pele's `BlockDb.setHierarchy`, over the parser's statements, with a stack of the containers open instead of
/// recursion. A block whose identifier is known merges into the first one (its shape and its text, when it gives them)
/// and is not drawn again; a `class` or `style` statement for a block not yet declared makes a block that waits for it,
/// whose classes and styles the block takes when it comes; a composite's color index counts composites in the order they
/// are declared; a `space:N` becomes N space blocks.
struct BlockHierarchy {
    private let statements: [BlockStatement]
    private var generatedIdentifierCount: Int
    private var blocks = [BlockDiagramBlock(identifier: "root", kind: .composite, label: "")]
    private var edges: [BlockDiagramEdge] = []
    private var classes: [String: BlockClassDefinition] = [:]
    private var indicesByIdentifier: [String: Int] = [:]
    private var pendingIdentifiers: Set<String> = []
    private var edgeCountsByIdentifier: [String: Int] = [:]
    private var compositeCount = 0

    /// An open container: its statements, how many are read, the block it is, and the children made so far.
    private struct Frame {
        let statementIndices: [Int]
        var next = 0
        let parentIndex: Int
        var childIndices: [Int] = []
    }

    init(statements: [BlockStatement], generatedIdentifierCount: Int) {
        self.statements = statements
        self.generatedIdentifierCount = generatedIdentifierCount
    }

    var diagram: BlockDiagram {
        BlockDiagram(blocks: blocks, edges: edges, classes: classes)
    }

    /// Sets the document's statements, `top`, into the root.
    mutating func set(_ top: [Int]) {
        var stack = [Frame(statementIndices: top, parentIndex: BlockDiagram.rootIndex)]
        // The frame is read in place, never copied out: a copy would share its children's list, which placing a block
        // then copies whole.
        while let top = stack.indices.last {
            guard stack[top].next < stack[top].statementIndices.count else {
                blocks[stack[top].parentIndex].childIndices = stack[top].childIndices
                stack.removeLast()
                continue
            }
            let statementIndex = stack[top].statementIndices[stack[top].next]
            stack[top].next += 1
            let parentIndex = stack[top].parentIndex
            switch statements[statementIndex] {
            case .classDefinition(let name, let declarations): addClass(name, declarations: declarations)
            case .classAssignment(let identifiers, let className):
                for identifier in identifiers.split(separator: ",", omittingEmptySubsequences: false) {
                    let index = named(identifier.trimmingCharacters(in: .whitespacesAndNewlines))
                    blocks[index].classNames = (blocks[index].classNames ?? []) + [className]
                }
            case .style(let identifiers, let declarations):
                guard !declarations.isEmpty else { continue }
                blocks[named(identifiers)].styles = declarations.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            case .columns(let columns): blocks[parentIndex].columns = columns
            case .edge(let draft): addEdge(draft)
            case .block(let draft): place(BlockDiagramBlock(draft), inner: [], in: &stack)
            case .space(let identifier, let width): placeSpace(identifier: identifier, width: width, in: &stack)
            case .composite(let header, let identifier, let childIndices):
                place(compositeBlock(header: header, identifier: identifier), inner: childIndices, in: &stack)
            }
        }
    }

    /// A composite as Pele spreads its header into it: the header's identifier, text and span, else the identifier given
    /// at its `end`, else (a header that was a link statement) one named now.
    private mutating func compositeBlock(header: BlockDraft?, identifier: String?) -> BlockDiagramBlock {
        guard let header else {
            let named = identifier ?? nextIdentifier()
            return BlockDiagramBlock(identifier: named, kind: .composite, label: "")
        }
        return BlockDiagramBlock(identifier: header.identifier, kind: .composite, label: header.label ?? "", widthInColumns: header.widthInColumns,
                                 directions: header.directions)
    }

    private mutating func nextIdentifier() -> String {
        generatedIdentifierCount += 1
        return "id-\(generatedIdentifierCount)"
    }

    /// A block read: merged into a known one of its identifier, or made a child of the open container; a composite's
    /// statements opened under it either way, as Pele's are.
    private mutating func place(_ block: BlockDiagramBlock, inner: [Int], in stack: inout [Frame]) {
        let (index, isFresh) = register(block)
        if isFresh { stack[stack.count - 1].childIndices.append(index) }
        if !inner.isEmpty { stack.append(Frame(statementIndices: inner, parentIndex: index)) }
    }

    /// `space:N`: the block registered, then N blocks of one cell each, `id-3-0` to `id-3-(N-1)`.
    private mutating func placeSpace(identifier: String, width: Int, in stack: inout [Frame]) {
        let space = BlockDiagramBlock(identifier: identifier, kind: .space, label: identifier)
        _ = register(space)
        for cell in 0..<max(width, 0) {
            var copy = space
            copy.identifier = identifier + "-\(cell)"
            indicesByIdentifier[copy.identifier] = blocks.count
            stack[stack.count - 1].childIndices.append(blocks.count)
            blocks.append(copy)
        }
    }

    /// Pele's merge by identifier: the block's place in `blocks` (a new one, unreached when the identifier was known),
    /// and whether it is the first of its identifier.
    private mutating func register(_ block: BlockDiagramBlock) -> (index: Int, isFresh: Bool) {
        var block = block
        let known = indicesByIdentifier[block.identifier]
        let isFresh = known == nil || pendingIdentifiers.remove(block.identifier) != nil
        if let known, !isFresh {
            if block.kind != .unshaped { blocks[known].kind = block.kind }
            if block.label != block.identifier { blocks[known].label = block.label }
        } else {
            if let known {
                block.classNames = blocks[known].classNames
                block.styles = blocks[known].styles
            }
            if block.kind == .composite {
                block.colorIndex = compositeCount
                compositeCount += 1
            }
            indicesByIdentifier[block.identifier] = blocks.count
        }
        blocks.append(block)
        return (blocks.count - 1, isFresh)
    }

    /// The block of `identifier`, made to wait for its declaration when there is none yet.
    private mutating func named(_ identifier: String) -> Int {
        if let known = indicesByIdentifier[identifier] { return known }
        indicesByIdentifier[identifier] = blocks.count
        pendingIdentifiers.insert(identifier)
        blocks.append(BlockDiagramBlock(identifier: identifier, kind: .unshaped, label: identifier))
        return blocks.count - 1
    }

    /// Pele's `addStyleClass`: each declaration between commas, its first semicolon dropped and trimmed.
    private mutating func addClass(_ name: String, declarations: String) {
        var definition = classes[name] ?? BlockClassDefinition(styles: [])
        for attribute in declarations.split(separator: ",", omittingEmptySubsequences: false) {
            var fixed = String(attribute)
            if let semicolon = fixed.firstIndex(of: ";") { fixed.remove(at: semicolon) }
            definition.styles.append(fixed.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        classes[name] = definition
    }

    private mutating func addEdge(_ draft: BlockEdgeDraft) {
        let count = (edgeCountsByIdentifier[draft.identifier] ?? 0) + 1
        edgeCountsByIdentifier[draft.identifier] = count
        edges.append(BlockDiagramEdge(identifier: "\(count)-" + draft.identifier, sourceIdentifier: draft.sourceIdentifier,
                                      targetIdentifier: draft.targetIdentifier, label: draft.label,
                                      sourceArrowhead: BlockSyntaxValues.sourceArrowhead(link: draft.link),
                                      targetArrowhead: BlockSyntaxValues.targetArrowhead(link: draft.link),
                                      isThick: BlockSyntaxValues.isThick(link: draft.link), isDotted: BlockSyntaxValues.isDotted(link: draft.link)))
    }
}

extension BlockDiagramBlock {
    /// A block as its statement writes it, its identifier its text when it has none.
    init(_ draft: BlockDraft) {
        self.init(identifier: draft.identifier, kind: draft.kind, label: draft.label.flatMap { label in label.isEmpty ? nil : label } ?? draft.identifier,
                  widthInColumns: draft.widthInColumns, directions: draft.directions)
    }
}
