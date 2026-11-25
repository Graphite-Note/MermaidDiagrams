/**
 * File: UseCaseDiagramPublishing.swift
 * ------------------------------------
 * Layer: Core
 * Description: A use case diagram's actors, use cases, boundaries and notes written as the model's records once their
 *              declarations are resolved, in the order Pele publishes them, then its class definitions, `class` and
 *              `style` statements applied, each list made once whatever the order of the statements that add to it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

extension UseCaseDiagramBuilder {
    /// Each element checked in the order it was added, then the actors and use cases in the order first mentioned,
    /// and the boundaries with their members.
    mutating func publishElements() throws(UseCaseBuildFailure) {
        var actorCount = 0
        var classCount = 0
        for state in elements {
            try checkGeometry(of: state)
            if state.kind == .actor { actorCount += 1 }
            classCount += state.classes.count
        }
        diagram.actorRecords.reserveCapacity(actorCount)
        diagram.useCaseRecords.reserveCapacity(elements.count - actorCount)
        diagram.namePool.reserveCapacity(diagram.namePool.count + classCount)
        for place in placesInMentionOrder(elements.map(\.name.name)) {
            let state = elements[place]
            let parent = namedParent(state.parent)
            let parentName = parent >= 0 ? drafts.boundaries[Int(parent)].name.name : -1
            let classes = pooled(state.classes)
            if state.kind == .actor {
                diagram.actorRecords.append(UseCaseElementRecord(
                    name: state.name.name, label: state.name.label, actorType: state.hasIcon ? .icon : state.actorType ?? .normal, shape: .ellipse,
                    icon: state.icon, hasIcon: state.hasIcon, isBusiness: state.isBusiness ?? false, stereotype: state.stereotype,
                    hasStereotype: state.hasStereotype, parent: parentName, classes: classes, styles: .empty))
            } else {
                diagram.useCaseRecords.append(UseCaseElementRecord(
                    name: state.name.name, label: state.name.label, actorType: .normal, shape: state.shape ?? .ellipse, icon: .empty, hasIcon: false,
                    isBusiness: state.isBusiness ?? false, stereotype: state.stereotype, hasStereotype: state.hasStereotype, parent: parentName,
                    classes: classes, styles: .empty))
            }
        }
        publishBoundaries()
    }

    /// `names` added to the diagram's name pool, and where.
    mutating func pooled(_ names: [Int32]) -> UseCaseListSpan {
        guard !names.isEmpty else { return .empty }
        let start = diagram.namePool.count
        diagram.namePool.append(contentsOf: names)
        return UseCaseListSpan(start: Int32(start), count: Int32(names.count))
    }

    /// An icon goes with a plain figure only, and a business element with a figure or an oval.
    private func checkGeometry(of state: UseCaseElementState) throws(UseCaseBuildFailure) {
        guard state.kind == .actor else {
            if state.shape == .rectangle, state.isBusiness == true {
                throw contradiction(.rectangularBusinessUseCase(identifier: identifier(state.name.name)), at: state.name.start)
            }
            return
        }
        if state.hasIcon, let type = state.actorType, type != .normal {
            throw contradiction(.iconWithActorType(actor: identifier(state.name.name), type: type), at: state.name.start)
        }
        if state.isBusiness == true, state.hasIcon || state.actorType == .awesome {
            throw contradiction(.businessActorGeometry(actor: identifier(state.name.name)), at: state.name.start)
        }
    }

    /// Each boundary with the elements declared in it, in the order written, and its type.
    private mutating func publishBoundaries() {
        // Without boundaries no element has a parent, and there is nothing to publish.
        guard !drafts.boundaries.isEmpty else { return }
        let declarations = drafts.elements.indices.sorted { first, second in
            let firstStart = drafts.elements[first].name.start
            let secondStart = drafts.elements[second].name.start
            return firstStart != secondStart ? firstStart < secondStart : first < second
        }
        // By element: the boundary it was placed in, so that each is placed once.
        var placedIn = [Int32](repeating: -1, count: diagram.nameRanges.count)
        for place in declarations {
            let draft = drafts.elements[place]
            let parent = namedParent(draft.parent)
            guard parent >= 0 else { continue }
            let boundary = drafts.boundaries[Int(parent)].name.name
            guard placedIn[Int(draft.name.name)] != boundary else { continue }
            placedIn[Int(draft.name.name)] = boundary
            let boundaryPlace = nameStates[Int(boundary)].boundary
            if boundaryPlace >= 0 { boundaries[Int(boundaryPlace)].members.append(draft.name.name) }
        }
        for place in placesInMentionOrder(boundaries.map(\.name.name)) {
            let state = boundaries[place]
            let members = pooled(state.members)
            let classes = pooled(state.classes)
            diagram.boundaryRecords.append(UseCaseBoundaryRecord(name: state.name.name, label: state.name.label, type: state.type ?? .rectangle,
                                                                 members: members, classes: classes, styles: .empty))
        }
    }

    /// The notes, each for an actor or a use case.
    mutating func resolveNotes() throws(UseCaseBuildFailure) {
        for note in drafts.notes {
            guard let origin = nameStates[Int(note.target)].kind else {
                throw contradiction(.unresolvedNoteTarget(identifier: identifier(note.target)), at: note.start)
            }
            guard origin == .actor || origin == .useCase else {
                throw contradiction(.noteTargetKind(identifier: identifier(note.target), kind: origin), at: note.start)
            }
            diagram.noteRecords.append(UseCaseNoteRecord(target: note.target, label: note.label))
        }
    }
}
