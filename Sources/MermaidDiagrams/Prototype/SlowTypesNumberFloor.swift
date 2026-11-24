/**
 * File: SlowTypesNumberFloor.swift
 * --------------------------------
 * Layer: Core (prototype of the slow-types redesign, not for merging as is)
 * Description: Times the SVG writer's own number writing on the numbers of a document, to bound what any SVG of
 *              that many numbers costs.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
import Foundation

public enum SlowTypesNumberFloor {
    /// Writes `values` into one buffer `rounds` times; nanoseconds a number, median of `pairs`.
    public static func run(values: [Double], byteCount: Int, rounds: Int, pairs: Int) -> String {
        var times: [Double] = []
        var copyTimes: [Double] = []
        let document = [UInt8](repeating: 65, count: byteCount)
        var sink = 0
        for _ in 0..<pairs {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<rounds {
                var buffer = DiagramSVGBuffer(reservingCapacity: byteCount)
                for value in values {
                    buffer.appendNumber(CGFloat(value))
                    buffer.append(byte: 32)
                }
                sink &+= buffer.count
            }
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(rounds))
            let copyStart = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<rounds {
                let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
                document.withUnsafeBufferPointer { source in destination.update(from: source.baseAddress!, count: byteCount) }
                sink &+= Int(destination[byteCount / 2])
                destination.deallocate()
            }
            copyTimes.append(Double(DispatchTime.now().uptimeNanoseconds - copyStart) / Double(rounds))
        }
        let median = times.sorted()[times.count / 2]
        let copyMedian = copyTimes.sorted()[copyTimes.count / 2]
        return String(format: "%d numbers: %.2f µs a document, %.1f ns a number; copying %d bytes once: %.2f µs (sink %d)", values.count, median / 1000,
                      median / Double(values.count), byteCount, copyMedian / 1000, sink)
    }
}
