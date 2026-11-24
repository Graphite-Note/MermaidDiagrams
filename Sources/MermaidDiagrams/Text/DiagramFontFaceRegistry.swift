/**
 * File: DiagramFontFaceRegistry.swift
 * -----------------------------------
 * Layer: Core
 * Description: Every Core Text font a diagram measures or draws in, made once per process with the advances of its
 *              printable ASCII by byte, kept in place and never freed, so that a measurer names its font by an index
 *              and copying it retains nothing; faces past the registry's room are kept in a small cache that is let go.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import CoreText
import Foundation

/// A font a diagram's text is measured or drawn in: the diagram's font, its size, its bold or italic, or the system's
/// monospaced font at that size.
struct CoreTextFontFaceKey: Hashable {
    let postScriptName: String?
    let size: CGFloat
    let isBold: Bool
    let isItalic: Bool
    let isMonospaced: Bool
}

/// A font as the registry keys it: the font's name as its place among the names met (0 for the system's font), its size
/// and the emphasis it is made in.
struct DiagramFontFaceName: Hashable, Sendable {
    let family: Int32
    let size: CGFloat
    let style: DiagramTextStyle
}

/// A face kept past the registry's room: its font and its advances, held as long as something measures with it.
final class DiagramOverflowFontFace: @unchecked Sendable {
    let font: CTFont
    let advances: DiagramFontAdvances

    init(font: CTFont, advances: DiagramFontAdvances) {
        self.font = font
        self.advances = advances
    }

    deinit {
        advances.byByte.deallocate()
    }
}

/// The fonts made so far in this process. Making a Core Text font and reading its advances costs more than laying out a
/// small diagram, and a font for one name is always the same, so each is made once and kept in place: a face's entry is
/// written before its index is handed out and never changed, so it is read without the lock. Past `capacity` faces (a
/// diagram's classes may set any size) a face is kept in a cache of at most `largestOverflowFaceCount`, emptied when
/// full, and found again by its name each time it measures.
final class DiagramFontFaceRegistry: @unchecked Sendable {
    static let shared = DiagramFontFaceRegistry()

    static let capacity = 1_024
    private static let largestOverflowFaceCount = 64

    private struct Entry {
        let name: DiagramFontFaceName
        let font: CTFont
        let advances: DiagramFontAdvances
    }

    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let entries: UnsafeMutablePointer<Entry>
    private var entryCount = 0
    private var indicesByName: [DiagramFontFaceName: Int32] = [:]
    private var familyNames: [String?] = [nil]
    private var familiesByName: [String: Int32] = [:]
    private var overflowFaces: [DiagramFontFaceName: DiagramOverflowFontFace] = [:]

    private init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        entries = .allocate(capacity: Self.capacity)
    }

    /// The face of `postScriptName` (nil for the system's font) at `size` in `style`, made the first time.
    func face(postScriptName: String?, size: CGFloat, style: DiagramTextStyle) -> DiagramFontFace {
        os_unfair_lock_lock(lock)
        let family = familyLocked(postScriptName)
        os_unfair_lock_unlock(lock)
        return face(DiagramFontFaceName(family: family, size: size, style: style))
    }

    /// The face of `name`, made the first time; unregistered past the registry's room.
    func face(_ name: DiagramFontFaceName) -> DiagramFontFace {
        os_unfair_lock_lock(lock)
        if let known = indicesByName[name] {
            os_unfair_lock_unlock(lock)
            return DiagramFontFace(index: DiagramFontFaceIndex(rawValue: known), name: name)
        }
        let isFull = entryCount >= Self.capacity
        let postScriptName = familyNames[Int(name.family)]
        os_unfair_lock_unlock(lock)
        guard !isFull else { return DiagramFontFace(index: .unregistered, name: name) }
        // Made outside the lock: making a font takes a while, and a face made twice by two threads is the same face.
        let font = Self.makeFont(postScriptName: postScriptName, name: name)
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        if let known = indicesByName[name] { return DiagramFontFace(index: DiagramFontFaceIndex(rawValue: known), name: name) }
        guard entryCount < Self.capacity else { return DiagramFontFace(index: .unregistered, name: name) }
        (entries + entryCount).initialize(to: Entry(name: name, font: font, advances: Self.makeAdvances(of: font)))
        let index = Int32(entryCount)
        entryCount += 1
        indicesByName[name] = index
        return DiagramFontFace(index: DiagramFontFaceIndex(rawValue: index), name: name)
    }

    /// The advances of a registered face, read without the lock.
    @inline(__always)
    func advances(_ index: DiagramFontFaceIndex) -> DiagramFontAdvances {
        entries[Int(index.rawValue)].advances
    }

    /// The Core Text font of a registered face, read without the lock.
    func coreTextFont(_ index: DiagramFontFaceIndex) -> CTFont {
        entries[Int(index.rawValue)].font
    }

    /// The font a drawing draws `key` in.
    func coreTextFont(of key: CoreTextFontFaceKey) -> CTFont {
        var style: DiagramTextStyle = []
        if key.isBold { style.insert(.bold) }
        if key.isItalic { style.insert(.italic) }
        if key.isMonospaced { style.insert(.monospaced) }
        let face = face(postScriptName: key.postScriptName, size: key.size, style: style)
        return face.index.isRegistered ? coreTextFont(face.index) : overflowFace(face.name).font
    }

    /// The PostScript name of a family, nil for the system's font.
    func postScriptName(ofFamily family: Int32) -> String? {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return familyNames[Int(family)]
    }

    /// A face past the registry's room, made again when the cache let it go.
    func overflowFace(_ name: DiagramFontFaceName) -> DiagramOverflowFontFace {
        os_unfair_lock_lock(lock)
        if let known = overflowFaces[name] {
            os_unfair_lock_unlock(lock)
            return known
        }
        let postScriptName = familyNames[Int(name.family)]
        os_unfair_lock_unlock(lock)
        let font = Self.makeFont(postScriptName: postScriptName, name: name)
        let made = DiagramOverflowFontFace(font: font, advances: Self.makeAdvances(of: font))
        os_unfair_lock_lock(lock)
        if overflowFaces.count >= Self.largestOverflowFaceCount { overflowFaces.removeAll(keepingCapacity: true) }
        overflowFaces[name] = made
        os_unfair_lock_unlock(lock)
        return made
    }

    /// The place of `postScriptName` among the names met, added the first time. Called with the lock held.
    private func familyLocked(_ postScriptName: String?) -> Int32 {
        guard let postScriptName else { return 0 }
        if let known = familiesByName[postScriptName] { return known }
        let family = Int32(familyNames.count)
        familyNames.append(postScriptName)
        familiesByName[postScriptName] = family
        return family
    }

    private static func makeFont(postScriptName: String?, name: DiagramFontFaceName) -> CTFont {
        let diagramFont = DiagramFont(postScriptName: postScriptName, size: name.size)
        let regular = name.style.contains(.monospaced) ? diagramFont.makeMonospacedCoreTextFont() : diagramFont.makeCoreTextFont()
        var traits: CTFontSymbolicTraits = []
        if name.style.contains(.bold) { traits.insert(.traitBold) }
        if name.style.contains(.italic) { traits.insert(.traitItalic) }
        return traits.isEmpty ? regular : CTFontCreateCopyWithSymbolicTraits(regular, name.size, nil, traits, traits) ?? regular
    }

    /// The font's advances by byte, those of printable ASCII from its glyphs, in a table never freed but by an overflow
    /// face; and whether they sum exactly.
    static func makeAdvances(of font: CTFont) -> DiagramFontAdvances {
        let first = DiagramFontAdvances.firstPrintableASCII
        let characters = (first...DiagramFontAdvances.lastPrintableASCII).map { byte in UniChar(byte) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var advances = [CGSize](repeating: .zero, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let table = UnsafeMutablePointer<CGFloat>.allocate(capacity: 256)
        table.initialize(repeating: 0, count: 256)
        for (offset, advance) in advances.enumerated() { table[Int(first) + offset] = advance.width }
        return DiagramFontAdvances(byByte: UnsafePointer(table), isExactlySummable: isExactlySummable(UnsafePointer(table)))
    }

    /// 2^20: an advance that is a whole number of these is a binary fraction of at most 20 bits.
    private static let exactFractionScale: CGFloat = 1_048_576
    private static let largestExactAdvance: CGFloat = 1_024

    /// Whether every advance is a binary fraction of at most 20 bits from 0 up to below 1,024 points.
    static func isExactlySummable(_ table: UnsafePointer<CGFloat>) -> Bool {
        for byte in 0..<256 {
            let advance = table[byte]
            let scaled = advance * exactFractionScale
            guard advance >= 0, advance < largestExactAdvance, scaled.rounded() == scaled else { return false }
        }
        return true
    }
}

/// A font a diagram's text is measured in, by its index in the registry and its name: copying it retains nothing.
struct DiagramFontFace: Hashable, Sendable {
    let index: DiagramFontFaceIndex
    let name: DiagramFontFaceName

    /// The same font with `style` added to its own emphasis.
    func adding(_ style: DiagramTextStyle) -> DiagramFontFace {
        guard !style.isSubset(of: name.style) else { return self }
        return DiagramFontFaceRegistry.shared.face(DiagramFontFaceName(family: name.family, size: name.size, style: name.style.union(style)))
    }

    /// The same font at `size`.
    func resized(to size: CGFloat) -> DiagramFontFace {
        DiagramFontFaceRegistry.shared.face(DiagramFontFaceName(family: name.family, size: size, style: name.style))
    }

    /// The advances it adds up for printable ASCII; nil past the registry's room, where every text is measured whole.
    var advances: DiagramFontAdvances? {
        index.isRegistered ? DiagramFontFaceRegistry.shared.advances(index) : nil
    }

    /// The width of `bytes`, valid UTF-8, on one line: printable ASCII added up from the first byte, any other text as a
    /// Core Text line lays it out, found by its bytes (`DiagramLineWidthCache`).
    func width(ofUTF8 bytes: UnsafeBufferPointer<UInt8>) -> CGFloat {
        guard let base = bytes.baseAddress else { return 0 }
        guard index.isRegistered else {
            let face = DiagramFontFaceRegistry.shared.overflowFace(name)
            return face.advances.width(of: base, from: 0, to: bytes.count) ?? DiagramLineWidthCache.layOutWidth(of: bytes, font: face.font)
        }
        if let width = DiagramFontFaceRegistry.shared.advances(index).width(of: base, from: 0, to: bytes.count) { return width }
        return DiagramLineWidthCache.shared.width(of: bytes, face: index)
    }
}
