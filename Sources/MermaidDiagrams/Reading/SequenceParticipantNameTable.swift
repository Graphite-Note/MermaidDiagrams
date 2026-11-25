/**
 * File: SequenceParticipantNameTable.swift
 * ----------------------------------------
 * Layer: Core
 * Description: A sequence diagram's participants by identifier, in the order they are first named: the few of most
 *              diagrams found by comparing them in turn, a table made once there are more.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The identifiers of a sequence diagram's participants, each at its participant's index: looked up by comparing them
/// in turn while there are at most `mostNamesSearched`, which costs less than hashing each message's two names, then in
/// a table made of them once, so that a diagram of many participants does not look each up in time growing with them.
/// Identifiers are compared as Swift compares Strings, as the table compares them.
struct SequenceParticipantNameTable {
    private var names: [String] = []
    private var indexByName: [String: Int] = [:]

    /// The most identifiers looked up by comparing them in turn.
    private static let mostNamesSearched = 8

    /// The index of the participant `name` identifies, or nil when none does.
    func index(of name: String) -> Int? {
        names.count > Self.mostNamesSearched ? indexByName[name] : names.firstIndex(of: name)
    }

    /// `name` as the identifier of the next participant, which no participant has yet.
    mutating func append(_ name: String) {
        names.append(name)
        guard names.count > Self.mostNamesSearched else { return }
        if indexByName.isEmpty {
            for (index, earlier) in names.enumerated() { indexByName[earlier] = index }
        } else {
            indexByName[name] = names.count - 1
        }
    }
}
