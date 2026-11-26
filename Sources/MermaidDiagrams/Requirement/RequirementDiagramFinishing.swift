/**
 * File: RequirementDiagramFinishing.swift
 * ---------------------------------------
 * Layer: Core
 * Description: A requirement diagram's builder finished into its flat model: the requirements and elements in one list,
 *              each relation's ends looked up among them, the declarations' bytes after the text, and each node's
 *              declarations and classes, then each class's declarations, gathered into runs of two shared lists in the
 *              order they were given, every list made at its size.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension RequirementDiagramBuilder {
    /// The diagram read, over `prepared`, the bytes the builder read (`bytes`), which the model keeps as its text, with the
    /// bytes of the declarations after them when there are any.
    func finished(text prepared: [UInt8]) -> RequirementDiagram {
        var model = RequirementModel()
        model.text = prepared
        if !lists.derived.isEmpty { model.text.append(contentsOf: lists.derived) }
        model.requirementCount = lists.requirements.count
        model.nodes = [RequirementNodeRecord](unsafeUninitializedCapacity: lists.requirements.count + lists.elements.count) { buffer, count in
            for record in lists.requirements {
                buffer.initializeElement(at: count, to: record)
                count += 1
            }
            for record in lists.elements {
                buffer.initializeElement(at: count, to: record)
                count += 1
            }
        }
        model.relations = [RequirementRelationRecord](unsafeUninitializedCapacity: lists.relations.count) { buffer, count in
            for var relation in lists.relations {
                relation.sourceBox = box(named: Int(relation.sourceBox))
                relation.targetBox = box(named: Int(relation.targetBox))
                buffer.initializeElement(at: count, to: relation)
                count += 1
            }
        }
        if !lists.styleClasses.isEmpty || !lists.declarations.isEmpty || !lists.classGifts.isEmpty { gatherStyles(into: &model, derivedOffset: prepared.count) }
        return RequirementDiagram(direction: direction, model: model, accessibilityTitle: accessibilityTitle, accessibilityDescription: accessibilityDescription)
    }

    /// The diagram as read so far, over a copy of the bytes read.
    var diagram: RequirementDiagram { finished(text: Array(bytes)) }

    /// The box the name numbered `number` names: its requirement, else its element after every requirement, else -1.
    private func box(named number: Int) -> Int32 {
        let named = lists.namedByNumber[number]
        if named.requirementIndex >= 0 { return named.requirementIndex }
        return named.elementIndex >= 0 ? Int32(lists.requirements.count) + named.elementIndex : -1
    }

    /// A node key's place among the boxes: a requirement's index, or an element's after every requirement.
    private func boxIndex(ofNode key: Int32) -> Int {
        key >= 0 ? Int(key) : lists.requirements.count + Int(~key)
    }

    /// The declarations' ranges (each moved after the text by `derivedOffset`), then the nodes' classes; the nodes'
    /// declarations, then the classes'. A declaration's number is its place in `ranges`.
    private func gatherStyles(into model: inout RequirementModel, derivedOffset: Int) {
        model.ranges.reserveCapacity(lists.declarations.count + lists.classGifts.count)
        for range in lists.declarations {
            model.ranges.append(MermaidTextRange(start: range.lowerBound + derivedOffset, end: range.upperBound + derivedOffset))
        }
        model.numbers.reserveCapacity(lists.declarationCopies.count + lists.classDeclarationLinks.count)
        gatherNodeDeclarations(into: &model)
        gatherNodeClasses(into: &model)
        model.styleClasses = RequirementReadingLists.exactCopy(lists.styleClasses)
        for index in model.styleClasses.indices {
            model.styleClasses[index].firstDeclaration = Int32(model.numbers.count)
            var link = lists.classDeclarationLists[index].first
            while link >= 0 {
                model.numbers.append(lists.classDeclarationLinks[Int(link)].node)
                link = lists.classDeclarationLinks[Int(link)].next
            }
            model.styleClasses[index].declarationCount = Int32(model.numbers.count) - model.styleClasses[index].firstDeclaration
        }
    }

    /// Each node's declarations, in the order they were copied, as one run of `numbers`: counted, then placed.
    private func gatherNodeDeclarations(into model: inout RequirementModel) {
        let starts = runStarts(of: lists.declarationCopies.lazy.map(\.node), boxCount: model.boxCount)
        var next = starts
        let first = model.numbers.count
        model.numbers.append(contentsOf: repeatElement(0, count: lists.declarationCopies.count))
        for copy in lists.declarationCopies {
            let box = boxIndex(ofNode: copy.node)
            model.numbers[first + next[box]] = copy.declaration
            next[box] += 1
        }
        for box in 0..<model.boxCount {
            model.nodes[box].firstStyleDeclaration = Int32(first + starts[box])
            model.nodes[box].styleDeclarationCount = Int32(next[box] - starts[box])
        }
    }

    /// Each node's classes after `default`, in the order they were given, as one run of `ranges`.
    private func gatherNodeClasses(into model: inout RequirementModel) {
        let starts = runStarts(of: lists.classGifts.lazy.map(\.node), boxCount: model.boxCount)
        var next = starts
        let first = model.ranges.count
        model.ranges.append(contentsOf: repeatElement(.empty, count: lists.classGifts.count))
        for gift in lists.classGifts {
            let box = boxIndex(ofNode: gift.node)
            model.ranges[first + next[box]] = gift.name
            next[box] += 1
        }
        for box in 0..<model.boxCount {
            model.nodes[box].firstClassName = Int32(first + starts[box])
            model.nodes[box].classNameCount = Int32(next[box] - starts[box])
        }
    }

    /// Where each box's run starts when the entries of `nodes` are placed box by box.
    private func runStarts(of nodes: some Sequence<Int32>, boxCount: Int) -> [Int] {
        var counts = [Int](repeating: 0, count: boxCount + 1)
        for node in nodes { counts[boxIndex(ofNode: node) + 1] += 1 }
        for box in 0..<boxCount { counts[box + 1] += counts[box] }
        counts.removeLast()
        return counts
    }
}
