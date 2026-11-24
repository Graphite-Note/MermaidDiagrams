/**
 * File: SlowTypesJourneyPrototype.swift
 * -------------------------------------
 * Layer: Core (prototype of the slow-types redesign, not for merging as is)
 * Description: Checks the flat user journey reader against MermaidDiagramReader (the flat model turned into the
 *              package's), and times both, alternately.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

public enum SlowTypesJourneyPrototype {
    public static func run(sources: [String], rounds: Int, pairs: Int) -> String {
        var report = ""
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)
        var flat = UserJourneyFlatDiagram()
        var agreeing = 0
        for source in sources {
            let old = try? MermaidDiagramReader.read(source, limits: .standard)
            let outcome = flatRead(source, buffer: &buffer, into: &flat)
            guard case .userJourney(let oldJourney)? = old, case .read = outcome else {
                report += "not compared: \(outcome)\n"
                continue
            }
            let converted = buffer.withUnsafeBufferPointer { bytes in packageModel(flat, bytes: bytes) }
            if converted == oldJourney { agreeing += 1 } else { report += "DIFFERS:\n\(converted)\n\(oldJourney)\n" }
        }
        report += "agreeing: \(agreeing) of \(sources.count)\n"
        var oldTimes: [Double] = []
        var newTimes: [Double] = []
        var sink = 0
        for _ in 0..<pairs {
            oldTimes.append(time(rounds: rounds) {
                for source in sources { if case .userJourney(let journey)? = try? MermaidDiagramReader.read(source, limits: .standard) { sink &+= journey.tasks.count } }
            })
            newTimes.append(time(rounds: rounds) {
                for source in sources { if case .read = flatRead(source, buffer: &buffer, into: &flat) { sink &+= flat.tasks.count } }
            })
        }
        let perDiagram = { (times: [Double]) -> Double in median(times) * 1e6 / Double(rounds * sources.count) }
        report += String(format: "MermaidDiagramReader.read: %.3f µs a diagram\nflat reader (bytes copied into the reused buffer, the preprocessing scan, the keyword, the statements): %.3f µs a diagram\nspeed-up %.1fx (sink %d)\n",
                         perDiagram(oldTimes), perDiagram(newTimes), median(oldTimes) / median(newTimes), sink)
        return report
    }

    /// The source copied into the reused buffer as the preprocessing would, the passes it needs found, the keyword
    /// skipped, the statements read.
    private static func flatRead(_ source: String, buffer: inout [UInt8], into flat: inout UserJourneyFlatDiagram) -> UserJourneyFlatReader.Outcome {
        buffer.removeAll(keepingCapacity: true)
        buffer.append(contentsOf: source.utf8)
        let found = MermaidPreprocessing.bytesFound(in: buffer)
        guard found.isEmpty else { return .fullReaderNeeded }
        flat.removeAll()
        return buffer.withUnsafeBufferPointer { bytes in
            var position = 0
            while position < bytes.count, MermaidByte.isWhitespace(bytes[position]) { position += 1 }
            let keyword: [UInt8] = [106, 111, 117, 114, 110, 101, 121]
            guard position + 7 <= bytes.count, (0..<7).allSatisfy({ offset in bytes[position + offset] == keyword[offset] }) else { return .fullReaderNeeded }
            return UserJourneyFlatReader.read(bytes, from: position + 7, limits: .standard, into: &flat)
        }
    }

    private static func packageModel(_ flat: UserJourneyFlatDiagram, bytes: UnsafeBufferPointer<UInt8>) -> UserJourneyDiagram {
        func text(_ range: FlatTextRange) -> String { String(decoding: bytes[Int(range.start)..<Int(range.end)], as: UTF8.self) }
        let sections = flat.sections.map { range in DiagramLabelDecoder.label(from: text(range), form: .literal) }
        let tasks = flat.tasks.map { task in
            UserJourneyTask(label: DiagramLabelDecoder.label(from: text(task.label), form: .literal), score: task.hasScore ? task.score : nil,
                            actors: (0..<Int(task.actorMentionCount)).map { offset in text(flat.actorNames[Int(flat.actorMentions[Int(task.firstActorMention) + offset])]) },
                            sectionIndex: task.sectionIndex >= 0 ? Int(task.sectionIndex) : nil)
        }
        return UserJourneyDiagram(title: flat.title.isNone ? nil : text(flat.title), sections: sections, tasks: tasks)
    }

    private static func time(rounds: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<rounds { body() }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }
}
