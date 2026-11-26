/**
 * File: RequirementDiagramStyling.swift
 * -------------------------------------
 * Layer: Core
 * Description: The style statements of a requirement diagram applied as Mermaid's database applies them: `style`
 *              copying declarations onto nodes, `class` and `:::` giving classes, `classDef` defining classes and
 *              copying their declarations onto the nodes that have them, every copy counted against Pele's million,
 *              each declaration a number of the bytes its parts joined.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
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
        let named = lists.namedByNumber[number(of: name)]
        if named.requirementIndex >= 0 { return .requirement(Int(named.requirementIndex)) }
        return named.elementIndex >= 0 ? .element(Int(named.elementIndex)) : nil
    }

    /// A declaration whose bytes are the parts' bytes run together, `parts` ranges of the text; its number.
    mutating func addDeclaration(joining parts: some Sequence<Range<Int>>) -> Int32 {
        let start = lists.derived.count
        for part in parts { lists.derived.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[part])) }
        lists.declarations.append(MermaidTextRange(start: start, end: lists.derived.count))
        return Int32(lists.declarations.count - 1)
    }

    /// The declarations `texts`, given as Strings rather than read, each a number of its bytes.
    mutating func addDeclarations(_ texts: [String]) -> Range<Int32> {
        let first = Int32(lists.declarations.count)
        for text in texts {
            let start = lists.derived.count
            lists.derived.append(contentsOf: text.utf8)
            lists.declarations.append(MermaidTextRange(start: start, end: lists.derived.count))
        }
        return first..<Int32(lists.declarations.count)
    }

    private mutating func copy(_ declarations: some Collection<Int32>, onto node: NodeReference) throws(Refusal) {
        try count(declarations.count)
        for declaration in declarations { lists.declarationCopies.append(RequirementNodeEntry(node: node.key, declaration: declaration)) }
    }

    private mutating func count(_ copies: Int) throws(Refusal) {
        styleCopyCount += copies
        guard styleCopyCount <= Self.maximumStyleCopyCount else { throw .tooManyStyleCopies }
    }

    /// `style a,b declarations`: Mermaid stops at the first name that is no node, leaving the rest of the list unstyled.
    mutating func setStyle(names: [Range<Int>], declarations: Range<Int32>) throws(Refusal) {
        for name in names {
            guard let node = node(named: name) else { return }
            try copy(declarations, onto: node)
        }
    }

    /// `style` with declarations given as Strings, each split at its commas as Mermaid splits them.
    mutating func setStyle(names: [Range<Int>], declarations texts: [String]) throws(Refusal) {
        try setStyle(names: names, declarations: addDeclarations(Self.splitAtCommas(texts)))
    }

    /// `class a,b c1,c2` and `a:::c1,c2`: each class is given to each node named, with the declarations its class holds
    /// now; a name that is no node is passed over.
    mutating func setClasses(names: [Range<Int>], classNames: [Range<Int>]) throws(Refusal) {
        for name in names {
            guard let node = node(named: name) else { continue }
            for className in classNames {
                try count(1)
                let classNumber = number(of: className)
                lists.classGifts.append(RequirementNodeClass(node: node.key, name: Self.textRange(className)))
                addMember(node, toClassNumbered: classNumber)
                let classIndex = lists.namedByNumber[classNumber].styleClassIndex
                if classIndex >= 0 { try copy(classDeclarationNumbers(of: Int(classIndex)), onto: node) }
            }
        }
    }

    /// The declarations class `index` holds now, in the order it was given them.
    private func classDeclarationNumbers(of index: Int) -> [Int32] {
        var numbers: [Int32] = []
        var link = lists.classDeclarationLists[index].first
        while link >= 0 {
            numbers.append(lists.classDeclarationLinks[Int(link)].node)
            link = lists.classDeclarationLinks[Int(link)].next
        }
        return numbers
    }

    /// Lists the node among those given the class, once; every node has `default`, which lists none.
    private mutating func addMember(_ node: NodeReference, toClassNumbered classNumber: Int) {
        guard classNumber != defaultClassNumber, lists.givenClasses.insert(RequirementClassMember.key(node: node.key, classNumber: classNumber)).inserted else { return }
        lists.classMembers.append(RequirementClassMember(node: node.key, next: lists.namedByNumber[classNumber].firstMember))
        lists.namedByNumber[classNumber].firstMember = Int32(lists.classMembers.count - 1)
    }

    /// `classDef a,b declarations`: each class defined or extended with `declarations`, and `copies` copied onto every
    /// node that has it already. A declaration read from a text holds no comma, so the two are the same; declarations
    /// given as Strings are copied split at their commas.
    mutating func defineClasses(names: [Range<Int>], declarations: Range<Int32>, copies: Range<Int32>) throws(Refusal) {
        for name in names {
            let classNumber = number(of: name)
            var classIndex = Int(lists.namedByNumber[classNumber].styleClassIndex)
            if classIndex < 0 {
                classIndex = lists.styleClasses.count
                lists.namedByNumber[classNumber].styleClassIndex = Int32(classIndex)
                lists.styleClasses.append(RequirementStyleClassRecord(name: Self.textRange(name)))
                lists.classDeclarationLists.append(RequirementClassDeclarations())
            }
            for declaration in declarations { appendDeclaration(declaration, toClassAt: classIndex) }
            try copy(copies, ontoNodesOfClassNumbered: classNumber)
        }
    }

    /// `classDef` with declarations given as Strings: kept whole by the class, copied split at their commas.
    mutating func defineClasses(names: [Range<Int>], declarations texts: [String]) throws(Refusal) {
        let whole = addDeclarations(texts)
        let split = texts.contains { text in text.utf8.contains(MermaidByte.comma) } ? addDeclarations(Self.splitAtCommas(texts)) : whole
        try defineClasses(names: names, declarations: whole, copies: split)
    }

    private mutating func appendDeclaration(_ declaration: Int32, toClassAt index: Int) {
        lists.classDeclarationLinks.append(RequirementClassMember(node: declaration, next: -1))
        let link = Int32(lists.classDeclarationLinks.count - 1)
        if lists.classDeclarationLists[index].last >= 0 { lists.classDeclarationLinks[Int(lists.classDeclarationLists[index].last)].next = link } else {
            lists.classDeclarationLists[index].first = link
        }
        lists.classDeclarationLists[index].last = link
    }

    /// Copies the declarations onto every node given the class: onto every node for `default`. The order the nodes are
    /// taken in changes nothing: each node's declarations grow in the statements' order, and a refusal refuses the whole
    /// statement whichever copy passes the count.
    private mutating func copy(_ declarations: Range<Int32>, ontoNodesOfClassNumbered classNumber: Int) throws(Refusal) {
        if classNumber == defaultClassNumber {
            for index in lists.requirements.indices { try copy(declarations, onto: .requirement(index)) }
            for index in lists.elements.indices { try copy(declarations, onto: .element(index)) }
            return
        }
        var member = Int(lists.namedByNumber[classNumber].firstMember)
        while member >= 0 {
            try copy(declarations, onto: NodeReference(key: lists.classMembers[member].node))
            member = Int(lists.classMembers[member].next)
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
