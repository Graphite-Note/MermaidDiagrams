/**
 * File: PeleInJavaScriptCore.swift
 * --------------------------------
 * Layer: Benchmark
 * Description: Runs Pele itself in JavaScriptCore (a JSContext), from the one script scripts/pele/bundle.sh makes of its
 *              modules (pele-bundle.js): what it draws of an input, and its render timed on a case as Pele's benchmark
 *              times it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Darwin
import Foundation
import JavaScriptCore

/// Pele 1.13.0 in a JSContext. A JSContext has no canvas and no document, so Pele measures text with its table of
/// Arial's advances, as it does in Deno on the Mac (`textMeasuredWithTable`); it has no URL either, which
/// `javascriptcore-url.js` gives it. Pele's render is called as its benchmark
/// calls it (`render(source)`, an input it refuses caught and counted out).
final class PeleInJavaScriptCore {
    /// What Pele drew of an input: `<type> <width>x<height> <FNV-1a of the SVG>`, or `error <code>: <message>`, as
    /// scripts/pele/pele-bundler.ts writes it (`pele-bundle-drawings.json`).
    typealias Drawing = String

    struct ScriptFailure: Error, CustomStringConvertible {
        let description: String
    }

    let version: String
    let textMeasuredWithTable: Bool
    private let context: JSContext
    private let renderEvery: JSValue
    private let drawing: JSValue
    private var failure: String?

    init() throws {
        // Pele's runner runs with TZ=UTC (scripts/pele/run.sh, bundle.sh): a Gantt chart's dates are written in it.
        setenv("TZ", "UTC", 1)
        tzset()
        guard let context = JSContext() else { throw ScriptFailure(description: "no JSContext") }
        self.context = context
        // A JSContext has no URL, which Pele's links ask for; javascriptcore-url.js defines it for http and https.
        for name in ["javascriptcore-url", "pele-bundle"] {
            let script = String(decoding: try PeleResults.resource(named: name, extension: "js"), as: UTF8.self)
            context.evaluateScript(script, withSourceURL: URL(string: "\(name).js"))
        }
        // `renderEvery` is the body of Pele's timed case (pele-runner.ts timedCase); `drawing` what the bundler records.
        context.evaluateScript("""
            function renderEvery(sources) {
              let rendered = 0;
              for (const source of sources) {
                try { Pele.render(source); rendered++; } catch { continue; }
              }
              return rendered;
            }
            function drawing(source, now) {
              try {
                const rendered = Pele.render(source, { now });
                return [`${rendered.type} ${rendered.width}x${rendered.height}`, rendered.svg];
              } catch (error) {
                return [`error ${error.code ?? 'exception'}: ${String(error.message ?? error).slice(0, 160)}`];
              }
            }
            """)
        if let exception = context.exception { throw ScriptFailure(description: "Pele's script: \(exception)") }
        guard let pele = context.objectForKeyedSubscript("Pele"), let version = pele.objectForKeyedSubscript("version")?.toString(),
              let renderEvery = context.objectForKeyedSubscript("renderEvery"), let drawing = context.objectForKeyedSubscript("drawing") else {
            throw ScriptFailure(description: "Pele's script defined no Pele")
        }
        self.version = version
        self.textMeasuredWithTable = pele.objectForKeyedSubscript("textMeasuredWithTable")?.toBool() ?? false
        self.renderEvery = renderEvery
        self.drawing = drawing
        context.exceptionHandler = { [weak self] _, exception in self?.failure = exception?.toString() ?? "an exception" }
    }

    /// What Pele draws of `source`, placed against `now` as the bundler's record is (Gantt charts).
    func drawing(of source: String, now: Date) throws -> Drawing {
        let (summary, svg) = try drawn(source, now: now)
        return svg.map { svg in "\(summary) \(PeleResults.sourceHash(of: svg))" } ?? summary
    }

    /// The SVG Pele writes of `source`, or the error it throws as a drawing writes it.
    func svg(of source: String, now: Date) throws -> String {
        let (summary, svg) = try drawn(source, now: now)
        return svg ?? summary
    }

    private func drawn(_ source: String, now: Date) throws -> (summary: String, svg: String?) {
        let result = drawing.call(withArguments: [source, now.timeIntervalSince1970 * 1_000])
        try rethrowFailure()
        guard let parts = result?.toArray(), let summary = parts.first as? String else { throw ScriptFailure(description: "no drawing") }
        return (summary, parts.count > 1 ? parts[1] as? String : nil)
    }

    /// Pele's render timed on every input of a case, as Pele's benchmark loop times it (one run not counted, then runs
    /// until 300 ms are spent, at least 5 and at most 2,000), per diagram; with how many inputs it drew.
    func timing(of sources: [String]) throws -> (timing: BenchmarkTiming, renderedCount: Int) {
        guard let array = JSValue(object: sources, in: context) else { throw ScriptFailure(description: "the sources reached no array") }
        var renderedCount = 0
        let timing = MermaidDiagramsBenchmark.timing(perDiagramOf: sources.count) {
            renderedCount = Int(renderEvery.call(withArguments: [array])?.toInt32() ?? 0)
        }
        try rethrowFailure()
        return (timing, renderedCount)
    }

    private func rethrowFailure() throws {
        guard let failure else { return }
        self.failure = nil
        throw ScriptFailure(description: failure)
    }
}
