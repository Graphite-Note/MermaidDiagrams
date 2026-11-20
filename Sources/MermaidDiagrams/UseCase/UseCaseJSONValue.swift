/**
 * File: UseCaseJSONValue.swift
 * ----------------------------
 * Layer: Core
 * Description: A JSON value as a use case diagram's `json` table holds it: its objects' keys in the order written, held
 *              flat so that no depth of nesting is walked by recursion, and the order of each object's keys by its JSON
 *              Pointer, as Pele's propertyOrder records it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// A JSON value read in the order its keys are written. Every value is an entry of one flat list, the root first, each
/// container listing its children by their place in it, so that comparing, copying and freeing a value nested
/// thousands deep walks no recursion. A key written twice keeps its first place and takes its last value, as Pele's
/// `parseOrderedJson` does; the value it replaced stays in the list unreferenced.
public struct UseCaseJSONValue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case object
        case array
        case string(String)
        case number(Double)
        case boolean(Bool)
        case null
    }

    public struct Entry: Equatable, Sendable {
        public let kind: Kind
        /// An object's keys, in the order first written; empty for other kinds.
        public internal(set) var keys: [String]
        /// A container's values by their places in `entries`: an object's in the order of its keys.
        public internal(set) var children: [Int]
    }

    /// Every value read, the root first.
    public internal(set) var entries: [Entry]

    /// The empty object.
    static let emptyObject = UseCaseJSONValue(entries: [Entry(kind: .object, keys: [], children: [])])

    /// The root's entry.
    public var root: Entry { entries[0] }

    /// The keys of each object reachable from the root, in the order written, by its JSON Pointer (`""` for the root,
    /// `/items/0` for the first value of `items`, `~` and `/` in a key written `~0` and `~1`), as Pele's propertyOrder.
    public var propertyOrder: [String: [String]] {
        var order: [String: [String]] = [:]
        var pending: [(entry: Int, pointer: String)] = [(0, "")]
        while let (index, pointer) = pending.popLast() {
            let entry = entries[index]
            switch entry.kind {
            case .object:
                order[pointer] = entry.keys
                for (key, child) in zip(entry.keys, entry.children) { pending.append((child, pointer + "/" + Self.pointerToken(key))) }
            case .array:
                for (position, child) in entry.children.enumerated() { pending.append((child, pointer + "/" + String(position))) }
            default: break
            }
        }
        return order
    }

    /// A key as a JSON Pointer writes it: `~` as `~0`, then `/` as `~1`.
    static func pointerToken(_ key: String) -> String {
        key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }
}
