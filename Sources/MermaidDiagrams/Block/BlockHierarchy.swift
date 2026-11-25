/**
 * File: BlockHierarchy.swift
 * --------------------------
 * Layer: Core
 * Description: Pele's setHierarchy over the block parser's statements, without recursion, into the flat model: blocks
 *              merged by their interned identifier, waiting blocks for class and style statements that come first,
 *              spaces split into cells, edges counted per pair of ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

/// Pele's `BlockDb.setHierarchy`, over the parser's statements, with a stack of the containers open instead of
/// recursion. A block whose identifier is known merges into the first one (its shape and its text, when it gives them)
/// and is not drawn again; a `class` or `style` statement for a block not yet declared makes a block that waits for it,
/// whose classes and styles the block takes when it comes; a composite's color index counts composites in the order they
/// are declared; a `space:N` becomes N space blocks. Identifiers are interned by their bytes, so a block is found by its
/// number, and the texts the reading makes (`id-3`, a declaration without its semicolon) go after the text's bytes.
struct BlockHierarchy {
    let statements: ScratchList<BlockStatement>
    let statementPlaces: ScratchList<Int32>
    var generatedIdentifierCount: Int
    var bytes: [UInt8]
    var blocks: [BlockRecord] = []
    var edges: [BlockEdgeRecord] = []
    var classes: [BlockClassRecord] = []
    var classIndicesByNameNumber: [Int32] = []
    var identifiers: BlockNameTable
    var classNames = BlockNameTable()
    /// Each interned identifier's block, -1 for none yet, and whether that block waits for its declaration.
    var blockIndicesByNumber: ScratchList<Int32>
    var isPendingByNumber: ScratchList<Bool>
    /// How many edges joined each pair of ends so far, by the pair's interned numbers.
    var edgeCountsByEnds: [UInt64: Int32] = [:]
    var compositeCount = 0
    var childIndices: [Int32] = []
    var texts: [BlockText]
    var classLinks: [BlockClassLink] = []
    /// The children of the containers open, the innermost's last; each moved to `childIndices` when its container ends.
    var openChildren: ScratchList<Int32>
    var stack: ScratchList<Frame>

    /// An open container: its statements, how many are read, the block it is, where its children start in
    /// `openChildren`.
    struct Frame: BitwiseCopyable {
        let statements: BlockSlice
        var next = 0
        let parentIndex: Int
        let childrenStart: Int
    }

    init(parser: BlockParser, bytes: [UInt8], arena: DiagramScratchArena) {
        statements = parser.statements
        statementPlaces = parser.statementPlaces
        generatedIdentifierCount = parser.generatedIdentifierCount
        texts = parser.texts
        self.bytes = bytes
        blocks.reserveCapacity(statements.count + 1)
        childIndices.reserveCapacity(statements.count)
        openChildren = arena.list(capacity: statements.count + 1)
        blockIndicesByNumber = arena.list(capacity: statements.count + 1)
        isPendingByNumber = arena.list(capacity: statements.count + 1)
        stack = arena.list(capacity: 8)
        identifiers = BlockNameTable(expectedCount: statements.count + 1)
        // The root's identifier, `root`, is no run of the text: it is read as `BlockModel.rootIdentifier`.
        blocks.append(BlockRecord(identifier: .empty, identifierNumber: -1, kind: .composite, shapeIndex: 0, label: .empty, widthInColumns: 1,
                                  directions: .empty))
    }

    func model() -> BlockModel {
        BlockModel(bytes: bytes, blocks: blocks, edges: edges, classes: classes, classIndicesByNameNumber: classIndicesByNameNumber,
                   classNames: classNames, childIndices: childIndices, texts: texts, classLinks: classLinks, identifiers: identifiers)
    }

    /// Sets the document's statements, `top`, into the root.
    mutating func set(_ top: BlockSlice) {
        stack.append(Frame(statements: top, parentIndex: BlockDiagram.rootIndex, childrenStart: 0))
        while !stack.isEmpty {
            let top = stack.count - 1
            guard stack[top].next < Int(stack[top].statements.count) else {
                let frame = stack.removeLast()
                blocks[frame.parentIndex].children = BlockSlice(first: childIndices.count, count: openChildren.count - frame.childrenStart)
                childIndices.append(contentsOf: openChildren.elements.part(frame.childrenStart..<openChildren.count))
                while openChildren.count > frame.childrenStart { _ = openChildren.removeLast() }
                continue
            }
            let statement = statements[Int(statementPlaces[Int(stack[top].statements.first) + stack[top].next])]
            stack[top].next += 1
            let parentIndex = stack[top].parentIndex
            switch statement.kind {
            case .classDefinition: addClass(statement.first, declarations: statement.second)
            case .classAssignment: assignClass(statement.second, to: statement.first)
            case .style:
                guard statement.second.count > 0 else { continue }
                let index = named(statement.first)
                blocks[index].styles = split(statement.second)
            case .columns:
                blocks[parentIndex].columns = statement.number
                blocks[parentIndex].hasColumns = statement.flag
            case .edge: addEdge(statement.edge)
            case .block: place(record(of: statement.draft), inner: nil)
            case .space: placeSpace(identifierNumber: statement.number, width: statement.draft.widthInColumns)
            case .composite:
                place(compositeRecord(header: statement.flag ? statement.draft : nil, identifierNumber: statement.number), inner: statement.children)
            }
        }
    }

    // MARK: Blocks

    /// A block as its statement writes it, its identifier its text when it has none.
    mutating func record(of draft: BlockDraft) -> BlockRecord {
        let label = draft.hasLabel && draft.label.count > 0 ? draft.label : draft.identifier
        return BlockRecord(identifier: draft.identifier, identifierNumber: Int32(intern(draft.identifier)), kind: draft.kind,
                           shapeIndex: draft.shapeIndex, label: label, widthInColumns: draft.widthInColumns, directions: draft.directions)
    }

    /// A composite as Pele spreads its header into it: the header's identifier, text and span, else the identifier given
    /// at its `end`, else (a header that was a link statement) one named now.
    mutating func compositeRecord(header: BlockDraft?, identifierNumber: Int) -> BlockRecord {
        guard let header else {
            let identifier = generatedIdentifier(identifierNumber >= 0 ? identifierNumber : nextIdentifierNumber())
            return BlockRecord(identifier: identifier, identifierNumber: Int32(intern(identifier)), kind: .composite, shapeIndex: 0, label: .empty,
                               widthInColumns: 1, directions: .empty)
        }
        return BlockRecord(identifier: header.identifier, identifierNumber: Int32(intern(header.identifier)), kind: .composite, shapeIndex: 0,
                           label: header.hasLabel ? header.label : .empty, widthInColumns: header.widthInColumns, directions: header.directions)
    }

    mutating func nextIdentifierNumber() -> Int {
        generatedIdentifierCount += 1
        return generatedIdentifierCount
    }

    /// A block read: merged into a known one of its identifier, or made a child of the open container; a composite's
    /// statements opened under it either way, as Pele's are.
    mutating func place(_ block: BlockRecord, inner: BlockSlice?) {
        let (index, isFresh) = register(block)
        if isFresh { openChildren.append(Int32(index)) }
        if let inner, inner.count > 0 { stack.append(Frame(statements: inner, parentIndex: index, childrenStart: openChildren.count)) }
    }

    /// `space:N`: the block `id-<number>` registered, then N blocks of one cell each, `id-<number>-0` to `-(N-1)`.
    mutating func placeSpace(identifierNumber: Int, width: Int) {
        let identifier = generatedIdentifier(identifierNumber)
        let space = BlockRecord(identifier: identifier, identifierNumber: Int32(intern(identifier)), kind: .space, shapeIndex: 0, label: identifier,
                                widthInColumns: 1, directions: .empty)
        _ = register(space)
        for cell in 0..<max(width, 0) {
            var copy = space
            copy.identifier = appendDerived(identifier: identifier, suffix: cell)
            copy.identifierNumber = Int32(intern(copy.identifier))
            setBlockIndex(blocks.count, of: Int(copy.identifierNumber))
            openChildren.append(Int32(blocks.count))
            blocks.append(copy)
        }
    }

    /// Pele's merge by identifier: the block's place in `blocks` (a new one, unreached when the identifier was known),
    /// and whether it is the first of its identifier.
    mutating func register(_ block: BlockRecord) -> (index: Int, isFresh: Bool) {
        var block = block
        let number = Int(block.identifierNumber)
        let known = blockIndex(of: number)
        let wasPending = known != nil && isPendingByNumber[number]
        if wasPending { isPendingByNumber[number] = false }
        let isFresh = known == nil || wasPending
        if let known, !isFresh {
            if block.kind != .unshaped {
                blocks[known].kind = block.kind
                blocks[known].shapeIndex = block.shapeIndex
            }
            if !sameText(block.label, block.identifier) { blocks[known].label = block.label }
        } else {
            if let known {
                (block.firstClassLink, block.lastClassLink) = copiedClassLinks(of: blocks[known])
                block.styles = blocks[known].styles
            }
            if block.kind == .composite {
                block.colorIndex = Int32(compositeCount)
                compositeCount += 1
            }
            setBlockIndex(blocks.count, of: number)
        }
        blocks.append(block)
        return (blocks.count - 1, isFresh)
    }

    /// The block of `identifier`, made to wait for its declaration when there is none yet.
    mutating func named(_ identifier: BlockText) -> Int {
        let number = intern(identifier)
        if let known = blockIndex(of: number) { return known }
        setBlockIndex(blocks.count, of: number)
        isPendingByNumber[number] = true
        blocks.append(BlockRecord(identifier: identifier, identifierNumber: Int32(number), kind: .unshaped, shapeIndex: 0, label: identifier,
                                  widthInColumns: 1, directions: .empty))
        return blocks.count - 1
    }

    func blockIndex(of number: Int) -> Int? {
        number < blockIndicesByNumber.count && blockIndicesByNumber[number] >= 0 ? Int(blockIndicesByNumber[number]) : nil
    }

    mutating func setBlockIndex(_ index: Int, of number: Int) {
        while blockIndicesByNumber.count <= number {
            blockIndicesByNumber.append(-1)
            isPendingByNumber.append(false)
        }
        blockIndicesByNumber[number] = Int32(index)
    }

    /// The identifier's number. Identifiers are keys as Swift's Strings are, equal when canonically equivalent: one
    /// beyond ASCII is interned by its composed form (NFC), after the text's bytes.
    mutating func intern(_ identifier: BlockText) -> Int {
        identifiers.intern(key(of: identifier), in: bytes)
    }
}
