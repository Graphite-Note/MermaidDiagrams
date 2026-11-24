/**
 * File: FlatShapeNames.swift
 * --------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: Mermaid's shape names found by their bytes in a table made once, no String made to look one up.
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

enum FlatShapeNames {
    private struct Entry {
        var hash: UInt32
        var start: Int32
        var length: Int32
        var shape: FlowchartNodeShape
    }

    private struct Table {
        var entries: [Entry?]
        var bytes: [UInt8]
    }

    private static let table: Table = {
        var bytes: [UInt8] = []
        var named: [(UInt32, Int32, Int32, FlowchartNodeShape)] = []
        for (shape, names) in FlowchartNodeShape.documentedNames {
            for name in names {
                let start = Int32(bytes.count)
                bytes.append(contentsOf: name.utf8)
                named.append((hash(Array(name.utf8)[...]), start, Int32(name.utf8.count), shape))
            }
        }
        var entries = [Entry?](repeating: nil, count: 512)
        for (hash, start, length, shape) in named {
            var slot = Int(hash) & 511
            while entries[slot] != nil { slot = (slot + 1) & 511 }
            entries[slot] = Entry(hash: hash, start: start, length: length, shape: shape)
        }
        return Table(entries: entries, bytes: bytes)
    }()

    private static func hash(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in bytes { hash = (hash ^ UInt32(byte)) &* 0x0100_0193 }
        return hash
    }

    /// The documented shape the bytes name, or nil.
    static func shape(named start: UnsafePointer<UInt8>, count: Int) -> FlowchartNodeShape? {
        var hash: UInt32 = 0x811C_9DC5
        for offset in 0..<count { hash = (hash ^ UInt32(start[offset])) &* 0x0100_0193 }
        let table = table
        var slot = Int(hash) & 511
        while let entry = table.entries[slot] {
            if entry.hash == hash, Int(entry.length) == count,
               table.bytes.withUnsafeBufferPointer({ names in memcmp(names.baseAddress! + Int(entry.start), start, count) == 0 }) { return entry.shape }
            slot = (slot + 1) & 511
        }
        return nil
    }
}
