// swift-tools-version: 6.2
/**
 * File: Package.swift
 * -------------------
 * Layer: Build
 * Description: The standalone package that reads, lays out and draws Mermaid diagrams, with its benchmark and
 *              tests; a warning in any of its targets fails the build.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 23/11/2026
 */
import PackageDescription

// Reads Mermaid diagram text, lays the diagram out and draws it into a Core Graphics context, in Pele's visual style.
// Foundation, CoreGraphics and CoreText only: it knows no app, and reads and writes no file.
let package = Package(
    name: "MermaidDiagrams",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "MermaidDiagrams", targets: ["MermaidDiagrams"])
    ],
    targets: [
        .target(name: "MermaidDiagrams"),
        // Times reading, layout and drawing on the inputs of Pele's benchmark (`swift run -c release MermaidDiagramsBenchmark`);
        // its resources are Mermaid's documentation examples as Pele's corpus collects them, Pele's own records and Pele
        // itself as one script (BenchmarkResources/README.md).
        .executableTarget(name: "MermaidDiagramsBenchmark", dependencies: ["MermaidDiagrams"], resources: [.copy("BenchmarkResources")]),
        .executableTarget(name: "SlowTypesPrototype", dependencies: ["MermaidDiagrams"]),
        .testTarget(name: "MermaidDiagramsTests", dependencies: ["MermaidDiagrams", "MermaidDiagramsBenchmark"]),
        // The comparison with Pele run in JavaScriptCore on an iPad or an iPhone (`xcodebuild test`), skipped unless
        // MERMAID_DIAGRAMS_DEVICE_BENCHMARK is set; it imports the benchmark without testability, so it builds in Release.
        .testTarget(name: "MermaidDiagramsDeviceBenchmarkTests", dependencies: ["MermaidDiagramsBenchmark"])
    ]
)

// The package builds with no warning: a warning in any of its
// targets fails the build. Dependencies are other packages and keep their own settings.
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
