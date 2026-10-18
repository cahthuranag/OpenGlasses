import XCTest
@testable import OpenGlasses

/// Plan IW P0 — every side-effecting registered tool has its own trail title, and reads have none.
/// A table test over the live registry, built the same way `ToolEffectClassPolicyTests` builds it,
/// so a tool added without a template fails here rather than appearing in the trail as "Used the
/// … tool".
@MainActor
final class ActivityTitlerTests: XCTestCase {

    // MARK: - The registry gate

    func testEverySideEffectingRegisteredToolHasATitleTemplate() {
        let registry = widestRegistry()
        var missing: [String] = []
        var titled = 0
        for tool in registry.allTools {
            if tool is SkillPackToolWrapper || tool is CustomToolWrapper { continue }
            let effectClass = ToolEffectClassifier.nativeClass(name: tool.name, args: [:],
                                                               semantics: tool.executionSemantics)
            guard effectClass >= .write else { continue }
            guard ActivityTitler.hasTemplate(for: tool.name),
                  let title = ActivityTitler.title(tool: tool.name, actionKey: nil, effectClass: effectClass) else {
                missing.append(tool.name)
                continue
            }
            titled += 1
            XCTAssertFalse(title.title.isEmpty, tool.name)
            XCTAssertNotEqual(title.title, ActivityTitler.genericTitle(tool: tool.name), tool.name)
            XCTAssertFalse(title.title.contains("_"), "a title is words, not a tool name: \(tool.name)")
            XCTAssertLessThanOrEqual(title.title.count, ActivityEntry.titleLength, tool.name)
        }
        XCTAssertEqual(missing.sorted(), [], "add a template to ActivityTitler.templates")
        XCTAssertGreaterThan(titled, 40, "the fixture registry must be wide, or the gate proves little")
    }

    /// Every template, registered here or not, reads as the assistant's own past-tense action.
    func testEveryTemplateIsAPastTenseSentenceFragment() {
        for (tool, template) in ActivityTitler.templates {
            for title in [template.title] + Array(template.actions.values) {
                XCTAssertFalse(title.isEmpty, tool)
                XCTAssertLessThanOrEqual(title.count, ActivityEntry.titleLength, tool)
                XCTAssertTrue(title.first?.isUppercase ?? false, "\(tool): \(title)")
                XCTAssertFalse(title.hasSuffix("."), "\(tool): \(title)")
                XCTAssertFalse(title.hasPrefix("I "), "the trail drops the 'I': \(tool): \(title)")
            }
            XCTAssertTrue(Set(template.actions.keys).isDisjoint(with: template.reads),
                          "\(tool): an action cannot be both titled and a read")
        }
    }

    // MARK: - Reads are not titled

    func testAReadIsNeverTitled() {
        XCTAssertNil(ActivityTitler.title(tool: "web_search", actionKey: nil, effectClass: .readOnly))
        XCTAssertNil(ActivityTitler.title(tool: "calendar", actionKey: "create", effectClass: .readOnly))
    }

    func testReadActionsOfAWritingToolAreNotTitled() {
        for (tool, action) in [("calendar", "today"), ("calendar", "upcoming"), ("reminder", "list"),
                               ("van_stock", "check"), ("smart_home", "list"), ("brain", "recall"),
                               ("field_session", "status"), ("manage_schedule", "list")] {
            XCTAssertNil(ActivityTitler.title(tool: tool, actionKey: action, effectClass: .write), "\(tool) \(action)")
        }
    }

    // MARK: - Actions sharpen the title

    func testTheActionKeySharpensTheTitle() {
        let cases: [(String, String?, ToolEffectClass, String)] = [
            ("calendar", "create", .write, "Added an event to your calendar"),
            ("calendar", " Add ", .write, "Added an event to your calendar"),
            ("calendar", nil, .write, "Changed your calendar"),
            ("reminder", "create", .write, "Set a reminder for you"),
            ("van_stock", "use", .write, "Recorded a part used from your van"),
            ("van_stock", "something_new", .write, "Updated your van stock"),
            ("smart_home", "unlock", .physicalActuation, "Unlocked a door for you"),
            ("send_message", nil, .messaging, "Sent a message for you"),
            ("parts_request", nil, .messaging, "Requested a part for you"),
            ("task", "done", .write, "Finished a job task"),
        ]
        for (tool, action, effectClass, expected) in cases {
            XCTAssertEqual(ActivityTitler.title(tool: tool, actionKey: action, effectClass: effectClass)?.title,
                           expected, "\(tool) \(action ?? "-")")
        }
    }

    // MARK: - The approval line, without the wearer's words

    func testTheApprovalLineBecomesTheDetailWithoutAQuotedBody() {
        let summary = PromptInjectionPolicy.actionSummary(toolName: "send_message",
                                                          args: ["to": "Sam", "body": "running late"])
        let title = ActivityTitler.title(tool: "send_message", actionKey: nil, approvalSummary: summary,
                                         effectClass: .messaging)
        XCTAssertEqual(title, ActivityTitle(title: "Sent a message for you",
                                            detail: "You approved: Send a message to Sam"))
        XCTAssertFalse(title?.detail?.contains("running late") ?? true)

        XCTAssertEqual(ActivityTitler.approvedDetail("Call 021 555 0100"), "You approved: Call 021 555 0100")
        XCTAssertNil(ActivityTitler.approvedDetail("“only quoted”"))
        XCTAssertNil(ActivityTitler.title(tool: "calendar", actionKey: "create", effectClass: .write)?.detail)
    }

    // MARK: - Tools with no template

    func testAToolWithNoTemplateGetsAPlainTitleNamingIt() {
        XCTAssertEqual(ActivityTitler.title(tool: "notes__create_page", actionKey: nil, effectClass: .unknown)?.title,
                       "Used the notes create page tool")
        XCTAssertEqual(ActivityTitler.genericTitle(tool: "_"), "Used the unnamed tool")
    }

    // MARK: - Helpers

    /// The widest registry this process can build headlessly — the same population the effect-class
    /// gate covers.
    private func widestRegistry() -> NativeToolRegistry {
        let savedFieldAssist = Config.fieldAssistEnabled
        let savedAccessibility = Config.accessibilityModeEnabled
        let savedEntitlement = EntitlementTestScope.grant()
        Config.setFieldAssistEnabled(true)
        Config.setAccessibilityModeEnabled(true)
        defer {
            Config.setFieldAssistEnabled(savedFieldAssist)
            Config.setAccessibilityModeEnabled(savedAccessibility)
            EntitlementTestScope.restore(savedEntitlement)
        }

        let registry = NativeToolRegistry(
            locationService: LocationService(),
            conversationStore: ConversationStore(),
            cameraService: CameraService(),
            medicalExportService: MedicalExportService())
        registry.register(MemorySearchTool())
        registry.register(AgentDiaryTool())
        registry.register(DocumentRAGTool())
        registry.register(StudyTool())
        registry.register(OpenClawSkillsTool())
        return registry
    }
}
