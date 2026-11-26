/**
 * File: ClassDiagramNamespaceTree.swift
 * -------------------------------------
 * Layer: Core
 * Description: A class diagram's namespaces as the nested boxes Pele draws, and the box each class and note sits in.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 26/11/2026
 */

/// The namespaces of a class diagram as Pele's class database and graph make them (`class/db.ts` addNamespace,
/// `class/graph.ts` buildClassGraph): a dotted name is a namespace inside the one its prefix names
/// (`namespace Company.Engineering` is `Engineering` inside `Company`, made for it when not declared), one name declared
/// twice is one namespace, a namespace's title is the last part of its name unless the text gives one, a class sits
/// in the last namespace that declares it and a note in the namespace it is written in. With `hierarchicalNamespaces: false`, only the declared namespaces are boxes,
/// side by side, titled with their full names, and a class or a note sits in its nearest declared one.
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
    /// For each note of the diagram, the namespace it is drawn in, or nil.
    private(set) var noteNamespaces: [Int?]
    private var indexByIdentifier: [String: Int] = [:]

    init(diagram: ClassDiagram) {
        classNamespaces = Array(repeating: nil, count: diagram.classCount)
        noteNamespaces = Array(repeating: nil, count: diagram.noteCount)
        var declaredIndices: [Int] = []
        for declared in diagram.namespaces {
            // The namespace it is written in was declared before it, so only the parts of its own name are walked.
            let enclosing = declared.enclosingNamespaceIndex.flatMap { index in index < declaredIndices.count ? declaredIndices[index] : nil }
            declaredIndices.append(add(declared, enclosing: enclosing))
        }
        for (declared, index) in zip(diagram.namespaces, declaredIndices) {
            for classIndex in declared.classIndices where classIndex < classNamespaces.count { classNamespaces[classIndex] = index }
            for noteIndex in declared.noteIndices where noteIndex < noteNamespaces.count { noteNamespaces[noteIndex] = index }
        }
        if !diagram.hierarchicalNamespaces { keepDeclaredOnly() }
    }

    /// Adds a declared namespace and the namespaces its dotted name puts it in, below `enclosing` (the namespace it is
    /// written in) as Pele's `addNamespace` walks them; its index.
    private mutating func add(_ declared: ClassDiagramNamespace, enclosing: Int?) -> Int {
        let identifier = declared.identifier
        if let existing = indexByIdentifier[identifier] {
            namespaces[existing].isDeclared = true
            if let title = Self.writtenTitle(of: declared) { namespaces[existing].title = title }
            return existing
        }
        var parent: Int?
        var partStart = identifier.startIndex
        if let enclosing, identifier.hasPrefix(namespaces[enclosing].identifier + ".") {
            parent = enclosing
            partStart = identifier.utf8.index(identifier.startIndex, offsetBy: namespaces[enclosing].identifier.utf8.count + 1)
        }
        while true {
            let dot = identifier[partStart...].firstIndex(of: ".")
            let prefix = dot.map { dot in String(identifier[..<dot]) } ?? identifier
            let index: Int
            if let existing = indexByIdentifier[prefix] {
                index = existing
            } else {
                let part = DiagramLabel(String(identifier[partStart..<(dot ?? identifier.endIndex)]))
                index = namespaces.count
                indexByIdentifier[prefix] = index
                namespaces.append(Namespace(identifier: prefix, title: dot == nil ? Self.writtenTitle(of: declared) ?? part : part, parent: parent,
                                            isDeclared: dot == nil))
            }
            guard let dot else { return index }
            parent = index
            partStart = identifier.index(after: dot)
        }
    }

    /// The title the text gives a namespace (`namespace Auth["Authentication Service"]`), or nil when its title is its name.
    static func writtenTitle(of declared: ClassDiagramNamespace) -> DiagramLabel? {
        if declared.title.lineCount == 1 {
            // A title of one line of ASCII is compared on its bytes, which compare as its Characters do: no String of it
            // is made. Other text is compared as Strings, which are equal when they are canonically equivalent.
            var identifier = declared.identifier
            let isName = identifier.withUTF8 { identifierBytes in
                declared.title.withUTF8(ofLine: 0) { titleBytes in isName(titleBytes, of: identifierBytes) }
            }
            if let isName { return isName ? nil : declared.title }
        }
        let title = declared.title.lines.joined(separator: "\n")
        let isName = title == declared.identifier || declared.identifier.hasSuffix("." + title)
        return isName ? nil : declared.title
    }

    /// Whether a title's bytes are the identifier's, or its last part after a dot; nil when either is not all ASCII.
    private static func isName(_ title: UnsafeBufferPointer<UInt8>, of identifier: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard !title.contains(where: { byte in byte >= 0x80 }), !identifier.contains(where: { byte in byte >= 0x80 }) else { return nil }
        if title.elementsEqual(identifier) { return true }
        guard identifier.count > title.count, identifier[identifier.count - title.count - 1] == UInt8(ascii: ".") else { return false }
        return identifier[(identifier.count - title.count)...].elementsEqual(title)
    }

    /// Pele's `hierarchicalNamespaces: false`: each class and note in its nearest declared namespace, the others gone, every box
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
        noteNamespaces = noteNamespaces.map { namespace in nearestDeclared(namespace).flatMap { index in kept[index] } }
        namespaces = declared
    }
}
