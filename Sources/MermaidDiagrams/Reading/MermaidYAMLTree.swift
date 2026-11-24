/**
 * File: MermaidYAMLTree.swift
 * ---------------------------
 * Layer: Core
 * Description: A front matter's YAML read once into a flat list of small records, its keys and texts byte ranges of
 *              the YAML's own bytes, looked up by their bytes: what a diagram's title and its type's options are read
 *              from without dictionaries of Strings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// One value of a YAML tree: a scalar, or a mapping or a list whose entries are its children, in the order written.
struct MermaidYAMLNode {
    enum Kind: UInt8 {
        case null
        case falseBoolean
        case trueBoolean
        case number
        case text
        case mapping
        case list
    }

    var kind: Kind
    /// The entry's key, in the tree's bytes; empty for the document itself and for a list's items.
    var key: MermaidTextRange
    /// A text's bytes, in the tree's bytes.
    var text = MermaidTextRange(start: 0, end: 0)
    var number: Double = 0
    /// The first entry of a mapping or a list, or -1.
    var firstChild: Int32 = -1
    /// The entry after this one in its mapping or list, or -1.
    var nextSibling: Int32 = -1
}

/// A YAML document as Pele's reader reads it (`SequenceAttributesBlockSyntax`, the reference), held as a flat list of
/// nodes, the document's at `root`. The common front matter, block mappings of plain and quoted scalars, is read on its
/// bytes by `MermaidYAMLTreeReader`, its keys and texts ranges of those bytes; any other YAML is read by the reference
/// reader, and its keys' and texts' bytes are written into the tree's own.
struct MermaidYAMLTree {
    /// The document's node.
    static let root = 0

    /// The YAML's bytes, which a tree read on them indexes; or the keys and texts the reference reader decoded.
    let bytes: [UInt8]
    let nodes: [MermaidYAMLNode]

    /// The document `yaml` holds, or nil when Pele's reader refuses it (Pele then refuses the diagram).
    static func read(_ yaml: [UInt8]) -> MermaidYAMLTree? {
        if let tree = MermaidYAMLTreeReader.tree(of: yaml) { return tree }
        return MermaidYAMLDocument.value(of: yaml).map { value in MermaidYAMLTree(value, sizedFor: yaml.count) }
    }

    init(bytes: [UInt8], nodes: [MermaidYAMLNode]) {
        self.bytes = bytes
        self.nodes = nodes
    }

    /// The tree of a value the reference reader read from a YAML text of `yamlByteCount` bytes: its keys' and texts'
    /// bytes written one after the other, in about as many bytes as the YAML's.
    init(_ value: DirectiveValue, sizedFor yamlByteCount: Int) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(yamlByteCount)
        var nodes: [MermaidYAMLNode] = []
        nodes.reserveCapacity(16)
        Self.append(value, key: MermaidTextRange(start: bytes.count, end: bytes.count), to: &nodes, bytes: &bytes)
        self.bytes = bytes
        self.nodes = nodes
    }

    private static func append(_ value: DirectiveValue, key: MermaidTextRange, to nodes: inout [MermaidYAMLNode], bytes: inout [UInt8]) {
        let index = nodes.count
        nodes.append(MermaidYAMLNode(kind: .null, key: key))
        func written(_ text: String) -> MermaidTextRange {
            let start = bytes.count
            bytes.append(contentsOf: text.utf8)
            return MermaidTextRange(start: start, end: bytes.count)
        }
        var children: [(key: MermaidTextRange, value: DirectiveValue)] = []
        switch value {
        case .null: return
        case .boolean(let boolean): nodes[index].kind = boolean ? .trueBoolean : .falseBoolean
        case .number(let number):
            nodes[index].kind = .number
            nodes[index].number = number
        case .text(let text):
            nodes[index].kind = .text
            nodes[index].text = written(text)
        case .array(let items):
            nodes[index].kind = .list
            children = items.map { item in (MermaidTextRange(start: bytes.count, end: bytes.count), item) }
        case .object(let entries):
            nodes[index].kind = .mapping
            children = entries.map { key, entry in (written(key), entry) }
        }
        var previous = -1
        for child in children {
            let childIndex = nodes.count
            append(child.value, key: child.key, to: &nodes, bytes: &bytes)
            if previous < 0 { nodes[index].firstChild = Int32(childIndex) } else { nodes[previous].nextSibling = Int32(childIndex) }
            previous = childIndex
        }
    }

    func kind(of node: Int) -> MermaidYAMLNode.Kind {
        nodes[node].kind
    }

    /// The entries of a mapping or the items of a list, in order.
    func children(of node: Int) -> MermaidYAMLChildren {
        MermaidYAMLChildren(nodes: nodes, first: Int(nodes[node].firstChild))
    }

    /// The entry of the mapping `node` whose key is `name`'s bytes, or nil (and nil when `node` is no mapping).
    func entry(of node: Int, named name: String) -> Int? {
        guard nodes[node].kind == .mapping else { return nil }
        let nameLength = name.utf8.count
        for child in children(of: node) {
            let key = nodes[child].key
            if key.count == nameLength, bytes[key.lowerBound..<key.upperBound].elementsEqual(name.utf8) { return child }
        }
        return nil
    }

    /// The key of an entry as text.
    func key(of node: Int) -> String {
        string(nodes[node].key)
    }

    /// A text node's text.
    func text(of node: Int) -> String {
        string(nodes[node].text)
    }

    private func string(_ range: MermaidTextRange) -> String {
        bytes.withUnsafeBufferPointer { bytes in String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound]), as: UTF8.self) }
    }

    /// The node and what it holds as a configuration's values, as the reference reader builds them.
    func value(of node: Int) -> DirectiveValue {
        switch nodes[node].kind {
        case .null: .null
        case .falseBoolean: .boolean(false)
        case .trueBoolean: .boolean(true)
        case .number: .number(nodes[node].number)
        case .text: .text(text(of: node))
        case .list: .array(children(of: node).map(value))
        case .mapping: .object(Dictionary(children(of: node).map { child in (key(of: child), value(of: child)) }) { _, later in later })
        }
    }

    /// The node as an option's value; nil for null.
    func optionValue(of node: Int) -> MermaidConfigurationOptions.Value? {
        switch nodes[node].kind {
        case .null: nil
        case .falseBoolean: .boolean(false)
        case .trueBoolean: .boolean(true)
        case .number: .number(nodes[node].number)
        case .text: .text(text(of: node))
        case .mapping, .list: .collection
        }
    }

    /// Whether JavaScript counts the value as true, as Pele tests the front matter's `title` and `displayMode`.
    func isTruthy(_ node: Int) -> Bool {
        switch nodes[node].kind {
        case .null, .falseBoolean: false
        case .trueBoolean, .mapping, .list: true
        case .number: nodes[node].number != 0 && !nodes[node].number.isNaN
        case .text: !nodes[node].text.isEmpty
        }
    }

    /// JavaScript's `String(value)`, as Pele writes the front matter's `title` and `displayMode`.
    func javaScriptText(_ node: Int) -> String {
        nodes[node].kind == .text ? text(of: node) : MermaidYAMLDocument.javaScriptText(value(of: node))
    }
}

/// The children of a node, followed from the first by their next siblings.
struct MermaidYAMLChildren: Sequence, IteratorProtocol {
    let nodes: [MermaidYAMLNode]
    /// The child `next()` gives, or -1 after the last.
    var upcoming: Int

    init(nodes: [MermaidYAMLNode], first: Int) {
        self.nodes = nodes
        upcoming = first
    }

    mutating func next() -> Int? {
        guard upcoming >= 0 else { return nil }
        let current = upcoming
        upcoming = Int(nodes[current].nextSibling)
        return current
    }
}
