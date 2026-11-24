/**
 * File: FlowchartShapeNameTable.swift
 * -----------------------------------
 * Layer: Core
 * Description: The shapes Mermaid documents, found by the bytes of their names in an open-addressing table made once,
 *              so that `@{ shape: … }` names a shape without a String.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Mermaid's documented shape names (`FlowchartNodeShape.documentedNames`) by their UTF-8 bytes: those
/// `FlowchartNodeShape.named` takes, lower case without an underscore (`squareRect` is refused there, and so not found).
enum FlowchartShapeNameTable {
    private struct Entry {
        var hash: UInt32
        var start: Int32
        var length: Int32
        var shape: FlowchartNodeShape
    }

    private struct Table {
        var entries: [Entry?]
        var names: [UInt8]
    }

    private static let slotCount = 512

    private static let table: Table = {
        var names: [UInt8] = []
        var entries = [Entry?](repeating: nil, count: slotCount)
        for (shape, shapeNames) in FlowchartNodeShape.documentedNames {
            for name in shapeNames where name == name.lowercased() && !name.contains("_") {
                let start = Int32(names.count)
                names.append(contentsOf: name.utf8)
                let hash = names.withUnsafeBufferPointer { buffer in Self.hash(buffer.baseAddress! + Int(start), count: name.utf8.count) }
                var slot = Int(hash) & (slotCount - 1)
                while entries[slot] != nil { slot = (slot + 1) & (slotCount - 1) }
                entries[slot] = Entry(hash: hash, start: start, length: Int32(name.utf8.count), shape: shape)
            }
        }
        return Table(entries: entries, names: names)
    }()

    private static func hash(_ start: UnsafePointer<UInt8>, count: Int) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for offset in 0..<count { hash = (hash ^ UInt32(start[offset])) &* 0x0100_0193 }
        return hash
    }

    /// The documented shape `name` spells, or nil.
    static func shape(named name: UnsafeBufferPointer<UInt8>) -> FlowchartNodeShape? {
        guard let start = name.baseAddress, !name.isEmpty else { return nil }
        let hash = hash(start, count: name.count)
        let table = table
        var slot = Int(hash) & (slotCount - 1)
        while let entry = table.entries[slot] {
            if entry.hash == hash, Int(entry.length) == name.count,
               table.names.withUnsafeBufferPointer({ names in memcmp(names.baseAddress! + Int(entry.start), start, name.count) == 0 }) { return entry.shape }
            slot = (slot + 1) & (slotCount - 1)
        }
        return nil
    }
}
