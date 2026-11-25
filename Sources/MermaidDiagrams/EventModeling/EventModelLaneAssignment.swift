/**
 * File: EventModelLaneAssignment.swift
 * ------------------------------------
 * Layer: Core
 * Description: The lanes of an event model as its frames meet them, one per group of kinds and one more per namespace
 *              in a group, with Mermaid's ordering keys, and their order from top to bottom.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The lanes of an event model as its frames meet them: one per group of kinds, and one more per namespace in a group,
/// each with Mermaid's ordering key. A lane is found among the few met so far by comparing them in turn, then in a table
/// once there are more than `mostLanesSearched`.
struct EventModelLaneAssignment {
    private var lanes: [EventModelLane] = []
    private var indexByKey: [LaneKey: Int] = [:]
    /// The next ordering key of a namespace's lane in each group, by `groupSlot`; 0 before its first.
    private var nextOrderKeys = [0, 0, 0]

    /// The most lanes looked up by comparing them in turn.
    private static let mostLanesSearched = 8

    /// A lane's group and namespace, as Mermaid keys a lane by `group namespace` (a group's name holds no space, so the
    /// two keys are told apart alike).
    private struct LaneKey: Hashable {
        let group: EventModelLaneGroup
        let namespace: String?
    }

    /// The index, in the order lanes were met, of the lane of a frame of `kind` in `namespace`.
    mutating func laneIndex(of kind: EventModelEntityKind, namespace: String?) -> Int {
        let group = kind.laneGroup
        if lanes.count <= Self.mostLanesSearched {
            if let index = lanes.firstIndex(where: { lane in lane.group == group && lane.namespace == namespace }) { return index }
        } else if let index = indexByKey[LaneKey(group: group, namespace: namespace)] {
            return index
        }
        let (firstKey, label, prefix) = Self.groupNaming(group)
        var orderKey = firstKey
        if namespace != nil {
            let slot = Self.groupSlot(group)
            orderKey = nextOrderKeys[slot] == 0 ? firstKey + 1 : nextOrderKeys[slot]
            nextOrderKeys[slot] = orderKey + 1
        }
        lanes.append(EventModelLane(orderKey: orderKey, label: namespace.map { namespace in prefix + namespace } ?? label, group: group,
                                    namespace: namespace))
        if lanes.count > Self.mostLanesSearched {
            if indexByKey.isEmpty {
                for (index, lane) in lanes.enumerated() { indexByKey[LaneKey(group: lane.group, namespace: lane.namespace)] = index }
            } else {
                indexByKey[LaneKey(group: group, namespace: namespace)] = lanes.count - 1
            }
        }
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

    private static func groupSlot(_ group: EventModelLaneGroup) -> Int {
        switch group {
        case .trigger: 0
        case .state: 1
        case .stream: 2
        }
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
