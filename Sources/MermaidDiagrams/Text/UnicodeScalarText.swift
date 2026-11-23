/**
 * File: UnicodeScalarText.swift
 * -----------------------------
 * Layer: Core
 * Description: Makes a string from Unicode scalars, or from UTF-16 code units, by writing their UTF-8 into the string
 *              at once, which the readers and the text wrapping do for every piece of text they cut out of an array.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A string from scalars. `String(String.UnicodeScalarView(scalars))` and appending scalars to a string one by one go
/// through the standard library's unspecialized path, scalar by scalar, which cost more than the YAML reader's or the
/// wrapping's own work; encoding to UTF-8 and decoding the bytes once gives the same string.
enum UnicodeScalarText {
    static func string<Scalars: Collection>(_ scalars: Scalars) -> String where Scalars.Element == Unicode.Scalar {
        var byteCount = 0
        for scalar in scalars { byteCount += UTF8.width(scalar) }
        return String(unsafeUninitializedCapacity: byteCount) { buffer in
            var index = 0
            for scalar in scalars {
                if scalar.value < 0x80 {
                    buffer[index] = UInt8(truncatingIfNeeded: scalar.value)
                    index += 1
                } else if let encoded = UTF8.encode(scalar) {
                    for byte in encoded {
                        buffer[index] = byte
                        index += 1
                    }
                }
            }
            return index
        }
    }

    /// A string from UTF-16 code units: written straight into the string when they are all ASCII, else decoded, an
    /// unpaired surrogate becoming U+FFFD as `String(decoding:as:)` makes it.
    static func string(utf16 units: ArraySlice<UInt16>) -> String {
        guard units.allSatisfy({ unit in unit < 0x80 }) else { return String(decoding: units, as: UTF16.self) }
        return String(unsafeUninitializedCapacity: units.count) { buffer in
            var index = 0
            for unit in units {
                buffer[index] = UInt8(truncatingIfNeeded: unit)
                index += 1
            }
            return index
        }
    }
}
