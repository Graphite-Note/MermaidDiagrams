/**
 * File: UnicodeScalarText.swift
 * -----------------------------
 * Layer: Core
 * Description: Makes a string from Unicode scalars by encoding them to UTF-8 at once, which the readers and the text
 *              wrapping do for every piece of text they cut out of an array of scalars.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// A string from scalars. `String(String.UnicodeScalarView(scalars))` and appending scalars to a string one by one go
/// through the standard library's unspecialized path, scalar by scalar, which cost more than the YAML reader's or the
/// wrapping's own work; encoding to UTF-8 and decoding the bytes once gives the same string.
enum UnicodeScalarText {
    static func string<Scalars: Sequence>(_ scalars: Scalars) -> String where Scalars.Element == Unicode.Scalar {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.underestimatedCount)
        for scalar in scalars {
            if scalar.value < 0x80 {
                bytes.append(UInt8(truncatingIfNeeded: scalar.value))
            } else if let encoded = UTF8.encode(scalar) {
                bytes.append(contentsOf: encoded)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
