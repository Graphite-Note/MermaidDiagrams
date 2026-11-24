/**
 * File: DiagramTextStorage.swift
 * ------------------------------
 * Layer: Core
 * Description: The bytes and records of decoded labels and measured text in one allocation that is written once and
 *              then only read, shared by every label and block written on one thread until it is full, so that a label
 *              or a block costs no allocation of its own and copies as one reference.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import Foundation

/// A region of label and text bytes and their records. Bytes are written from its start up, records (lines, runs,
/// spans: small values aligned to eight bytes) from its end down, and what is written is never changed or moved, so a
/// label or a block that refers to it reads it from any thread without a lock. Only the thread whose current storage it
/// is writes to it (`DiagramTextThreadState`); once full it is no thread's, and lives as long as a label or a block
/// refers to it. Offsets are bytes from the region's start.
final class DiagramTextStorage: @unchecked Sendable {
    /// The size of a storage a thread writes into; a label or a block that needs more than a quarter of it gets a
    /// storage of its own, as large as it needs.
    static let standardByteCount = 16 * 1024
    static let recordAlignment = 8

    let base: UnsafeMutableRawPointer
    let byteCapacity: Int
    /// The end of the bytes written, and the start of the records written: the room left lies between.
    private(set) var byteEnd = 0
    private(set) var recordStart: Int

    init(byteCapacity: Int) {
        let capacity = (max(byteCapacity, Self.recordAlignment) + Self.recordAlignment - 1) / Self.recordAlignment * Self.recordAlignment
        base = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: Self.recordAlignment)
        self.byteCapacity = capacity
        recordStart = capacity
    }

    deinit {
        base.deallocate()
    }

    /// The room left, in bytes.
    var roomLeft: Int { recordStart - byteEnd }

    /// Whether `byteCount` bytes and `recordByteCount` bytes of records, each record's place aligned, fit.
    func hasRoom(forBytes byteCount: Int, recordBytes recordByteCount: Int) -> Bool {
        let recordStart = (self.recordStart - recordByteCount) & ~(Self.recordAlignment - 1)
        return recordStart >= byteEnd + byteCount
    }

    // MARK: Reading, from any thread

    /// The bytes from `start` to `end`.
    @inline(__always)
    func bytes(from start: Int32, to end: Int32) -> UnsafeBufferPointer<UInt8> {
        UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self) + Int(start), count: Int(end - start))
    }

    @inline(__always)
    var bytePointer: UnsafePointer<UInt8> {
        UnsafePointer(base.assumingMemoryBound(to: UInt8.self))
    }

    /// Record `index` of the run of records of `Record` that starts at `offset`.
    @inline(__always)
    func record<Record: BitwiseCopyable>(at offset: Int32, index: Int = 0, as type: Record.Type = Record.self) -> Record {
        base.load(fromByteOffset: Int(offset) + index * MemoryLayout<Record>.stride, as: Record.self)
    }

    // MARK: Writing, by the owning thread only

    /// Writes `bytes` after the bytes written; the caller checked the room. Returns where they start.
    func append(_ bytes: UnsafeBufferPointer<UInt8>) -> Int32 {
        let start = byteEnd
        if let source = bytes.baseAddress, !bytes.isEmpty { (base + start).copyMemory(from: source, byteCount: bytes.count) }
        byteEnd += bytes.count
        return Int32(start)
    }

    /// Room for `count` records of `Record` below the records written, the caller having checked it; returns their offset.
    func reserveRecords<Record: BitwiseCopyable>(count: Int, of type: Record.Type) -> Int32 {
        recordStart = (recordStart - count * MemoryLayout<Record>.stride) & ~(Self.recordAlignment - 1)
        precondition(recordStart >= byteEnd, "the room was checked")
        return Int32(recordStart)
    }

    /// Writes `record` as record `index` of the run at `offset`.
    @inline(__always)
    func setRecord<Record: BitwiseCopyable>(_ record: Record, at offset: Int32, index: Int) {
        base.storeBytes(of: record, toByteOffset: Int(offset) + index * MemoryLayout<Record>.stride, as: Record.self)
    }

    /// The bytes of a record, aligned as it is placed.
    static func recordByteCount<Record: BitwiseCopyable>(_ count: Int, of type: Record.Type) -> Int {
        count * MemoryLayout<Record>.stride + recordAlignment
    }
}

/// What a thread writes text with: its current storage, and the working lists measuring and decoding use, kept for the
/// thread's life so that they grow once. Found through a thread-specific key; the thread's exit lets them go.
final class DiagramTextThreadState {
    private(set) var storage = DiagramTextStorage(byteCapacity: DiagramTextStorage.standardByteCount)
    /// The measuring scratch, and whether it is in use (a measurer measuring a block while another is measured gets one
    /// of its own).
    var measuring = DiagramTextMeasuringScratch()
    var isMeasuring = false
    /// The decoding lists of labels with markup, and whether they are in use.
    var decoder = DiagramLabelByteDecoder()
    var isDecoding = false

    deinit {
        measuring.free()
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { state in
            Unmanaged<DiagramTextThreadState>.fromOpaque(state).release()
        }
        return key
    }()

    /// This thread's state, made the first time.
    static var current: DiagramTextThreadState {
        if let state = pthread_getspecific(key) { return Unmanaged<DiagramTextThreadState>.fromOpaque(state).takeUnretainedValue() }
        let state = DiagramTextThreadState()
        pthread_setspecific(key, Unmanaged.passRetained(state).toOpaque())
        return state
    }

    /// A storage of this thread with room for `byteCount` bytes and `recordByteCount` bytes of records: the current one,
    /// or a new current one when it is full, or one of their own for text larger than a quarter of a storage.
    func storage(forBytes byteCount: Int, recordBytes recordByteCount: Int) -> DiagramTextStorage {
        if storage.hasRoom(forBytes: byteCount, recordBytes: recordByteCount) { return storage }
        let needed = byteCount + recordByteCount + DiagramTextStorage.recordAlignment
        guard needed <= DiagramTextStorage.standardByteCount / 4 else { return DiagramTextStorage(byteCapacity: needed) }
        storage = DiagramTextStorage(byteCapacity: DiagramTextStorage.standardByteCount)
        return storage
    }
}
