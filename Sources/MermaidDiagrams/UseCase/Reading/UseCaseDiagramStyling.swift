/**
 * File: UseCaseDiagramStyling.swift
 * ---------------------------------
 * Layer: Core
 * Description: A use case diagram's class definitions, `class` statements and `style` statements applied as Pele's
 *              `resolveUsecase` applies them: each target found in the order written, the first one missing the error,
 *              then each target's classes and styles made once, so that no order of statements copies a list again.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

extension UseCaseDiagramBuilder {
    /// The class definitions, each name in its first place with its last styles, then `class` and `style` statements.
    mutating func applyClassesAndStyles() throws(UseCaseBuildFailure) {
        var definitionPlaces = [Int32](repeating: -1, count: diagram.nameRanges.count)
        for definition in drafts.classDefinitions {
            let styles = pooledStyles([definition.styles])
            for name in drafts.names[definition.names.range] {
                let place = definitionPlaces[Int(name)]
                if place >= 0 {
                    diagram.classDefinitionRecords[Int(place)].styles = styles
                } else {
                    definitionPlaces[Int(name)] = Int32(diagram.classDefinitionRecords.count)
                    diagram.classDefinitionRecords.append(UseCaseClassDefinitionRecord(name: name, styles: styles))
                }
            }
        }
        // Only `class` and `style` statements look anything up.
        guard !drafts.classAssignments.isEmpty || !drafts.styles.isEmpty else { return }
        let places = UseCaseStylablePlaces(diagram: diagram)
        var classChanges: [(item: Int32, assignment: Int32)] = []
        for (assignment, statement) in drafts.classAssignments.enumerated() {
            for target in drafts.targets[statement.targets.range] {
                classChanges.append((try stylable(target.name, at: target.start, places: places), Int32(assignment)))
            }
        }
        var styleChanges: [(item: Int32, statement: Int32)] = []
        for (place, statement) in drafts.styles.enumerated() {
            styleChanges.append((try stylable(statement.target, at: statement.start, places: places), Int32(place)))
        }
        for (item, changes) in Self.grouped(classChanges.map(\.item), places.itemCount) {
            var classes = names(of: item, places: places)
            for change in changes {
                let assignment = drafts.classAssignments[Int(classChanges[change].assignment)]
                Self.appendUnique(drafts.names[assignment.classes.range], to: &classes, marks: &nameStates, mark: &seenMark)
            }
            setClasses(pooled(classes), of: item, places: places)
        }
        for (item, changes) in Self.grouped(styleChanges.map(\.item), places.itemCount) {
            setStyles(pooledStyles(changes.map { change in drafts.styles[Int(styleChanges[change].statement)].styles }), of: item, places: places)
        }
    }

    /// The styles of `spans` of the drafts' style pool, one after another, added to the diagram's style pool.
    private mutating func pooledStyles(_ spans: [UseCaseListSpan]) -> UseCaseListSpan {
        let start = diagram.stylePool.count
        for span in spans { diagram.stylePool.append(contentsOf: drafts.styleTexts[span.range]) }
        return UseCaseListSpan(start: Int32(start), count: Int32(diagram.stylePool.count - start))
    }

    /// The item `name` names for a `class` or `style` statement: an actor, a use case, a boundary or a JSON table by
    /// its kind, else a relationship by its id.
    private func stylable(_ name: Int32, at start: Int32, places: UseCaseStylablePlaces) throws(UseCaseBuildFailure) -> Int32 {
        let found: Int32 = switch nameStates[Int(name)].kind {
        case .actor?: places.actors[Int(name)] >= 0 ? places.actors[Int(name)] : -1
        case .useCase?: places.useCases[Int(name)] >= 0 ? places.useCaseStart + places.useCases[Int(name)] : -1
        case .boundary?: places.boundaries[Int(name)] >= 0 ? places.boundaryStart + places.boundaries[Int(name)] : -1
        case .json?: places.jsonNodes[Int(name)] >= 0 ? places.jsonStart + places.jsonNodes[Int(name)] : -1
        default: nameStates[Int(name)].relationship >= 0 ? places.relationshipStart + nameStates[Int(name)].relationship : -1
        }
        guard found >= 0 else { throw contradiction(.unresolvedStyleTarget(identifier: identifier(name)), at: start) }
        return found
    }

    /// The places of `items` grouped by item, each group in the order its places come, the groups by item.
    private static func grouped(_ items: [Int32], _ itemCount: Int) -> [(item: Int32, places: [Int])] {
        guard !items.isEmpty else { return [] }
        var counts = [Int](repeating: 0, count: itemCount)
        for item in items { counts[Int(item)] += 1 }
        var groups: [(item: Int32, places: [Int])] = []
        var groupOf = [Int](repeating: -1, count: itemCount)
        for (place, item) in items.enumerated() {
            if groupOf[Int(item)] < 0 {
                groupOf[Int(item)] = groups.count
                var places: [Int] = []
                places.reserveCapacity(counts[Int(item)])
                groups.append((item, places))
            }
            groups[groupOf[Int(item)]].places.append(place)
        }
        return groups
    }

    private func names(of item: Int32, places: UseCaseStylablePlaces) -> [Int32] {
        let span: UseCaseListSpan
        switch places.kind(of: item) {
        case .actor(let place): span = diagram.actorRecords[place].classes
        case .useCase(let place): span = diagram.useCaseRecords[place].classes
        case .boundary(let place): span = diagram.boundaryRecords[place].classes
        case .json(let place): span = diagram.jsonRecords[place].classes
        case .relationship(let place): span = diagram.relationshipRecords[place].classes
        }
        return span.isEmpty ? [] : Array(diagram.namePool[span.range])
    }

    private mutating func setClasses(_ classes: UseCaseListSpan, of item: Int32, places: UseCaseStylablePlaces) {
        switch places.kind(of: item) {
        case .actor(let place): diagram.actorRecords[place].classes = classes
        case .useCase(let place): diagram.useCaseRecords[place].classes = classes
        case .boundary(let place): diagram.boundaryRecords[place].classes = classes
        case .json(let place): diagram.jsonRecords[place].classes = classes
        case .relationship(let place): diagram.relationshipRecords[place].classes = classes
        }
    }

    private mutating func setStyles(_ styles: UseCaseListSpan, of item: Int32, places: UseCaseStylablePlaces) {
        switch places.kind(of: item) {
        case .actor(let place): diagram.actorRecords[place].styles = styles
        case .useCase(let place): diagram.useCaseRecords[place].styles = styles
        case .boundary(let place): diagram.boundaryRecords[place].styles = styles
        case .json(let place): diagram.jsonRecords[place].styles = styles
        case .relationship(let place): diagram.relationshipRecords[place].styles = styles
        }
    }
}

/// Where each name's actor, use case, boundary and JSON table is among the diagram's records (its first, or -1), and
/// one numbering of all the items a `class` or `style` statement can change: the actors, then the use cases, the
/// boundaries, the JSON tables and the relationships.
struct UseCaseStylablePlaces {
    enum Item {
        case actor(Int), useCase(Int), boundary(Int), json(Int), relationship(Int)
    }

    let actors: [Int32]
    let useCases: [Int32]
    let boundaries: [Int32]
    let jsonNodes: [Int32]
    let useCaseStart: Int32
    let boundaryStart: Int32
    let jsonStart: Int32
    let relationshipStart: Int32
    let itemCount: Int

    init(diagram: UseCaseDiagram) {
        func places(_ names: [Int32]) -> [Int32] {
            var places = [Int32](repeating: -1, count: diagram.nameRanges.count)
            for (place, name) in names.enumerated() where places[Int(name)] < 0 { places[Int(name)] = Int32(place) }
            return places
        }
        actors = places(diagram.actorRecords.map(\.name))
        useCases = places(diagram.useCaseRecords.map(\.name))
        boundaries = places(diagram.boundaryRecords.map(\.name))
        jsonNodes = places(diagram.jsonRecords.map(\.name))
        useCaseStart = Int32(diagram.actorRecords.count)
        boundaryStart = useCaseStart + Int32(diagram.useCaseRecords.count)
        jsonStart = boundaryStart + Int32(diagram.boundaryRecords.count)
        relationshipStart = jsonStart + Int32(diagram.jsonRecords.count)
        itemCount = Int(relationshipStart) + diagram.relationshipRecords.count
    }

    func kind(of item: Int32) -> Item {
        if item < useCaseStart { return .actor(Int(item)) }
        if item < boundaryStart { return .useCase(Int(item - useCaseStart)) }
        if item < jsonStart { return .boundary(Int(item - boundaryStart)) }
        if item < relationshipStart { return .json(Int(item - jsonStart)) }
        return .relationship(Int(item - relationshipStart))
    }
}
