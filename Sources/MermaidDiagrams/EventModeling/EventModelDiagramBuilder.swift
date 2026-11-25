/**
 * File: EventModelDiagramBuilder.swift
 * ------------------------------------
 * Layer: Core
 * Description: Builds an event model from its statements as Mermaid's database does: one lane per group of kinds and
 *              namespace, each frame's data, and the relations its sources name or the frame before it implies; each
 *              frame made once, in its sorted lane, its frame number looked up in a short list or a table.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

/// Builds an `EventModelDiagram` from what `EventModelParser` read, as Pele's `buildEventModel` does after Mermaid's
/// database: a frame number used twice refuses the diagram; a frame that names its sources is fed by those of them
/// written before it, in their order; any other frame but the first and reset frames is fed by the nearest earlier
/// frame in another lane. The lanes are met first, so that each frame is made once in its sorted lane; which frame
/// feeds which depends only on whether two lanes are one, which the order lanes were met in tells as well.
enum EventModelDiagramBuilder {
    static func diagram(of statements: EventModelStatements, bytes: [UInt8], limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> EventModelDiagram {
        let written = statements.frames
        var frameNumbers = EventModelFrameNumbers(capacity: written.count)
        for index in written.indices where !frameNumbers.insert(written[index].identifier, at: index) {
            let line = FirstMatchTokenReader<EventModelTokenKind>.line(of: written[index].position, in: bytes)
            throw .invalidSyntax(line: line, problem: .eventModeling(.duplicateFrame(identifier: written[index].identifier)))
        }
        var lanes = EventModelLaneAssignment()
        var entities: [EventModelEntityName] = []
        entities.reserveCapacity(written.count)
        var laneIndices: [Int] = []
        laneIndices.reserveCapacity(written.count)
        for index in written.indices {
            let entity = EventModelEntityName(written[index].entity, kindKeyword: written[index].kindKeyword)
            entities.append(entity)
            laneIndices.append(lanes.laneIndex(of: entity.kind, namespace: entity.namespace))
        }
        var relations: [EventModelRelation] = []
        relations.reserveCapacity(written.count)
        var sources: [Int] = []
        for index in written.indices {
            Self.sources(of: written[index], at: index, laneIndices: laneIndices, frameNumbers: frameNumbers, into: &sources)
            for source in sources {
                guard relations.count < limits.maximumEdgeCount else { throw .tooManyEdges(limit: limits.maximumEdgeCount) }
                relations.append(EventModelRelation(sourceFrameIndex: source, targetFrameIndex: index))
            }
        }
        var dataByName: [String: String] = [:]
        for dataBlock in statements.dataBlocks where dataByName[dataBlock.name] == nil { dataByName[dataBlock.name] = dataBlock.block }
        let sorted = lanes.sortedLanes()
        var frames: [EventModelFrame] = []
        frames.reserveCapacity(written.count)
        for index in written.indices {
            let entity = entities[index]
            frames.append(EventModelFrame(identifier: written[index].identifier, kind: entity.kind, entity: written[index].entity, name: entity.name,
                                          namespace: entity.namespace, isReset: written[index].isReset,
                                          laneIndex: sorted.newIndexByAssignedIndex[laneIndices[index]],
                                          data: data(of: written[index], dataByName: dataByName), dataType: written[index].dataType))
        }
        return EventModelDiagram(
            title: statements.title.map(FirstMatchStatementValues.title).flatMap { title in title.isEmpty ? nil : title },
            accessibilityTitle: statements.accessibilityTitle.map(FirstMatchStatementValues.accessibilityTitle),
            accessibilityDescription: statements.accessibilityDescription.map(FirstMatchStatementValues.accessibilityDescription),
            frames: frames, lanes: sorted.lanes, relations: relations, notes: statements.notes, specifications: statements.specifications,
            entities: statements.entities)
    }

    /// The frame's data: of the data block it names, when one of that name was written, else its own written data.
    private static func data(of frame: EventModelWrittenFrame, dataByName: [String: String]) -> String? {
        if let reference = frame.dataReference, let block = dataByName[reference] { return blockText(block) }
        return frame.inlineData.map(blockText)
    }

    /// The frames that feed the frame at `index`, in frame order, into `sources`: the sources it names that are written
    /// before it (or itself), each once, else the nearest earlier frame in another lane unless it is the first or a
    /// reset frame.
    private static func sources(of frame: EventModelWrittenFrame, at index: Int, laneIndices: [Int], frameNumbers: EventModelFrameNumbers,
                                into sources: inout [Int]) {
        sources.removeAll(keepingCapacity: true)
        guard frame.sourceIdentifiers.isEmpty else {
            for identifier in frame.sourceIdentifiers {
                if let source = frameNumbers.index(of: identifier), source <= index { sources.append(source) }
            }
            guard sources.count > 1 else { return }
            sources.sort()
            var kept = 1
            for position in 1..<sources.count where sources[position] != sources[kept - 1] {
                sources[kept] = sources[position]
                kept += 1
            }
            sources.removeSubrange(kept...)
            return
        }
        guard index > 0, !frame.isReset else { return }
        let lane = laneIndices[index]
        if let nearest = laneIndices[..<index].lastIndex(where: { other in other != lane }) { sources.append(nearest) }
    }
}

/// A frame's entity as Mermaid's database reads it: only a name of two parts has a namespace, the part before its dot.
/// A name of ASCII alone, as the grammar's names are, is cut at its dot on its bytes; any other as Swift's characters
/// split it.
struct EventModelEntityName {
    let kind: EventModelEntityKind
    let name: String
    let namespace: String?

    init(_ entity: String, kindKeyword: String) {
        kind = EventModelEntityKind(keyword: kindKeyword)
        let utf8 = entity.utf8
        var dot: String.Index?
        var dotCount = 0
        var position = utf8.startIndex
        while position != utf8.endIndex {
            let byte = utf8[position]
            guard byte < 0x80 else {
                let parts = entity.split(separator: ".", omittingEmptySubsequences: false)
                name = parts.count == 2 ? String(parts[1]) : entity
                namespace = parts.count == 2 ? String(parts[0]) : nil
                return
            }
            if byte == UInt8(ascii: ".") {
                dot = position
                dotCount += 1
            }
            utf8.formIndex(after: &position)
        }
        guard dotCount == 1, let dot else {
            name = entity
            namespace = nil
            return
        }
        name = String(entity[utf8.index(after: dot)...])
        namespace = String(entity[..<dot])
    }
}

/// The frames' numbers as written, and each one's frame: a short list searched in turn, then a table once there are more
/// than `mostNumbersSearched`, so that a long model's lookups do not grow with its frames.
struct EventModelFrameNumbers {
    private var numbers: [String] = []
    private var indexByNumber: [String: Int] = [:]

    /// The most numbers looked up by comparing them in turn.
    private static let mostNumbersSearched = 16

    init(capacity: Int) {
        numbers.reserveCapacity(capacity)
    }

    /// Adds `number` as the frame at `index`, which follows the frames added before; false, adding nothing, when it is
    /// there already.
    mutating func insert(_ number: String, at index: Int) -> Bool {
        guard self.index(of: number) == nil else { return false }
        numbers.append(number)
        if numbers.count > Self.mostNumbersSearched {
            if indexByNumber.isEmpty {
                for (earlier, written) in numbers.enumerated() { indexByNumber[written] = earlier }
            } else {
                indexByNumber[number] = index
            }
        }
        return true
    }

    func index(of number: String) -> Int? {
        numbers.count > Self.mostNumbersSearched ? indexByNumber[number] : numbers.firstIndex(of: number)
    }
}
