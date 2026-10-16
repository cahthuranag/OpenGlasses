import Foundation

/// The voice verbs that move a task: "do it", "skip that", "later", "done", "add a task".
///
/// Voice verbs are ambiguous — "done" could close a task or a procedure step — so this resolves
/// against the active task first, falls back to the latest recommendation when nothing is running,
/// and **says out loud what it changed**. A confirmation the technician can contradict is the only
/// safe way to run a state machine by voice.
@MainActor
final class TaskTool: NativeTool {
    let name = "task"
    let description = """
    Move a task on the active Field Assist job when the technician decides something. Pass 'verb': \
    'accept' ("do it", "yes, do that") starts the recommendation and its procedure if it names \
    one; 'decline' ("skip that", "no") and 'defer' ("later", "next visit") keep it on the record as \
    recommended-but-not-done; 'start' picks up a task accepted earlier; 'done' closes the task the \
    technician is working on, with 'completion_note' for what they said they did ("replaced the \
    ignitor, 47 ohms before") — only once they have said the work is done: a reading or a finding \
    is not a repair, and 'done' is refused until they say so; 'abandon' gives one up; 'add' with \
    'title' records work the technician did that nobody recommended ("add a task: cleaned the \
    condensate trap") and starts it immediately — work already on the job is not added twice. Omit 'task_id' and the verb applies to the task in progress, or to the latest \
    recommendation when none is running. Pass 'read_back' to hear the whole job so far. Repeat the \
    confirmation this returns to the technician. Requires an active session.
    """
    let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "verb": [
                "type": "string",
                "enum": ["accept", "decline", "defer", "start", "done", "abandon", "add"],
                "description": "What the technician decided."
            ],
            "task_id": [
                "type": "string",
                "description": "The task to move. Omit to use the task in progress, or the latest recommendation."
            ],
            "title": [
                "type": "string",
                "description": "For 'add': what the technician did or is doing."
            ],
            "why": [
                "type": "string",
                "description": "For 'add': why, when the technician says."
            ],
            "completion_note": [
                "type": "string",
                "description": "For 'done' / 'abandon': what the technician said they did, in their words."
            ],
            "verified": [
                "type": "boolean",
                "description": "For 'done': true only when the technician says the check the fix waits on passed (a retest). Closing a 'Verify: …' task needs it."
            ],
            "read_back": [
                "type": "boolean",
                "description": "Read the whole job back: equipment, tasks by status with their evidence, parts, pages verified and time."
            ]
        ],
        "required": [] as [String]
    ]

    /// Session to act on; nil means the shared service. Injectable for tests.
    private let injectedSession: FieldSessionService?
    /// The technician's words this turn, read at execution time. Nil (nothing spoken or typed)
    /// leaves the completion gate out of the way.
    private let currentUtterance: @MainActor () -> String?

    init(sessionService: FieldSessionService? = nil,
         currentUtterance: @escaping @MainActor () -> String? = { TechnicianWords.current() }) {
        self.injectedSession = sessionService
        self.currentUtterance = currentUtterance
    }

    private var session: FieldSessionService { injectedSession ?? .shared }

    func execute(args: [String: Any]) async throws -> String {
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        guard session.activeSession != nil else {
            return "No active Field Assist session. Start a session before recording work."
        }

        if (args["read_back"] as? Bool) == true, args["verb"] == nil {
            return readBack()
        }

        let verb = (args["verb"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch verb {
        case "add":
            return add(args: args)
        case "accept", "decline", "defer":
            return decide(verb: verb!, args: args)
        case "start":
            return start(args: args)
        case "done", "abandon":
            return close(verb: verb!, args: args)
        case nil, "":
            return "Say what to do with the task: accept, decline, defer, start, done, abandon, or add."
        default:
            return "'\(verb!)' is not a task verb. Use accept, decline, defer, start, done, abandon, or add."
        }
    }

    // MARK: - Verbs

    private func add(args: [String: Any]) -> String {
        let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            return "Say what the task is — \"add a task: cleaned the condensate trap\"."
        }
        // The same work already on this unit is that task, not a second one: one repair reported
        // twice put two completed replacements on the report. Another unit's is its own work.
        if let job = session.activeSession, let existing = job.tasks.last(where: {
            $0.status != .declined && $0.status != .abandoned && job.belongsToCurrentEquipment($0)
                && TaskTitleMatch.isSameWork($0.title, title)
        }) {
            return sameWork(existing)
        }
        do {
            let task = try session.addOperatorTask(
                title: title,
                why: (args["why"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            return "Added \(task.title) to the job and started it. Nobody recommended this one — "
                + "it is recorded as the technician's own. Say 'done' when it is finished."
        } catch {
            return error.localizedDescription
        }
    }

    private func decide(verb: String, args: [String: Any]) -> String {
        guard let task = resolveTask(args: args, preferringActive: false) else {
            return "There is no recommendation waiting on this job. Name the task, or ask me to look something up first."
        }
        let decision: FieldSessionService.TaskDecision = verb == "accept" ? .accept
            : (verb == "decline" ? .decline : .defer_)
        do {
            let result = try session.decideTask(id: task.id, decision: decision)
            switch decision {
            case .decline:
                return "Declined \(result.task.title). It stays on the record as recommended and not done."
            case .defer_:
                return "Deferred \(result.task.title). It stays on the record for the next visit."
            case .accept:
                var lines = ["Accepted \(result.task.title)."]
                if let step = result.procedureStep {
                    lines.append("Starting \(result.task.procedureId ?? "the procedure"): \(step.title). \(step.instruction)")
                    lines.append("The procedure's outcome will close this task.")
                } else if let problem = result.procedureProblem {
                    lines.append("The procedure did not start: \(problem) Work through it yourself and say 'done' when finished.")
                } else if result.task.status == .accepted {
                    lines.append("Another task is still in progress, so this one is queued. Say 'start' when you get to it.")
                } else {
                    lines.append("It is the task in progress now — readings, photos and pages go on it. Say 'done' when finished.")
                }
                if let note = result.task.safetyNote, !note.isEmpty {
                    lines.insert("Safety first: \(note).", at: 1)
                }
                return lines.joined(separator: " ")
            }
        } catch {
            return error.localizedDescription
        }
    }

    private func start(args: [String: Any]) -> String {
        let named = (args["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (named?.isEmpty == false)
            ? resolveTask(args: args, preferringActive: false)
            : (session.activeSession?.nextStartable ?? session.latestRecommendation)
        guard let task = resolved else {
            return "There is nothing waiting to start on this job."
        }
        do {
            let started = try session.startTask(id: task.id)
            return "Started \(started.title). Readings, photos and pages go on it from here."
        } catch {
            return error.localizedDescription
        }
    }

    private func close(verb: String, args: [String: Any]) -> String {
        guard let task = resolveTask(args: args, preferringActive: true) else {
            return "Nothing is in progress on this job, so there is nothing to close. "
                + "Say \"add a task: …\" to record what you did."
        }
        let note = (args["completion_note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let verified = (args["verified"] as? Bool) ?? false
        if verb == "done", let refusal = completionRefusal(task: task, verified: verified) {
            return refusal
        }
        do {
            let closed = verb == "done"
                ? try session.completeTask(id: task.id, note: note, confirmed: verified)
                : try session.abandonTask(id: task.id, note: note)
            var line = verb == "done" ? "Closed \(closed.title) as done." : "Marked \(closed.title) abandoned."
            // A fix whose check is still owed is done, not resolved (Plan GB P3).
            if verb == "done", let owed = session.activeSession?.openVerifications
                .first(where: { $0.verification == closed.verification && $0.id != closed.id }) {
                line += " '\(owed.title)' stays open until the technician confirms it. "
                    + VerificationRequirement.notYetVerified
            }
            if let note, !note.isEmpty { line += " Noted: \(note)." }
            if !closed.parts.isEmpty {
                line += " Parts on it: " + closed.parts.map(\.number).joined(separator: ", ") + "."
            }
            return line
        } catch {
            return error.localizedDescription
        }
    }

    /// Why `done` may not close `task` on what the technician said this turn, or nil when it may.
    ///
    /// A check closes on the technician saying it passed; any other task on them saying the work
    /// is done. The note the model writes is not evidence — it wrote "Replaced hot-surface
    /// ignitor" for a technician who had only measured one.
    private func completionRefusal(task: FieldSession.Task, verified: Bool) -> String? {
        guard let said = currentUtterance()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !said.isEmpty else { return nil }
        if task.isVerificationTask || verified {
            guard !TaskCompletionStatement.statesPassedCheck(said) else { return nil }
            return "Not closed: the technician has not said '\(task.title)' passed. Ask how the "
                + "check went, and close it with verified true when they say it passed. "
                + VerificationRequirement.notYetVerified
        }
        guard !TaskCompletionStatement.states(said, completing: task.title) else { return nil }
        return "Not closed: the technician has not said '\(task.title)' is done — what they said "
            + "is not a finished repair. It stays \(task.status.rawValue). Close it when they tell "
            + "you the work is finished, in their words."
    }

    /// What `add` says when the work is already on the job — and, when that task is still open,
    /// what it did with it instead.
    private func sameWork(_ existing: FieldSession.Task) -> String {
        switch existing.status {
        case .done:
            return "'\(existing.title)' is already on this job as done, so it was not added again. "
                + "Nothing changed."
        case .inProgress:
            return "'\(existing.title)' is already on this job and in progress, so it was not added "
                + "again. Say 'done' on it when the technician says it is finished."
        default:
            do {
                let started = try session.startTask(id: existing.id)
                return "'\(started.title)' was already on this job, so it was started rather than "
                    + "added again. Say 'done' on it when the technician says it is finished."
            } catch {
                return error.localizedDescription
            }
        }
    }

    private func readBack() -> String {
        guard let record = session.workRecord() else {
            return "No active Field Assist session."
        }
        return record.summary
    }

    // MARK: - Resolution

    /// "The latest recommendation" when the technician names nothing: the task in progress for a
    /// closing verb, the newest undecided recommendation for a deciding one.
    private func resolveTask(args: [String: Any], preferringActive: Bool) -> FieldSession.Task? {
        if let id = (args["task_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            return session.task(id: id) ?? session.activeSession?.tasks.first {
                $0.title.lowercased() == id.lowercased()
            }
        }
        // "The retest passed": the check still owed, when nothing else is named (Plan GB P3).
        if (args["verified"] as? Bool) == true, let owed = session.activeSession?.openVerifications.last {
            return owed
        }
        if preferringActive {
            return session.activeTask ?? session.latestRecommendation
        }
        return session.latestRecommendation ?? session.activeTask
    }
}
