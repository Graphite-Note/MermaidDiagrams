/**
 * File: FlatTextStorage.swift
 * ---------------------------
 * Layer: Prototype
 * Description: The text of one layout in one object that every block of it refers to, found through the thread's
 *              current layout so that a block made where no storage is passed appends to it; a block holds the storage
 *              and its line indices, with no list or String of its own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

/// One layout's text: an arena in an object, appended to on the layout's thread only.
final class FlatTextStorage: @unchecked Sendable {
    var arena = FlatTextArena()

    /// The storage of the layout running on this thread, if any.
    private static let currentKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    static var current: FlatTextStorage? {
        pthread_getspecific(currentKey).map { pointer in Unmanaged<FlatTextStorage>.fromOpaque(pointer).takeUnretainedValue() }
    }

    /// `body` with `storage` as this thread's current storage.
    static func withCurrent<Result>(_ storage: FlatTextStorage, _ body: () -> Result) -> Result {
        let previous = pthread_getspecific(currentKey)
        pthread_setspecific(currentKey, Unmanaged.passUnretained(storage).toOpaque())
        defer { pthread_setspecific(currentKey, previous) }
        return body()
    }
}

/// A block as the redesign keeps it: its storage and where its lines are, the block's size and place.
struct FlatStoredBlock {
    let storage: FlatTextStorage
    let record: FlatTextBlock
    var center: CGPoint = .zero
}
