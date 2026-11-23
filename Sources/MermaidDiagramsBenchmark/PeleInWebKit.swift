/**
 * File: PeleInWebKit.swift
 * ------------------------
 * Layer: Benchmark
 * Description: Runs Pele itself in a WebKit page (a WKWebView) on an iPad or an iPhone, as Obsidian runs it there: its
 *              JavaScriptCore compiles to machine code, which a JSContext in an app's own process may not; what it
 *              draws of an input, and its render timed on a case.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

#if canImport(WebKit)
#if canImport(UIKit)
import UIKit
#endif
import WebKit

/// Pele 1.13.0 (`pele-bundle.js`) in a WKWebView shown in a window of the app, so that WebKit runs the page as a
/// visible one. The page's canvases give Pele no context, so it measures text with its table of Arial's advances, as in
/// Deno and in a JSContext, not with the page's fonts.
///
/// WebKit's page clock (`performance.now`) moves in steps of a millisecond, so a sample here repeats the case until
/// 50 ms have passed on it and counts the mean of those runs (a step is then at most 2 % of a sample); the samples are
/// taken as Pele's benchmark takes runs (one round not counted, then samples until the budget is spent, at least 5 and
/// at most 2,000), over 3 s instead of 300 ms.
///
/// The page runs in the device's time zone, which an app cannot change, and Pele writes a Gantt chart's dates in the
/// page's time zone: where that is not UTC, the Gantt charts are drawn otherwise than in Deno (`timeZoneOffsetMinutes`).
@MainActor
final class PeleInWebKit {
    struct PageFailure: Error, CustomStringConvertible {
        let description: String
    }

    let webView: WKWebView
    #if canImport(UIKit)
    private var window: UIWindow?
    #endif
    /// The smallest step of the page's clock seen, in microseconds.
    private(set) var clockResolutionMicroseconds = 0.0

    init() async throws {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 320), configuration: WKWebViewConfiguration())
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ scene in scene as? UIWindowScene }).first {
            let window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            controller.view.addSubview(webView)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            self.window = window
        }
        #endif
        webView.loadHTMLString("<!doctype html><meta charset=utf-8><title>Pele</title>", baseURL: nil)
        while webView.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        let bundle = String(decoding: try PeleResults.resource(named: "pele-bundle", extension: "js"), as: UTF8.self)
        _ = try await webView.evaluateJavaScript(Self.pageSetUp + "\n" + bundle + "\n" + Self.pageFunctions + "\ntrue;")
        clockResolutionMicroseconds = try await number(from: webView.callAsyncJavaScript("return clockResolution();", contentWorld: .page))
    }

    var version: String {
        get async throws { try await webView.callAsyncJavaScript("return Pele.version;", contentWorld: .page) as? String ?? "" }
    }

    var textMeasuredWithTable: Bool {
        get async throws { try await webView.callAsyncJavaScript("return Pele.textMeasuredWithTable;", contentWorld: .page) as? Bool ?? false }
    }

    /// The page's time zone's offset from UTC at `now`, in minutes, as JavaScript's `getTimezoneOffset` gives it.
    func timeZoneOffsetMinutes(at now: Date) async throws -> Double {
        let offset = try await webView.callAsyncJavaScript("return new Date(now).getTimezoneOffset();",
                                                           arguments: ["now": now.timeIntervalSince1970 * 1_000], contentWorld: .page)
        return try number(from: offset)
    }

    /// What Pele draws of each source, as `PeleInJavaScriptCore.Drawing`.
    func drawings(of sources: [String], now: Date) async throws -> [PeleInJavaScriptCore.Drawing] {
        let result = try await webView.callAsyncJavaScript("return sources.map((source) => drawing(source, now));",
                                                           arguments: ["sources": sources, "now": now.timeIntervalSince1970 * 1_000], contentWorld: .page)
        guard let drawn = result as? [[String]], drawn.count == sources.count else { throw PageFailure(description: "no drawings") }
        return drawn.map { parts in parts.count > 1 ? "\(parts[0]) \(PeleResults.sourceHash(of: parts[1]))" : parts.first ?? "" }
    }

    /// Pele's render timed on every input of a case, per diagram.
    func timing(of sources: [String]) async throws -> BenchmarkTiming {
        let result = try await webView.callAsyncJavaScript("return timeCase(sources, 3000, 50);", arguments: ["sources": sources], contentWorld: .page)
        guard let timed = result as? [String: Any] else { throw PageFailure(description: "no timing") }
        let median = try number(from: timed["median"])
        let percentile99 = try number(from: timed["percentile99"])
        let runs = try number(from: timed["samples"])
        let diagramCount = Double(max(sources.count, 1))
        return BenchmarkTiming(medianMicroseconds: median * 1_000 / diagramCount, percentile99Microseconds: percentile99 * 1_000 / diagramCount,
                               runCount: Int(runs))
    }

    func close() {
        webView.removeFromSuperview()
        #if canImport(UIKit)
        window?.isHidden = true
        window = nil
        #endif
    }

    private func number(from value: Any?) throws -> Double {
        guard let number = value as? NSNumber else { throw PageFailure(description: "not a number: \(String(describing: value))") }
        return number.doubleValue
    }

    /// Before Pele's script: no canvas context, so Pele measures with its table.
    private static let pageSetUp = """
        HTMLCanvasElement.prototype.getContext = function () { return null; };
        if (typeof OffscreenCanvas !== 'undefined') OffscreenCanvas.prototype.getContext = function () { return null; };
        """

    /// What the page answers: the drawing the bundler records, the clock's step, and a case timed.
    private static let pageFunctions = """
        function drawing(source, now) {
          try {
            const rendered = Pele.render(source, { now });
            return [`${rendered.type} ${rendered.width}x${rendered.height}`, rendered.svg];
          } catch (error) {
            return [`error ${error.code ?? 'exception'}: ${String(error.message ?? error).slice(0, 160)}`];
          }
        }
        function clockResolution() {
          let smallest = Infinity;
          for (let round = 0; round < 50; round++) {
            const start = performance.now();
            let now = start;
            while (now === start) now = performance.now();
            smallest = Math.min(smallest, now - start);
          }
          return smallest * 1000;
        }
        function timeCase(sources, budgetMilliseconds, sampleMilliseconds) {
          const runAll = () => {
            for (const source of sources) {
              try { Pele.render(source); } catch { continue; }
            }
          };
          runAll();
          let repetitions = 1;
          for (;;) {
            const start = performance.now();
            for (let run = 0; run < repetitions; run++) runAll();
            if (performance.now() - start >= sampleMilliseconds || repetitions >= 65536) break;
            repetitions *= 2;
          }
          const samples = [];
          let budget = budgetMilliseconds;
          while (budget > 0 || samples.length < 5) {
            const start = performance.now();
            for (let run = 0; run < repetitions; run++) runAll();
            const elapsed = performance.now() - start;
            samples.push(elapsed / repetitions);
            budget -= elapsed;
            if (samples.length >= 2000) break;
          }
          samples.sort((first, second) => first - second);
          const percentile99 = samples[Math.min(samples.length - 1, Math.ceil(samples.length * 0.99) - 1)];
          return { median: samples[samples.length >> 1], percentile99, samples: samples.length, repetitions };
        }
        """
}
#endif
