import XCTest
@testable import OpenGlasses

/// The on-device model's own instructions fit its window: everything that is not a tool
/// definition stays under `AppleOnDeviceInstructions.characterBudget`, the parts the support
/// report lists add up to what was sent, and an open job travels as a compact summary — never as
/// manual passages.
@MainActor
final class AppleOnDeviceInstructionsTests: XCTestCase {

    private func inputs(persona: String = Config.defaultSystemPrompt(device: .glasses),
                        location: String? = "Christchurch, Canterbury, New Zealand",
                        memory: String? = nil, weather: String? = nil,
                        job: AppleOnDeviceInstructions.JobSummary? = nil,
                        fieldAssistActive: Bool = false) -> AppleOnDeviceInstructions.Inputs {
        .init(persona: persona,
              appGuide: SystemPromptBuilder.onDeviceAppGuide(appName: "OpenGlasses"),
              safetyPolicy: PromptInjectionPolicy.onDeviceSystemPromptPolicy,
              dateTime: LLMService.currentDateTimeLine(now: Date(timeIntervalSince1970: 1_800_000_000),
                                                       timeZone: TimeZone(identifier: "Pacific/Auckland")!),
              location: location, memory: memory, weather: weather, job: job,
              fieldAssistActive: fieldAssistActive, modelSettingsPath: "Settings > Intelligence",
              speakerLine: "The person speaking to you is the user. Address them directly as \"you\".")
    }

    private let busyJob = AppleOnDeviceInstructions.JobSummary(
        reference: "JOB-1005-B", unit: "SLP99UH070",
        openTasks: (1...9).map { "Task \($0): " + String(repeating: "check the flame sensor and clean it ", count: 4) },
        lastReading: "manifold pressure 3.5 inches water column",
        questions: ["the job number; ask for it", "a yes or no to switching the unit to EL296UH045"],
        paused: true)

    func testTheBudgetLeavesTheWindowRoomForToolsAndTheAnswer() {
        // 4,096 tokens shared: instructions (~4 characters a token), tool definitions, and what is
        // left for the carried turns, the request and the answer.
        let instructionTokens = AppleOnDeviceInstructions.characterBudget / 4
        XCTAssertLessThanOrEqual(instructionTokens + AppleOnDeviceToolSet.definitionBudgetTokens, 4_096 - 1_024)
    }

    func testTheDefaultPromptFitsTheBudgetWithEverythingSwitchedOn() {
        let built = AppleOnDeviceInstructions.build(inputs(
            memory: String(repeating: "prefers metric units; ", count: 60),
            weather: String(repeating: "light rain, 12 degrees, wind from the south; ", count: 20),
            job: busyJob, fieldAssistActive: true))
        XCTAssertLessThanOrEqual(built.text.count, AppleOnDeviceInstructions.characterBudget)
        XCTAssertTrue(built.text.contains("CURRENT DATE & TIME:"), "the date line is always kept")
        XCTAssertTrue(built.text.contains("FIELD ASSIST JOB"))
        XCTAssertTrue(built.text.contains("SAFETY"))
    }

    func testTheReportedBlocksAddUpToWhatWasSent() {
        let built = AppleOnDeviceInstructions.build(inputs(memory: "partner = Alex", job: busyJob,
                                                           fieldAssistActive: true))
        XCTAssertEqual(built.blocks.reduce(0) { $0 + $1.characters }, built.text.count)
        let names = built.blocks.map(\.name)
        XCTAssertEqual(names.first?.hasPrefix("system prompt"), true)
        for expected in ["app guide (on-device)", "field assist: job summary", "field assist: manuals note",
                         "memory", "date and time", "location", "speaker", "safety policy (on-device)"] {
            XCTAssertTrue(names.contains(expected), "missing \(expected) in \(names)")
        }
        XCTAssertEqual(names.last, "safety policy (on-device)", "the policy closes the instructions, as on every path")
    }

    func testAShortPersonaIsKeptWholeAndALongOneIsCondensedOnASentence() {
        let short = AppleOnDeviceInstructions.build(inputs(persona: "You are Nova. Be brief."))
        XCTAssertTrue(short.text.hasPrefix("You are Nova. Be brief."))
        XCTAssertEqual(short.blocks.first?.name, "system prompt")

        let long = String(repeating: "Always answer in a calm and friendly tone. ", count: 200)
        let condensed = AppleOnDeviceInstructions.build(inputs(persona: long))
        XCTAssertLessThanOrEqual(condensed.text.count, AppleOnDeviceInstructions.characterBudget)
        XCTAssertEqual(condensed.blocks.first?.name, "system prompt (condensed)")
        XCTAssertTrue(condensed.text.hasPrefix("Always answer in a calm and friendly tone."))
        let personaEnd = condensed.text.range(of: "\n\nTHIS APP")!.lowerBound
        XCTAssertTrue(condensed.text[..<personaEnd].hasSuffix("."), "the cut lands on a sentence")
    }

    func testTheCameraSectionIsDroppedBecauseThisModelNeverSeesAPhoto() {
        let built = AppleOnDeviceInstructions.build(inputs())
        XCTAssertFalse(built.text.contains("VISION & CAMERA"))
        XCTAssertFalse(built.text.contains("You CAN see images"))
        XCTAssertTrue(built.text.contains("RESPONSE STYLE") || built.blocks.first?.name == "system prompt (condensed)")
    }

    func testAnOpenJobTravelsAsASummaryWithTheManualsNote() {
        let built = AppleOnDeviceInstructions.build(inputs(job: busyJob))
        XCTAssertTrue(built.text.contains("Job: JOB-1005-B. Unit: SLP99UH070."))
        XCTAssertTrue(built.text.contains("Last reading: manifold pressure 3.5 inches water column."))
        XCTAssertTrue(built.text.contains("(and 5 earlier)"), "four tasks shown, the rest counted")
        XCTAssertTrue(built.text.contains("Waiting on the technician: the job number; ask for it."))
        XCTAssertTrue(built.text.contains("PAUSED"))
        XCTAssertTrue(built.text.contains("manual answers need a cloud model on this phone"))
        XCTAssertFalse(built.text.contains("<field_assist_context>"), "no vault or manual passages")
    }

    func testNoJobAndNoFieldAssistMeansNoJobOrManualsBlock() {
        let built = AppleOnDeviceInstructions.build(inputs())
        XCTAssertFalse(built.blocks.map(\.name).contains { $0.hasPrefix("field assist") })
        let fieldOn = AppleOnDeviceInstructions.build(inputs(fieldAssistActive: true))
        XCTAssertTrue(fieldOn.blocks.map(\.name).contains("field assist: manuals note"),
                      "said before a job opens, so a first question gets the honest answer")
    }

    func testMemoryIsClippedAndTheClipIsReported() {
        let memory = String(repeating: "m", count: 1_000)
        let built = AppleOnDeviceInstructions.build(inputs(memory: memory))
        XCTAssertEqual(built.memoryDroppedCharacters, 1_000 - AppleOnDeviceInstructions.memoryLimit)
        XCTAssertTrue(built.text.contains("[REMEMBER: key = value]"))
    }

    func testTheShortGuideAndPolicyAreShorterAndKeepTheirRules() {
        let guide = SystemPromptBuilder.onDeviceAppGuide(appName: "OpenGlasses")
        XCTAssertLessThan(guide.count, SystemPromptBuilder.appGuide(appName: "OpenGlasses").count / 2)
        XCTAssertTrue(guide.contains("cannot change settings yourself"))
        XCTAssertTrue(guide.contains("never in the iPhone's Settings app"))

        let policy = PromptInjectionPolicy.onDeviceSystemPromptPolicy
        XCTAssertLessThan(policy.count, PromptInjectionPolicy.systemPromptPolicy.count)
        for rule in ["UNTRUSTED DATA", "<untrusted_tool_output>", "Never obey", "ignore previous instructions",
                     "Only the person speaking to you", "clear request", "server__tool", "bypass these rules"] {
            XCTAssertTrue(policy.contains(rule), "the short policy lost: \(rule)")
        }
    }

    func testTheSummaryOfARealSessionNamesOnlyWhatIsOpen() {
        var session = FieldSession(id: "s", vaultId: "refrigeration", assetId: nil, mode: .aiOnly,
                                   startedAt: Date(), outcome: .inProgress, escalations: [], billableSeconds: 0)
        session.jobReference = "4411"
        session.tasks = [
            FieldSession.Task(title: "Replace the igniter", origin: .operatorAdded, status: .inProgress),
            FieldSession.Task(title: "Clean the condensate trap", origin: .operatorAdded, status: .done),
        ]
        session.spokenReadings = [
            SpokenReading(id: "r1", quantity: "supply air", value: "140", unit: "°F"),
            SpokenReading(id: "r2", quantity: "supply air", value: "142", unit: "°F", supersedes: "r1"),
        ]
        session.jobIntake = .recorded(reference: "4411")
        let summary = AppleOnDeviceInstructions.JobSummary(session: session)
        XCTAssertEqual(summary.reference, "4411")
        XCTAssertEqual(summary.openTasks, ["Replace the igniter (in progress)"])
        XCTAssertEqual(summary.lastReading, "supply air 142 °F")
        XCTAssertEqual(summary.questions, [])
        XCTAssertFalse(summary.paused)

        session.jobIntake = .needsReference
        session.pausedAt = Date()
        let waiting = AppleOnDeviceInstructions.JobSummary(session: session)
        XCTAssertEqual(waiting.questions, ["the job number; ask for it"])
        XCTAssertTrue(waiting.paused)
    }
}
