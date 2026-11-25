/**
 * File: RequirementDiagramStyling.swift
 * -------------------------------------
 * Layer: Core
 * Description: The style statements of a requirement diagram applied as Mermaid's database applies them: `style`
 *              copying declarations onto nodes, `class` and `:::` giving classes, `classDef` defining classes and
 *              copying their declarations onto the nodes that have them, every copy counted against Pele's million.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import Foundation

extension RequirementDiagramBuilder {
    /// A node by name: the requirement of that name, else the element.
    enum NodeReference {
        case requirement(Int), element(Int)

        var key: Int32 {
            switch self {
            case .requirement(let index): Int32(index)
            case .element(let index): ~Int32(index)
            }
        }

        init(key: Int32) {
            self = key >= 0 ? .requirement(Int(key)) : .element(Int(~key))
        }
    }

    mutating func node(named name: Range<Int>) -> NodeReference? {
        let named = namedByNumber[number(of: name)]
        if named.requirementIndex >= 0 { return .requirement(Int(named.requirementIndex)) }
        return named.elementIndex >= 0 ? .element(Int(named.elementIndex)) : nil
    }

    private mutating func copy(_ declarations: [String], onto node: NodeReference) throws(Refusal) {
        try count(declarations.count)
        switch node {
        case .requirement(let index): diagram.requirements[index].styleDeclarations += declarations
        case .element(let index): diagram.elements[index].styleDeclarations += declarations
        }
    }

    private mutating func count(_ copies: Int) throws(Refusal) {
        styleCopyCount += copies
        guard styleCopyCount <= Self.maximumStyleCopyCount else { throw .tooManyStyleCopies }
    }

    /// `style a,b declarations`: Mermaid stops at the first name that is no node, leaving the rest of the list unstyled.
    mutating func setStyle(names: [Range<Int>], declarations: [String]) throws(Refusal) {
        let split = Self.splitAtCommas(declarations)
        for name in names {
            guard let node = node(named: name) else { return }
            try copy(split, onto: node)
        }
    }

    /// `class a,b c1,c2` and `a:::c1,c2`: each class is given to each node named, with the declarations its class holds
    /// now; a name that is no node is passed over.
    mutating func setClasses(names: [Range<Int>], classNames: [Range<Int>]) throws(Refusal) {
        var classStrings: [String]?
        for name in names {
            guard let node = node(named: name) else { continue }
            let given = classStrings ?? classNames.map(string)
            classStrings = given
            for (className, classString) in zip(classNames, given) {
                try count(1)
                let classNumber = number(of: className)
                switch node {
                case .requirement(let index): diagram.requirements[index].classNames.append(classString)
                case .element(let index): diagram.elements[index].classNames.append(classString)
                }
                addMember(node, toClassNumbered: classNumber)
                let classIndex = namedByNumber[classNumber].styleClassIndex
                if classIndex >= 0 { try copy(diagram.styleClasses[Int(classIndex)].styleDeclarations, onto: node) }
            }
        }
    }

    /// Lists the node among those given the class, once; every node has `default`, which lists none.
    private mutating func addMember(_ node: NodeReference, toClassNumbered classNumber: Int) {
        guard classNumber != defaultClassNumber, givenClasses.insert(RequirementClassMember.key(node: node.key, classNumber: classNumber)).inserted else { return }
        classMembers.append(RequirementClassMember(node: node.key, next: namedByNumber[classNumber].firstMember))
        namedByNumber[classNumber].firstMember = Int32(classMembers.count - 1)
    }

    /// `classDef a,b declarations`: each class defined or extended, and its declarations copied onto every node that has
    /// it already; a declaration that sets a color is also kept for text, its first `fill` written `bgFill`.
    mutating func defineClasses(names: [Range<Int>], declarations: [String]) throws(Refusal) {
        let split = Self.splitAtCommas(declarations)
        for name in names {
            let classNumber = number(of: name)
            var classIndex = Int(namedByNumber[classNumber].styleClassIndex)
            if classIndex < 0 {
                classIndex = diagram.styleClasses.count
                namedByNumber[classNumber].styleClassIndex = Int32(classIndex)
                diagram.styleClasses.append(RequirementDiagramStyleClass(name: string(name), styleDeclarations: [], textStyleDeclarations: []))
            }
            for declaration in declarations {
                if Self.holdsColor(declaration) { diagram.styleClasses[classIndex].textStyleDeclarations.append(Self.withBackgroundFill(declaration)) }
                diagram.styleClasses[classIndex].styleDeclarations.append(declaration)
            }
            try copy(split, ontoNodesOfClassNumbered: classNumber)
        }
    }

    /// Copies the declarations onto every node given the class: onto every node for `default`. The order the nodes are
    /// taken in changes nothing: each node's declarations grow in the statements' order, and a refusal refuses the whole
    /// statement whichever copy passes the count.
    private mutating func copy(_ declarations: [String], ontoNodesOfClassNumbered classNumber: Int) throws(Refusal) {
        if classNumber == defaultClassNumber {
            for index in diagram.requirements.indices { try copy(declarations, onto: .requirement(index)) }
            for index in diagram.elements.indices { try copy(declarations, onto: .element(index)) }
            return
        }
        var member = Int(namedByNumber[classNumber].firstMember)
        while member >= 0 {
            try copy(declarations, onto: NodeReference(key: classMembers[member].node))
            member = Int(classMembers[member].next)
        }
    }

    /// The declarations each split at its commas, empty pieces kept; a declaration read from a text holds none.
    static func splitAtCommas(_ declarations: [String]) -> [String] {
        guard declarations.contains(where: { declaration in declaration.utf8.contains(MermaidByte.comma) }) else { return declarations }
        return declarations.flatMap { declaration in declaration.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }

    /// Whether `declaration` holds `color`, as Foundation's search by characters finds it: never without its bytes,
    /// always with them in a text of ASCII bytes, where the slow search is skipped.
    static func holdsColor(_ declaration: String) -> Bool {
        let utf8 = declaration.utf8
        let color = Array("color".utf8)
        var hasBytes = false
        var isASCII = true
        var index = utf8.startIndex
        var matched = 0
        while index != utf8.endIndex {
            let byte = utf8[index]
            if byte >= 0x80 { isASCII = false }
            matched = byte == color[matched] ? matched + 1 : (byte == color[0] ? 1 : 0)
            if matched == color.count {
                hasBytes = true
                matched = 0
            }
            index = utf8.index(after: index)
        }
        return hasBytes && (isASCII || declaration.contains("color"))
    }

    /// The declaration with its first `fill` written `bgFill`, as Foundation's search finds it: the first `fill` of its
    /// bytes in a declaration of ASCII bytes, as one read from a text always is.
    static func withBackgroundFill(_ declaration: String) -> String {
        let utf8 = Array(declaration.utf8)
        guard utf8.allSatisfy({ byte in byte < 0x80 }) else {
            return declaration.range(of: "fill").map { range in declaration.replacingCharacters(in: range, with: "bgFill") } ?? declaration
        }
        guard utf8.count >= 4, let start = (0...(utf8.count - 4)).first(where: { start in utf8[start..<start + 4].elementsEqual("fill".utf8) }) else {
            return declaration
        }
        return String(decoding: utf8[..<start] + Array("bgFill".utf8) + utf8[(start + 4)...], as: UTF8.self)
    }
}
