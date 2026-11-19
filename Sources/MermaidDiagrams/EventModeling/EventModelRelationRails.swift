/**
 * File: EventModelRelationRails.swift
 * -----------------------------------
 * Layer: Core
 * Description: Which rail beside the cards each relation that skips a card runs on, in an event model laid out down a
 *              column, so that no two follow the same line; and which cards a relation between neighbours passes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The rails of an event model down a column, as Pele allocates them. A relation between neighbouring cards drops
/// straight past the lower card's lane name; one that skips a card runs on a rail at the right. Relations into one card
/// share a rail, spanning from the first to the last of their sources; others whose spans overlap take the next rail
/// out, and a rail is reused once the span on it has ended.
struct EventModelRelationRails {
    /// The rail of each target frame index fed over a rail, counted from the cards outward.
    let railByTarget: [Int: Int]
    let railCount: Int
    /// The frame indices whose lane name a relation from or to its neighbour passes beside.
    let passedFrames: Set<Int>

    init(relations: [EventModelRelation]) {
        var spans: [(target: Int, from: Int, to: Int)] = []
        var spanIndexByTarget: [Int: Int] = [:]
        var passed: Set<Int> = []
        for relation in relations {
            let source = relation.sourceFrameIndex
            let target = relation.targetFrameIndex
            guard source != target else { continue }
            if abs(source - target) < 2 {
                passed.insert(max(source, target))
                continue
            }
            if let index = spanIndexByTarget[target] {
                spans[index].from = min(spans[index].from, source)
                spans[index].to = max(spans[index].to, source)
            } else {
                spanIndexByTarget[target] = spans.count
                spans.append((target, min(source, target), max(source, target)))
            }
        }
        var railEnds: [Int] = []
        var rails: [Int: Int] = [:]
        for span in spans.enumerated().sorted(by: { first, second in
            first.element.from != second.element.from ? first.element.from < second.element.from : first.offset < second.offset
        }).map(\.element) {
            let rail = railEnds.firstIndex { end in end < span.from } ?? railEnds.count
            if rail == railEnds.count { railEnds.append(span.to) } else { railEnds[rail] = span.to }
            rails[span.target] = rail
        }
        railByTarget = rails
        railCount = railEnds.count
        passedFrames = passed
    }
}
