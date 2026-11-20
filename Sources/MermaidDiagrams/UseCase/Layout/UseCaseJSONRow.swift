/**
 * File: UseCaseJSONRow.swift
 * --------------------------
 * Layer: Core
 * Description: The rows of a use case diagram's JSON table, as Pele's flattenJsonRows makes them: one for each leaf of
 *              the object, depth first in the order its keys are written, each under the path of keys to it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// One row of a JSON table: a leaf's path of keys (`items[0].name`), blank on the second and later values of an array
/// of scalars, the path again for a screen reader, and the value as JavaScript writes it.
struct UseCaseJSONRow: Equatable {
    let key: String
    let accessibleKey: String
    let value: String

    /// One row for each leaf of `value`, depth first in the order its keys are written: an array of scalars a row a
    /// value, an empty array `[]`, an empty object `{}`. Nesting is kept on a stack of its own.
    static func rows(of value: UseCaseJSONValue) -> [UseCaseJSONRow] {
        var rows: [UseCaseJSONRow] = []
        var pending: [(entry: Int, path: String)] = [(0, "")]
        while let (index, path) = pending.popLast() {
            let entry = value.entries[index]
            var children: [(Int, String)] = []
            switch entry.kind {
            case .array:
                if entry.children.isEmpty {
                    rows.append(UseCaseJSONRow(key: path, accessibleKey: path, value: "[]"))
                } else if entry.children.allSatisfy({ child in !isContainer(value.entries[child].kind) }) {
                    for (position, child) in entry.children.enumerated() {
                        rows.append(UseCaseJSONRow(key: position == 0 ? path : "", accessibleKey: path, value: text(of: value.entries[child].kind)))
                    }
                } else {
                    children = entry.children.enumerated().map { position, child in (child, "\(path)[\(position)]") }
                }
            case .object:
                if entry.keys.isEmpty { rows.append(UseCaseJSONRow(key: path, accessibleKey: path, value: "{}")) }
                children = zip(entry.keys, entry.children).map { key, child in (child, path.isEmpty ? key : path + "." + key) }
            default:
                rows.append(UseCaseJSONRow(key: path, accessibleKey: path, value: text(of: entry.kind)))
            }
            pending.append(contentsOf: children.reversed())
        }
        return rows
    }

    private static func isContainer(_ kind: UseCaseJSONValue.Kind) -> Bool {
        kind == .object || kind == .array
    }

    /// A scalar as JavaScript's `String()` writes it.
    private static func text(of kind: UseCaseJSONValue.Kind) -> String {
        switch kind {
        case .string(let text): text
        case .number(let number): JavaScriptNumberText.text(number)
        case .boolean(let value): value ? "true" : "false"
        case .null: "null"
        case .object, .array: ""
        }
    }
}
