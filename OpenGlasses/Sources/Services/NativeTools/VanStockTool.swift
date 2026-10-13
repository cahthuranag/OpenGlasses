import Foundation

/// The fields that describe one part, shared by a single-part call and each entry of `items`.
private func vanStockLineProperties() -> [String: Any] {
    [
        "part": [
            "type": "string",
            "description": "The part number, exactly as the label or the manual prints it."
        ],
        "description": [
            "type": "string",
            "description": "What the part is, in the technician's words: '45/5 capacitor'."
        ],
        "quantity": [
            "type": "integer",
            "description": "How many. Defaults to 1 for load, use and remove; required for count."
        ],
        "unit": [
            "type": "string",
            "enum": VanStockUnit.allCases.map(\.rawValue),
            "description": "How the part is counted. Defaults to each."
        ],
        "code": [
            "type": "string",
            "description": "A barcode or QR code read by scan_code, verbatim."
        ],
        "new_line": [
            "type": "boolean",
            "description": "For load or count: true when the technician says this is a different part from a similar line already on the van."
        ]
    ]
}

/// What is on the technician's own van or truck, kept by voice (Plan IH §3).
///
/// Loading happens at the shop with no job open, so unlike the other Field Assist tools this one
/// needs Field Assist switched on and nothing else. Everything it does is on the phone: it works
/// with no signal, and it never asks the office for anything — at zero it tells the model to offer
/// a request, and the request is `parts_request`'s to make once the technician has said yes.
@MainActor
final class VanStockTool: NativeTool {
    let name = "van_stock"
    let description = """
    The technician's own van or truck stock, kept on the phone. Use it whenever they ask what is \
    on the van or truck, or say they loaded, used, returned or counted parts. Works without a job \
    open and without signal. Pass 'action': 'check' (how many of one part; pass 'part' and/or \
    'description'), 'low' (what has run out or is at its minimum), 'load' (parts put on the van), \
    'use' (parts fitted from the van; tagged to the open job), 'remove' (parts taken off for \
    another reason; pass 'reason'), 'count' (a stocktake: sets the figure), or 'undo' (takes back \
    the last spoken entry). For one part pass 'part' (the number exactly as printed), \
    'description', 'quantity' and optionally 'unit'; for several parts in one sentence pass \
    'items', each with the same fields. A scanned barcode goes in 'code'. Read the result back to \
    the technician as given: it says how each figure is known, and it spells out a part number it \
    has not met so a misheard one can be undone. Never state a quantity this tool did not return. \
    When more than one line fits, ask which one. When the result offers a replacement, ask the \
    technician before requesting one.
    """

    let parametersSchema: [String: Any] = {
        var properties = vanStockLineProperties()
        properties["action"] = [
            "type": "string",
            "enum": ["check", "low", "load", "use", "remove", "count", "undo"],
            "description": "What to do."
        ]
        properties["items"] = [
            "type": "array",
            "description": "Several parts said in one sentence. Use instead of the single-part fields.",
            "items": ["type": "object", "properties": vanStockLineProperties()] as [String: Any]
        ]
        properties["reason"] = [
            "type": "string",
            "enum": VanStockMovement.RemovalReason.allCases.map(\.rawValue),
            "description": "For 'remove': why it came off the van."
        ]
        return ["type": "object", "properties": properties, "required": ["action"]]
    }()

    /// The service to speak for; nil means the shared one. Injectable for tests.
    private let injectedService: VanStockService?

    init(service: VanStockService? = nil) {
        self.injectedService = service
    }

    private var service: VanStockService { injectedService ?? .shared }

    func execute(args: [String: Any]) async throws -> String {
        guard Config.fieldAssistActive else {
            return "Field Assist is disabled. Enable it in Settings → Field Assist."
        }
        let action = (args["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let lines = Self.lines(args)

        switch action {
        case "check":
            guard let line = lines.first else { return "Say which part to check, by number or description." }
            return service.check(line)
        case "low":
            return service.low()
        case "load":
            return service.load(lines, source: Self.source(lines))
        case "use":
            return service.use(lines, source: Self.source(lines))
        case "remove":
            let reason = (args["reason"] as? String).flatMap { VanStockMovement.RemovalReason(rawValue: $0.lowercased()) }
            return service.remove(lines, reason: reason ?? .other, source: Self.source(lines))
        case "count":
            return service.count(lines, source: Self.source(lines))
        case "undo":
            return service.undo()
        default:
            return "Pass 'action': check, low, load, use, remove, count or undo."
        }
    }

    /// The lines of one call: `items` when it is given, otherwise the single-part fields.
    static func lines(_ args: [String: Any]) -> [VanStockService.Line] {
        let raw = (args["items"] as? [[String: Any]]).flatMap { $0.isEmpty ? nil : $0 } ?? [args]
        return raw.compactMap { entry in
            let line = VanStockService.Line(part: Self.text(entry["part"]),
                                            description: Self.text(entry["description"]),
                                            quantity: PartsRequestTool.integer(entry["quantity"]),
                                            unit: Self.text(entry["unit"]),
                                            code: Self.text(entry["code"]),
                                            asNew: (entry["new_line"] as? Bool) ?? false)
            return line.part == nil && line.description == nil && line.code == nil ? nil : line
        }
    }

    /// A call that carries a scanned code was scanned; anything else was said.
    private static func source(_ lines: [VanStockService.Line]) -> VanStockMovement.Source {
        lines.contains { $0.code != nil } ? .scanned : .spoken
    }

    /// Models send a part number as a string or, when it is all digits, as a number.
    private static func text(_ raw: Any?) -> String? {
        if let value = raw as? String { return value }
        if let value = raw as? Int { return String(value) }
        return nil
    }
}
