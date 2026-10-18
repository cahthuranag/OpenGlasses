import XCTest
@testable import OpenGlasses

/// Plan JD P0 — the pure reading of a native tool's JSON schema into the shape Apple's on-device
/// model takes, the condensing that keeps it inside a 4k window, the argument read-back, and the
/// carry policy for a full window. No Foundation Models import: every case runs headless.
final class AppleToolSchemaTests: XCTestCase {

    // MARK: - Conversion

    func testObjectPropertiesAreSortedAndRequiredDrivesOptionality() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "zeta": ["type": "string", "description": "Last."],
                "alpha": ["type": "integer", "description": "First."],
            ],
            "required": ["alpha"],
        ]
        guard case .object(let name, _, let properties) = AppleToolSchema.root(toolName: "demo", parameters: schema) else {
            return XCTFail("root is always an object")
        }
        XCTAssertEqual(name, "demo")
        XCTAssertEqual(properties.map(\.name), ["alpha", "zeta"], "stable order between launches")
        XCTAssertEqual(properties[0].isOptional, false)
        XCTAssertEqual(properties[0].node, .integer)
        XCTAssertEqual(properties[1].isOptional, true)
        XCTAssertEqual(properties[1].node, .string(choices: nil))
    }

    func testEveryJSONTypeMapsAndUnknownReadsAsString() {
        let limits = AppleToolSchema.Limits.standard
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "number"], path: "p", limits: limits), .number)
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "boolean"], path: "p", limits: limits), .boolean)
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "INTEGER"], path: "p", limits: limits), .integer)
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "mystery"], path: "p", limits: limits), .string(choices: nil))
        XCTAssertEqual(AppleToolSchema.node(from: [:], path: "p", limits: limits), .string(choices: nil))
    }

    func testEnumBecomesChoicesUnlessTooLong() {
        let limits = AppleToolSchema.Limits(toolDescription: 100, propertyDescription: 100, maxChoices: 3)
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "string", "enum": ["a", "b"]], path: "p", limits: limits),
                       .string(choices: ["a", "b"]))
        let long: [String: Any] = ["type": "object",
                                   "properties": ["mode": ["type": "string", "description": "Pick one.",
                                                           "enum": ["a", "b", "c", "d"]]]]
        guard case .object(_, _, let properties) = AppleToolSchema.node(from: long, path: "t", limits: limits) else {
            return XCTFail()
        }
        XCTAssertEqual(properties[0].node, .string(choices: nil), "four choices exceed the cap of three")
        XCTAssertEqual(properties[0].description, "Pick one. One of: a, b, c, d",
                       "the choices still reach the model, as text")
    }

    func testArraysTakeTheirItemTypeAndDefaultToStrings() {
        let limits = AppleToolSchema.Limits.standard
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "array", "items": ["type": "integer"]], path: "p", limits: limits),
                       .array(.integer))
        XCTAssertEqual(AppleToolSchema.node(from: ["type": "array"], path: "p", limits: limits),
                       .array(.string(choices: nil)))
    }

    func testNestedObjectsAreNamedByPath() {
        let schema: [String: Any] = [
            "type": "object",
            "properties": ["inner": ["type": "object", "properties": ["x": ["type": "number"]]]],
        ]
        guard case .object(_, _, let properties) = AppleToolSchema.root(toolName: "tool", parameters: schema),
              case .object(let innerName, _, let innerProperties) = properties[0].node else {
            return XCTFail()
        }
        XCTAssertEqual(innerName, "tool_inner")
        XCTAssertEqual(innerProperties.map(\.name), ["x"])
    }

    func testRootWithoutObjectSchemaIsAnEmptyObject() {
        XCTAssertEqual(AppleToolSchema.root(toolName: "bare", parameters: [:]),
                       .object(name: "bare", description: nil, properties: []))
        XCTAssertEqual(AppleToolSchema.root(toolName: "odd", parameters: ["type": "string"]),
                       .object(name: "odd", description: nil, properties: []))
    }

    // MARK: - Condensing

    func testShortTextSurvivesWithWhitespaceCollapsed() {
        XCTAssertEqual(AppleToolSchema.condense("  Start,\n  pause   or end. ", limit: 100), "Start, pause or end.")
    }

    func testLongTextCutsOnASentenceBoundary() {
        let text = "Start a job. Pause the job when the technician steps away. End it when they finish."
        XCTAssertEqual(AppleToolSchema.condense(text, limit: 60),
                       "Start a job. Pause the job when the technician steps away.")
    }

    func testCutFallsBackToAWordBoundaryWithEllipsis() {
        let text = "Records the technician's exact job or work-order number without any normalisation whatsoever"
        let cut = AppleToolSchema.condense(text, limit: 40)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertLessThanOrEqual(cut.count, 41)
        XCTAssertFalse(cut.dropLast().hasSuffix(" "), "no dangling space before the ellipsis")
        XCTAssertTrue(text.hasPrefix(String(cut.dropLast())))
    }

    func testADecimalPointIsNotASentenceEnd() {
        let text = "Target 1.5 bar then hold. Then vent the line slowly and record the reading."
        // A cut landing just after "1.5" must not treat the point as a boundary.
        let cut = AppleToolSchema.condense(text, limit: 30)
        XCTAssertNotEqual(cut, "Target 1.")
        XCTAssertEqual(cut, "Target 1.5 bar then hold.")
    }

    func testToolDescriptionUsesTheToolLimit() {
        let limits = AppleToolSchema.Limits(toolDescription: 12, propertyDescription: 100, maxChoices: 3)
        XCTAssertEqual(AppleToolSchema.toolDescription("One two. Three four five.", limits: limits), "One two.")
    }

    // MARK: - Size

    func testEstimateGrowsWithProperties() {
        let small = AppleToolSchema.root(toolName: "t", parameters: ["type": "object"])
        let large = AppleToolSchema.root(toolName: "t", parameters: [
            "type": "object",
            "properties": ["a": ["type": "string", "description": "A long enough description."],
                           "b": ["type": "string", "enum": ["one", "two", "three"]]],
        ])
        let smallTokens = AppleToolSchema.estimatedTokens(name: "t", description: "Does a thing.", root: small)
        let largeTokens = AppleToolSchema.estimatedTokens(name: "t", description: "Does a thing.", root: large)
        XCTAssertGreaterThan(smallTokens, 0)
        XCTAssertGreaterThan(largeTokens, smallTokens)
    }

    // MARK: - Arguments

    func testArgumentsDropExplicitNullsAndKeepTheRest() {
        let args = AppleToolArguments.dictionary(fromJSON: #"{"action":"start","vault":null,"count":2,"tags":["a",null]}"#)
        XCTAssertEqual(args["action"] as? String, "start")
        XCTAssertNil(args["vault"], "an optional the model left out is absent, not NSNull")
        XCTAssertEqual(args["count"] as? Int, 2)
        XCTAssertEqual((args["tags"] as? [Any])?.count, 2, "only top-level nulls are the omitted-optional shape")
    }

    func testNonObjectArgumentsReadAsNone() {
        XCTAssertTrue(AppleToolArguments.dictionary(fromJSON: "[1,2]").isEmpty)
        XCTAssertTrue(AppleToolArguments.dictionary(fromJSON: "not json").isEmpty)
        XCTAssertTrue(AppleToolArguments.dictionary(fromJSON: "").isEmpty)
    }

    // MARK: - Carry policy

    func testCarryShrinksThenStops() {
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(AppleSessionPolicy.carriedEntryLimit), 4)
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(4), 0)
        XCTAssertEqual(AppleSessionPolicy.carryAfterOverflow(3), 0)
        XCTAssertNil(AppleSessionPolicy.carryAfterOverflow(0), "the prompt alone does not fit — no retry can fix it")
        XCTAssertNil(AppleSessionPolicy.carryAfterOverflow(-1))
    }
}
