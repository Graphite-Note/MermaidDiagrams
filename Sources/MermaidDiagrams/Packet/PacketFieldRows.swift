/**
 * File: PacketFieldRows.swift
 * ---------------------------
 * Layer: Core
 * Description: Splits a packet's fields at the ends of its rows, as Mermaid's database does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A field, or the part of one that lies in one row.
struct PacketFieldPiece: Equatable, Sendable {
    /// The index of the field in the diagram's fields, which gives its label.
    let fieldIndex: Int
    let firstBit: Int
    let lastBit: Int
}

enum PacketFieldRows {
    /// The pieces of `fields` row by row: a field that crosses the end of a row is cut there and goes on at the start of
    /// the next, and a row ends where its last bit is, whatever the fields after it. `fields` are contiguous from bit 0,
    /// and `bitsPerRow` is at least 1.
    static func rows(of fields: [PacketField], bitsPerRow: Int) -> [[PacketFieldPiece]] {
        var rows: [[PacketFieldPiece]] = []
        var row: [PacketFieldPiece] = []
        for (index, field) in fields.enumerated() {
            var firstBit = field.firstBit
            while true {
                let rowLastBit = (firstBit / bitsPerRow + 1) * bitsPerRow - 1
                row.append(PacketFieldPiece(fieldIndex: index, firstBit: firstBit, lastBit: min(field.lastBit, rowLastBit)))
                guard field.lastBit >= rowLastBit else { break }
                rows.append(row)
                row = []
                guard field.lastBit > rowLastBit else { break }
                firstBit = rowLastBit + 1
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}
