/**
 * File: FlowchartSubgraphNesting.swift
 * ------------------------------------
 * Layer: Core
 * Description: Nests a flowchart's groups once its text is read: a member whose name is a group's identifier is that
 *              group, inside the one that took it; groups in a loop are lifted to the top as Pele lifts them; each
 *              group is listed before the groups inside it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

extension FlowchartParser {
    /// Turns the groups, in the order they ended, into the model's groups: a member whose name is a group's identifier
    /// is that group, inside this one; the others are nodes. A group in a loop of groups (each named inside the next)
    /// is lifted to the top, the group that ended last first, as Pele does. Each group is listed before the groups
    /// inside it, groups side by side in the order they opened.
    mutating func nestGroups() {
        let groupCount = lists.endedGroups.count
        guard groupCount > 0 else { return }
        var parents = [Int](repeating: -1, count: groupCount)
        var children = [[Int]](repeating: [], count: groupCount)
        for group in 0..<groupCount {
            forEachMember(ofEndedGroup: group) { name in
                let child = Int(lists.names.names[name].endedGroupIndex)
                guard child >= 0 else { return }
                parents[child] = group
                children[group].append(child)
            }
        }
        Self.liftGroupsInLoops(parents: &parents, children: &children)
        let order = preorder(parents: parents, children: children)
        var place = [Int32](repeating: 0, count: groupCount)
        for (position, group) in order.enumerated() { place[group] = Int32(position) }
        parts.groups.reserveCapacity(groupCount)
        for endedIndex in order { addGroup(endedIndex, children: children[endedIndex], place: place) }
    }

    /// The model's record of the ended group at `endedIndex`: its node members, then its children by their places.
    private mutating func addGroup(_ endedIndex: Int, children: [Int], place: [Int32]) {
        let group = lists.endedGroups[endedIndex]
        let nodesStart = Int32(parts.groupMembers.count)
        var run = Int(group.firstRun)
        while run >= 0 {
            let members = lists.memberRuns[run]
            for place in Int(members.start)..<Int(members.start + members.count) {
                let member = lists.names.names[Int(lists.endedMembers[place])]
                if member.endedGroupIndex < 0, member.nodeIndex >= 0 { parts.groupMembers.append(member.nodeIndex) }
            }
            run = Int(members.next)
        }
        let childrenStart = Int32(parts.groupMembers.count)
        for child in children { parts.groupMembers.append(place[child]) }
        let name = lists.names.names[Int(group.name)]
        parts.groups.append(FlowchartGroupRecord(identifier: group.writtenIdentifier, generatedNumber: group.generatedNumber, title: group.title,
                                                 direction: group.direction, representingNodeIndex: name.nodeIndex, isCollapsed: name.isCollapsed,
                                                 nodeIndices: nodesStart..<childrenStart, childGroupIndices: childrenStart..<Int32(parts.groupMembers.count)))
    }

    /// A group cannot be reached from the top when its parents loop; the last such group to end loses its parent,
    /// which places the rest of its loop inside it.
    private static func liftGroupsInLoops(parents: inout [Int], children: inout [[Int]]) {
        var isReachable = [Bool](repeating: false, count: parents.count)
        func markReachable(from root: Int) {
            var stack = [root]
            while let group = stack.popLast() {
                guard !isReachable[group] else { continue }
                isReachable[group] = true
                stack.append(contentsOf: children[group])
            }
        }
        for group in parents.indices where parents[group] < 0 { markReachable(from: group) }
        for group in parents.indices.reversed() where !isReachable[group] {
            if parents[group] >= 0 { children[parents[group]].removeAll { child in child == group } }
            parents[group] = -1
            markReachable(from: group)
        }
    }

    /// The groups depth first: the top-level groups in the order they opened, each followed by the groups inside it.
    /// Each group is listed once: a group is in one group's members at most, which the lifting leaves a tree.
    private func preorder(parents: [Int], children: [[Int]]) -> [Int] {
        let roots = parents.indices.filter { group in parents[group] < 0 }.sorted { first, second in
            lists.endedGroups[first].openingOrder < lists.endedGroups[second].openingOrder
        }
        var order: [Int] = []
        order.reserveCapacity(parents.count)
        var isListed = [Bool](repeating: false, count: parents.count)
        var stack = Array(roots.reversed())
        while let group = stack.popLast() {
            guard !isListed[group] else { continue }
            isListed[group] = true
            order.append(group)
            stack.append(contentsOf: children[group].reversed())
        }
        return order
    }
}
