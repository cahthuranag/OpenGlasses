import Foundation

/// When smart camera may take a frame for a turn, beyond what `VisionIntentDetector` reads in its
/// words (Plan JW P0). Pure.
///
/// # "Show me the table"
///
/// `VisionIntentDetector` hears "show me" as a request to look. In a Field Assist session whose last
/// answer cited manual pages it is nothing of the kind: "show me the table", "open the page",
/// "bring up the second source" mean the cited pages, which `show_source` puts on the phone. The
/// partner's trace: every such turn grabbed a frame before the model was called, and with the
/// glasses added but not connected the grab ran three Meta permission attempts (about eight
/// seconds) and was rejected — then the model called `show_source` anyway. So while there are cited
/// pages to show, a turn that asks to show one is not a camera turn: no capture, no live frame, and
/// not the cooldown's follow-up either, so routing (`expectsCameraImage`) and the grab agree.
///
/// # A link that is down
///
/// Connected means `linkState == .connected` (`CameraService.isGlassesLinkUp`). A glasses capture
/// with the link down cannot succeed, and trying costs the permission attempts above; smart camera
/// sends no picture instead, at once. It never swaps to the phone camera for an automatic capture:
/// a phone in a pocket would answer the question with a picture of the pocket.
enum SmartCameraPolicy {

    /// What smart camera knows about the turn besides its words.
    struct Context: Equatable {
        /// The session's last answer cited manual pages that `show_source` can open.
        var citedManualPagesOpen = false
    }

    /// Whether the turn needs the camera.
    static func intent(for query: String, context: Context) -> VisionIntentDetector.CameraIntent {
        isAboutCitedPages(query, context: context) ? .textOnly : VisionIntentDetector.classify(query)
    }

    /// Whether the turn asks to see the cited pages, so no frame of any kind goes with it.
    static func isAboutCitedPages(_ query: String, context: Context) -> Bool {
        context.citedManualPagesOpen && asksToShowSource(query)
    }

    /// Whether the glasses camera may be started for an automatic capture: only with the link up.
    static func mayStartGlassesCapture(linkUp: Bool) -> Bool { linkUp }

    // MARK: - The words

    /// "Show me the table", "open the page", "bring up the second source", "show me" on its own:
    /// a verb that puts something on screen, and after it a page, table, figure, row, source,
    /// passage or diagram — or a bare "show me (that)". Words that name the camera or the world in
    /// front of the wearer keep it a camera turn ("show me what's in front of me").
    static func asksToShowSource(_ query: String) -> Bool {
        let words = query.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
        guard !words.isEmpty else { return false }
        let padded = " " + words.joined(separator: " ") + " "
        if cameraWords.contains(where: { padded.contains(" \($0) ") }) { return false }
        if words.count <= 4, words.first == "show", words.allSatisfy(bareShowWords.contains) { return true }
        if padded.contains(" where does it say ") { return true }
        for verb in showVerbs {
            guard let range = padded.range(of: " \(verb) ") else { continue }
            let rest = padded[range.upperBound...].split(separator: " ").map(String.init)
            if rest.contains(where: sourceNouns.contains) { return true }
        }
        return false
    }

    private static let showVerbs = ["show", "open", "bring up", "bring back", "pull up", "put up", "display",
                                    "highlight", "go to", "go back to", "let me see"]

    private static let sourceNouns: Set<String> = [
        "page", "pages", "table", "tables", "figure", "figures", "row", "rows", "source", "sources",
        "passage", "passages", "diagram", "diagrams", "clause", "clauses", "section", "drawing",
    ]

    /// A short "show me (that) (again)", which with pages cited means the first of them.
    private static let bareShowWords: Set<String> = ["show", "me", "it", "that", "this", "them", "those", "again",
                                                     "please"]

    private static let cameraWords = ["camera", "glasses", "in front of me", "what you see", "what do you see",
                                      "can you see", "do you see", "look at", "take a photo", "take a picture"]
}
