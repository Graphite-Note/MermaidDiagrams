/**
 * File: ClassDiagramNamespaceTree.swift
 * -------------------------------------
 * Layer: Core
 * Description: A class diagram's namespaces as the nested boxes Pele draws, and the box each class sits in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The namespaces of a class diagram as Pele's class database and graph make them (`class/db.ts` addNamespace,
/// `class/graph.ts` buildClassGraph): a dotted name is a namespace inside the one its prefix names
/// (`namespace Company.Engineering` is `Engineering` inside `Company`, made for it when not declared), one name declared
/// twice is one namespace, a namespace's title is the last part of its name unless the text gives one, and a class sits
/// in the last namespace that declares it. With `hierarchicalNamespaces: false`, only the declared namespaces are boxes,
/// side by side, titled with their full names, and a class sits in its nearest declared one.
struct ClassDiagramNamespaceTree {
    struct Namespace: Equatable {
        let identifier: String
        var title: DiagramLabel
        /// The namespace this one is drawn in, or nil.
        var parent: Int?
        /// Whether the text declares it, rather than only a namespace inside it.
        var isDeclared: Bool
    }

    private(set) var namespaces: [Namespace] = []
    /// For each class of the diagram, the namespace it is drawn in, or nil.
    private(set) var classNamespaces: [Int?]
    private var indexByIdentifier: [String: Int] = [:]

    init(diagram: ClassDiagram) {
        classNamespaces = Array(repeating: nil, count: diagram.classes.count)
        var declaredIndices: [Int] = []
        for declared in diagram.namespaces { declaredIndices.append(add(declared)) }
        for (declared, index) in zip(diagram.namespaces, declaredIndices) {
            for classIndex in declared.classIndices where classIndex < classNamespaces.count { classNamespaces[classIndex] = index }
        }
        if !diagram.hierarchicalNamespaces { keepDeclaredOnly() }
    }

    /// Adds a declared namespace and the namespaces its dotted name puts it in; its index.
    private mutating func add(_ declared: ClassDiagramNamespace) -> Int {
        let parts = declared.identifier.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var parent: Int?
        var prefix = ""
        for (position, part) in parts.enumerated() {
            prefix = position == 0 ? part : prefix + "." + part
            let isLeaf = position == parts.count - 1
            if let existing = indexByIdentifier[prefix] {
                if isLeaf {
                    namespaces[existing].isDeclared = true
                    if let title = Self.writtenTitle(of: declared) { namespaces[existing].title = title }
                }
                parent = existing
                continue
            }
            indexByIdentifier[prefix] = namespaces.count
            let title = isLeaf ? Self.writtenTitle(of: declared) ?? DiagramLabel(part) : DiagramLabel(part)
            namespaces.append(Namespace(identifier: prefix, title: title, parent: parent, isDeclared: isLeaf))
            parent = namespaces.count - 1
        }
        return parent ?? 0
    }

    /// The title the text gives a namespace (`namespace Auth["Authentication Service"]`), or nil when its title is its name.
    private static func writtenTitle(of declared: ClassDiagramNamespace) -> DiagramLabel? {
        let title = declared.title.lines.joined(separator: "\n")
        let isName = title == declared.identifier || declared.identifier.hasSuffix("." + title)
        return isName ? nil : declared.title
    }

    /// Pele's `hierarchicalNamespaces: false`: each class in its nearest declared namespace, the others gone, every box
    /// at the top level titled with its full name.
    private mutating func keepDeclaredOnly() {
        func nearestDeclared(_ index: Int?) -> Int? {
            var current = index
            var steps = 0
            while let namespace = current, !namespaces[namespace].isDeclared, steps <= namespaces.count {
                current = namespaces[namespace].parent
                steps += 1
            }
            return current
        }
        var kept: [Int: Int] = [:]
        var declared: [Namespace] = []
        for (index, namespace) in namespaces.enumerated() where namespace.isDeclared {
            kept[index] = declared.count
            declared.append(Namespace(identifier: namespace.identifier, title: DiagramLabel(namespace.identifier), parent: nil, isDeclared: true))
        }
        classNamespaces = classNamespaces.map { namespace in nearestDeclared(namespace).flatMap { index in kept[index] } }
        namespaces = declared
    }
}
