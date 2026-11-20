/**
 * File: UseCasePeleLayoutTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Use case diagrams laid out in Pele's own numbers: the page, each node's center and each line's ends that
 *              Pele's renderUsecase draws for Mermaid's documentation examples and a few more, across and turned to
 *              run down, with text half its size wide, so that no measurement, end or loop moves unnoticed.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class UseCasePeleLayoutTests: XCTestCase {
    /// What Pele draws for `source`: written down from its SVG, rendered with a measurer giving each character half the
    /// size's width, and again with a width of 10 (`maxWidth`), which turns a diagram that runs across to run down.
    private struct PeleLayout {
        let source: String
        let size: CGSize
        let centers: [String: CGPoint]
        /// Each line's first and last points, in the order drawn.
        let ends: [[CGFloat]]
        let narrowSize: CGSize?
        let narrowCenters: [String: CGPoint]
        let narrowEnds: [[CGFloat]]
    }

    private static let cases: [PeleLayout] = [
        PeleLayout(source: "usecase-beta\ndirection LR\nactor Customer(\"Customer\")\nsystemBoundary \"Order system\"\n  Checkout(\"Place order\")\nend\nCustomer --> Checkout\n",
                   size: CGSize(width: 344, height: 128), centers: ["Checkout": CGPoint(x: 250, y: 74), "Customer": CGPoint(x: 40, y: 74)],
                   ends: [[63, 59, 177, 74]],
                   narrowSize: CGSize(width: 188, height: 310), narrowCenters: ["Checkout": CGPoint(x: 94, y: 256), "Customer": CGPoint(x: 94, y: 53)],
                   narrowEnds: [[94, 100, 94, 223]]),
        PeleLayout(source: "usecase-beta\nsystemBoundary sb1[\"Payment service\"]@{ type: package }:::system\n  actor Clerk(\"Payment clerk\")\n  Authorize(\"Authorize payment\")\n  Receipt[Create receipt]\nend\nClerk --> Authorize\nAuthorize --> Receipt\nclassDef system stroke:#4b4b7a\n",
                   size: CGSize(width: 628, height: 178), centers: ["Authorize": CGPoint(x: 294, y: 105), "Clerk": CGPoint(x: 80, y: 105), "Receipt": CGPoint(x: 528, y: 105)],
                   ends: [[103, 90, 197, 105], [384, 105, 449, 105]],
                   narrowSize: CGSize(width: 236, height: 422), narrowCenters: ["Authorize": CGPoint(x: 118, y: 248), "Clerk": CGPoint(x: 118, y: 105), "Receipt": CGPoint(x: 118, y: 370)],
                   narrowEnds: [[118, 152, 118, 215], [118, 274, 118, 339]]),
        PeleLayout(source: "usecase-beta\nactor User\nLogin\nUser -- \"include account details\" --> Login\n",
                   size: CGSize(width: 389, height: 106), centers: ["Login": CGPoint(x: 337, y: 53), "User": CGPoint(x: 28, y: 53)],
                   ends: [[51, 38, 286, 53]],
                   narrowSize: CGSize(width: 189, height: 255), narrowCenters: ["Login": CGPoint(x: 94.5, y: 221), "User": CGPoint(x: 94.5, y: 53)],
                   narrowEnds: [[94.5, 100, 94.5, 188]]),
        PeleLayout(source: "usecase-beta\nactor Admin\nactor Person\nCheckout\nPayment\nApplyCoupon\nAdmin --|> Person\nCheckout ..> : include Payment\nApplyCoupon ..> : extend Checkout\nApplyCoupon --|> Checkout\n",
                   size: CGSize(width: 643, height: 190), centers: ["Admin": CGPoint(x: 74, y: 53), "ApplyCoupon": CGPoint(x: 74, y: 156), "Checkout": CGPoint(x: 334, y: 156), "Payment": CGPoint(x: 585, y: 156), "Person": CGPoint(x: 334, y: 53)],
                   ends: [[97, 38, 299, 38], [388, 156, 528, 156], [137.56, 149, 274.99, 149], [137.56, 163, 269.99, 163]],
                   narrowSize: CGSize(width: 224, height: 442), narrowCenters: ["Admin": CGPoint(x: 32, y: 53), "ApplyCoupon": CGPoint(x: 150, y: 53), "Checkout": CGPoint(x: 150, y: 240), "Payment": CGPoint(x: 150, y: 408), "Person": CGPoint(x: 32, y: 240)],
                   narrowEnds: [[32, 100, 32, 181], [150, 266, 150, 375], [143, 78.85, 143, 207.22], [157, 78.85, 157, 202.22]]),
        PeleLayout(source: "usecase-beta\nnote for Login \"`Requires an **active session**`\"\nnote for User \"Starts the workflow\"\nactor User\nLogin(\"Sign in\")\nUser --> Login\n",
                   size: CGSize(width: 571, height: 192), centers: ["Login": CGPoint(x: 513, y: 105), "User": CGPoint(x: 315, y: 53), "note-0": CGPoint(x: 315, y: 157), "note-1": CGPoint(x: 87.5, y: 53)],
                   ends: [[338, 38, 457.85, 98], [391, 157, 464.85, 112], [167, 53, 292, 38]],
                   narrowSize: CGSize(width: 300, height: 341), narrowCenters: ["Login": CGPoint(x: 151.5, y: 307), "User": CGPoint(x: 87.5, y: 164), "note-0": CGPoint(x: 215.5, y: 164), "note-1": CGPoint(x: 87.5, y: 27.5)],
                   narrowEnds: [[87.5, 211, 144.5, 274.26], [215.5, 191, 158.5, 281.26], [87.5, 47, 87.5, 117]]),
        PeleLayout(source: "usecase-beta\nInspect(\"Inspect payload\")\njson Payload@{\n  \"2\": \"second in source\",\n  \"1\": \"first after 2\",\n  \"enabled\": true,\n  \"count\": 3,\n  \"missing\": null,\n  \"colors\": [\"Red\", \"Green\"],\n  \"address\": { \"city\": \"Oslo\" },\n  \"items\": [{ \"name\": \"Book\" }],\n  \"emptyObject\": {},\n  \"emptyArray\": []\n}:::data\nInspect --> Payload\nclassDef data stroke:#3572a5\nstyle Payload stroke-width:2px\n",
                   size: CGSize(width: 495, height: 367), centers: ["Inspect": CGPoint(x: 90, y: 183.5), "Payload": CGPoint(x: 365.5, y: 183.5)],
                   ends: [[172, 183.5, 237, 183.5]],
                   narrowSize: CGSize(width: 259, height: 491), narrowCenters: ["Inspect": CGPoint(x: 129.5, y: 34), "Payload": CGPoint(x: 129.5, y: 307.5)],
                   narrowEnds: [[129.5, 60, 129.5, 125]]),
        PeleLayout(source: "usecase-beta\nactor Customer:::external\nCheckout(\"Checkout\"):::critical\nsystemBoundary Account\n  Profile[Edit profile]\nend\njson Session@{ \"active\": true }:::data\nCustomer --> Checkout\nCheckout --> Profile\nProfile --> Session\nclassDef default stroke:#7f8ea3\nclassDef external,critical stroke-width:3px\nclass Customer,Checkout external,critical\nclass Account,Session data\nstyle Checkout stroke:#c33,stroke-width:4px\nstyle Account stroke:#536878\n",
                   size: CGSize(width: 722, height: 125), centers: ["Checkout": CGPoint(x: 198, y: 72), "Customer": CGPoint(x: 40, y: 72), "Profile": CGPoint(x: 428, y: 72), "Session": CGPoint(x: 659, y: 72)],
                   ends: [[63, 57, 137, 72], [252, 72, 357, 72], [492, 72, 597, 72]],
                   narrowSize: CGSize(width: 184, height: 583), narrowCenters: ["Checkout": CGPoint(x: 92, y: 196), "Customer": CGPoint(x: 92, y: 53), "Profile": CGPoint(x: 92, y: 378), "Session": CGPoint(x: 92, y: 544.5)],
                   narrowEnds: [[92, 100, 92, 163], [92, 222, 92, 347], [92, 402, 92, 507]]),
        PeleLayout(source: "usecase-beta\nactor Customer\nReset(\"`Reset\npassword`\")\nRefund(\"Refund #40;partial#41;\")\nCustomer --> Reset\nCustomer --> Refund\n",
                   size: CGSize(width: 324, height: 170), centers: ["Customer": CGPoint(x: 40, y: 89.5), "Refund": CGPoint(x: 230, y: 136), "Reset": CGPoint(x: 230, y: 43)],
                   ends: [[63, 67.5, 169, 43], [63, 81.5, 137, 136]],
                   narrowSize: nil, narrowCenters: [:],
                   narrowEnds: []),
        PeleLayout(source: "usecase-beta\nactor A\nA --> U\nU -- again --> U\nU --> U\nA -- note it --> A",
                   size: CGSize(width: 216, height: 230), centers: ["A": CGPoint(x: 28, y: 115), "U": CGPoint(x: 164, y: 115)],
                   ends: [[51, 100, 113, 115], [156, 140.57, 174.06, 147.26], [150, 139.65, 180.67, 146.12], [20, 162, 38.06, 168.69]],
                   narrowSize: nil, narrowCenters: [:],
                   narrowEnds: []),
        PeleLayout(source: "usecase-beta\ndirection TB\nactor A\nA --> U\nU -- again --> U\nU --> U",
                   size: CGSize(width: 302, height: 230), centers: ["A": CGPoint(x: 151, y: 53), "U": CGPoint(x: 151, y: 196)],
                   ends: [[151, 100, 151, 163], [192.87, 188, 199.56, 206.06], [188.08, 182, 194.55, 212.67]],
                   narrowSize: nil, narrowCenters: [:],
                   narrowEnds: []),
    ]

    func testTheLayoutIsPelesAcrossAndTurnedDown() throws {
        for expected in Self.cases {
            let diagram = try UseCaseReading.diagram(expected.source)
            var measurers = UseCaseReading.uniformMeasurers
            let across = try UseCaseLayoutEngine.layout(diagram, measurers: &measurers, limits: .standard)
            check(across, size: expected.size, centers: expected.centers, ends: expected.ends, expected.source)
            // Pele keeps a diagram across when it runs down already, or when down is no narrower.
            let down = try diagram.turnedToRunDown.map { turned in try UseCaseLayoutEngine.layout(turned, measurers: &measurers, limits: .standard) }
            guard let narrowSize = expected.narrowSize, let down else {
                XCTAssertFalse(down.map { down in down.size.width < across.size.width } ?? false, expected.source)
                continue
            }
            check(down, size: narrowSize, centers: expected.narrowCenters, ends: expected.narrowEnds, "turned: " + expected.source)
        }
    }

    private func check(_ layout: UseCaseLayout, size: CGSize, centers: [String: CGPoint], ends: [[CGFloat]], _ message: String) {
        XCTAssertEqual(layout.size, size, message)
        for (identifier, center) in centers {
            XCTAssertEqual(layout.node(identifier)?.center.x ?? .nan, center.x, accuracy: 0.01, identifier + ": " + message)
            XCTAssertEqual(layout.node(identifier)?.center.y ?? .nan, center.y, accuracy: 0.01, identifier + ": " + message)
        }
        XCTAssertEqual(layout.edges.count, ends.count, message)
        for (edge, expected) in zip(layout.edges, ends) {
            let last: CGPoint = switch edge.path.segments.last {
            case .line(let end)?: end
            case .curve(let end, _, _)?: end
            case nil: edge.path.start
            }
            let drawn = [edge.path.start.x, edge.path.start.y, last.x, last.y]
            for (value, wanted) in zip(drawn, expected) { XCTAssertEqual(value, wanted, accuracy: 0.01, edge.identifier + ": " + message) }
        }
    }
}
