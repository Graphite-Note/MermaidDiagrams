/**
 * File: EventModelDiagramBuilder.swift
 * ------------------------------------
 * Layer: Core
 * Description: Builds an event model from its statements as Mermaid's database does: one lane per group of kinds and
 *              namespace, each frame's data, and the relations its sources name or the frame before it implies.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Builds an `EventModelDiagram` from what `EventModelParser` read, as Pele's `buildEventModel` does after Mermaid's
/// database: a frame number used twice refuses the diagram; a frame that names its sources is fed by those of them
/// written before it, in their order; any other frame but the first and reset frames is fed by the nearest earlier
/// frame in another lane.
enum EventModelDiagramBuilder {
    static func diagram(of statements: EventModelStatements, bytes: [UInt8], limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> EventModelDiagram {
        var frameIndexByIdentifier: [String: Int] = [:]
        for (index, frame) in statements.frames.enumerated() {
            guard frameIndexByIdentifier[frame.identifier] == nil else {
                let line = FirstMatchTokenReader<EventModelTokenKind>.line(of: frame.position, in: bytes)
                throw .invalidSyntax(line: line, problem: .eventModeling(.duplicateFrame(identifier: frame.identifier)))
            }
            frameIndexByIdentifier[frame.identifier] = index
        }
        var dataByName: [String: String] = [:]
        for dataBlock in statements.dataBlocks where dataByName[dataBlock.name] == nil { dataByName[dataBlock.name] = dataBlock.block }
        var lanes = EventModelLaneAssignment()
        var frames: [EventModelFrame] = []
        var relations: [EventModelRelation] = []
        for (index, written) in statements.frames.enumerated() {
            let frame = frame(written, laneIndex: { kind, namespace in lanes.laneIndex(of: kind, namespace: namespace) }, dataByName: dataByName)
            frames.append(frame)
            for source in sources(of: written, at: index, frames: frames, frameIndexByIdentifier: frameIndexByIdentifier) {
                guard relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
                relations.append(EventModelRelation(sourceFrameIndex: source, targetFrameIndex: index))
            }
        }
        let sorted = lanes.sortedLanes()
        return EventModelDiagram(
            title: statements.title.map(FirstMatchStatementValues.title).flatMap { title in title.isEmpty ? nil : title },
            accessibilityTitle: statements.accessibilityTitle.map(FirstMatchStatementValues.accessibilityTitle),
            accessibilityDescription: statements.accessibilityDescription.map(FirstMatchStatementValues.accessibilityDescription),
            frames: frames.map { frame in frame.withLane(sorted.newIndexByAssignedIndex[frame.laneIndex]) }, lanes: sorted.lanes,
            relations: relations, notes: statements.notes, specifications: statements.specifications, entities: statements.entities)
    }

    private static func frame(_ written: EventModelWrittenFrame, laneIndex: (EventModelEntityKind, String?) -> Int,
                              dataByName: [String: String]) -> EventModelFrame {
        // Only a name of two parts has a namespace.
        let parts = written.entity.split(separator: ".", omittingEmptySubsequences: false)
        let namespace = parts.count == 2 ? String(parts[0]) : nil
        let kind = EventModelEntityKind(keyword: written.kindKeyword)
        var data = written.inlineData.map(blockText)
        if let reference = written.dataReference, let block = dataByName[reference] { data = blockText(block) }
        return EventModelFrame(identifier: written.identifier, kind: kind, entity: written.entity, name: parts.count == 2 ? String(parts[1]) : written.entity,
                               namespace: namespace, isReset: written.isReset, laneIndex: laneIndex(kind, namespace), data: data,
                               dataType: written.dataType)
    }

    /// The frames that feed the frame at `index`, in frame order: the sources it names that are written before it (or
    /// itself), else the nearest earlier frame in another lane unless it is the first or a reset frame.
    private static func sources(of written: EventModelWrittenFrame, at index: Int, frames: [EventModelFrame],
                                frameIndexByIdentifier: [String: Int]) -> [Int] {
        guard written.sourceIdentifiers.isEmpty else {
            let named = Set(written.sourceIdentifiers.compactMap { identifier in frameIndexByIdentifier[identifier] }.filter { source in source <= index })
            return named.sorted()
        }
        guard index > 0, !written.isReset else { return [] }
        let lane = frames[index].laneIndex
        guard let nearest = frames[..<index].lastIndex(where: { frame in frame.laneIndex != lane }) else { return [] }
        return [nearest]
    }

    /// The text between the outer braces (or, without a brace, inside the quotation marks), without carriage returns,
    /// the blank lines at either end and the indentation its lines share, each line without its trailing whitespace.
    static func blockText(_ raw: String) -> String {
        let scalars = Array(raw.unicodeScalars)
        let opening = scalars.firstIndex(of: "{")
        let closing = scalars.lastIndex(of: "}")
        var inner: ArraySlice<Unicode.Scalar> = []
        if let opening, let closing, closing > opening {
            inner = scalars[(opening + 1)..<closing]
        } else if opening == nil, scalars.count >= 2 {
            inner = scalars[1..<(scalars.count - 1)]
        }
        var lines = inner.filter { scalar in scalar != "\r" }.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
        while let first = lines.first, first.allSatisfy(isWhitespace) { lines.removeFirst() }
        while let last = lines.last, last.allSatisfy(isWhitespace) { lines.removeLast() }
        let indent = lines.filter { line in !line.allSatisfy(isWhitespace) }.map { line in line.prefix(while: isWhitespace).count }.min() ?? 0
        return lines.map { line in
            var kept = line.dropFirst(min(indent, line.count))
            while let last = kept.last, isWhitespace(last) { kept = kept.dropLast() }
            var text = ""
            text.unicodeScalars.append(contentsOf: kept)
            return text
        }.joined(separator: "\n")
    }

    /// JavaScript's whitespace (`\s`).
    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: true
        default: false
        }
    }
}

/// The lanes of an event model as its frames meet them: one per group of kinds, and one more per namespace in a group,
/// each with Mermaid's ordering key.
struct EventModelLaneAssignment {
    private var lanes: [EventModelLane] = []
    private var indexByKey: [String: Int] = [:]
    private var nextOrderKeyByGroup: [EventModelLaneGroup: Int] = [:]

    /// The index, in the order lanes were met, of the lane of a frame of `kind` in `namespace`.
    mutating func laneIndex(of kind: EventModelEntityKind, namespace: String?) -> Int {
        let group = kind.laneGroup
        let key = namespace.map { namespace in "\(group) \(namespace)" } ?? "\(group)"
        if let index = indexByKey[key] { return index }
        let (firstKey, label, prefix) = Self.groupNaming(group)
        var orderKey = firstKey
        if namespace != nil {
            orderKey = nextOrderKeyByGroup[group] ?? firstKey + 1
            nextOrderKeyByGroup[group] = orderKey + 1
        }
        lanes.append(EventModelLane(orderKey: orderKey, label: namespace.map { namespace in prefix + namespace } ?? label, group: group,
                                    namespace: namespace))
        indexByKey[key] = lanes.count - 1
        return lanes.count - 1
    }

    /// The lanes sorted by their ordering key (lanes of one key in the order they were met), and the sorted index of
    /// each lane by the index it was given.
    func sortedLanes() -> (lanes: [EventModelLane], newIndexByAssignedIndex: [Int]) {
        let order = lanes.indices.sorted { first, second in
            lanes[first].orderKey != lanes[second].orderKey ? lanes[first].orderKey < lanes[second].orderKey : first < second
        }
        var newIndex = [Int](repeating: 0, count: lanes.count)
        for (sortedIndex, assignedIndex) in order.enumerated() { newIndex[assignedIndex] = sortedIndex }
        return (order.map { index in lanes[index] }, newIndex)
    }

    /// The first ordering key, the label and the namespace's label prefix of a group's lanes.
    private static func groupNaming(_ group: EventModelLaneGroup) -> (Int, String, String) {
        switch group {
        case .trigger: (0, "UI/Automation", "UI/A: ")
        case .state: (100, "Command/Read Model", "C/RM: ")
        case .stream: (200, "Events", "Stream: ")
        }
    }
}

extension EventModelFrame {
    /// The same frame in the lane at `laneIndex`.
    func withLane(_ laneIndex: Int) -> EventModelFrame {
        EventModelFrame(identifier: identifier, kind: kind, entity: entity, name: name, namespace: namespace, isReset: isReset, laneIndex: laneIndex,
                        data: data, dataType: dataType)
    }
}
