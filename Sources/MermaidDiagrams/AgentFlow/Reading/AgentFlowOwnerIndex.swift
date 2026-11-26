/**
 * File: AgentFlowOwnerIndex.swift
 * -------------------------------
 * Layer: Core
 * Description: The entries of one of an agent flow's lists (attributes, members) grouped by the element owning them,
 *              each group in the order written, counted once in time that grows with the list, in the scratch arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// A list's entries grouped by owner, in the thread's scratch arena: the entries of `owner` are
/// `order[starts[owner]..<starts[owner + 1]]`, indices into the list in the order written.
struct AgentFlowOwnerIndex {
    private let starts: ScratchSpan<Int32>
    private let order: ScratchSpan<Int32>

    /// No entries.
    init() {
        starts = .empty
        order = .empty
    }

    /// The `count` entries whose owners `owner(entry)` gives, among `ownerCount` owners, in `arena`; an owner out of
    /// range owns none.
    init(ownerCount: Int, count: Int, arena: DiagramScratchArena, owner: (Int) -> Int32) {
        let starts = arena.span(count: ownerCount + 1, repeating: Int32(0))
        for entry in 0..<count {
            let entryOwner = Int(owner(entry))
            if entryOwner >= 0, entryOwner < ownerCount { starts[entryOwner + 1] += 1 }
        }
        for index in 0..<ownerCount { starts[index + 1] += starts[index] }
        let fill = arena.copy(of: starts)
        let order: ScratchSpan<Int32> = arena.uninitializedSpan(count: Int(starts[ownerCount]))
        for entry in 0..<count {
            let entryOwner = Int(owner(entry))
            guard entryOwner >= 0, entryOwner < ownerCount else { continue }
            order[Int(fill[entryOwner])] = Int32(entry)
            fill[entryOwner] += 1
        }
        self.starts = starts
        self.order = order
    }

    /// The entries of `owner`, by their indices in the list; none when the index was made without entries.
    func entries(of owner: Int) -> ScratchSpan<Int32> {
        guard owner >= 0, owner + 1 < starts.count else { return .empty }
        return order.part(Int(starts[owner])..<Int(starts[owner + 1]))
    }
}
