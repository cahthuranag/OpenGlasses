import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// A native tool, offered to Apple's on-device model as one of the framework's own `Tool`s
/// (Plan JD P0).
///
/// The model calls tools through constrained decoding against `parameters`, so the arguments it
/// produces always match the schema; the framework runs `call(arguments:)` for each call it makes
/// — several in one turn when the request needs them — and folds the output back into the same
/// turn. What the adapter adds is the hop to the app's execution authority: every call goes to
/// `NativeToolRouter.executeRoot`, through `dispatch`, so the policy ladder, the approval card and
/// the HIPAA gate see an Apple call exactly as they see a cloud model's.
///
/// `dispatch` never throws. A tool that failed is reported to the model as text ("Error: …"), the
/// way the cloud wires report it, so the model can tell the wearer rather than the turn dying in a
/// `ToolCallError`.
@available(iOS 26.0, *)
struct NativeToolAdapter: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let dispatch: @Sendable (_ name: String, _ argumentsJSON: String) async -> String

    func call(arguments: GeneratedContent) async throws -> String {
        await dispatch(name, arguments.jsonString)
    }
}

@available(iOS 26.0, *)
enum AppleToolBridge {

    /// The adapter for one native tool, or `nil` when its schema cannot be expressed — logged by
    /// the caller; the tool is simply not offered rather than the whole session failing.
    static func adapter(name: String, description: String, parameters: [String: Any],
                        limits: AppleToolSchema.Limits = .standard,
                        dispatch: @escaping @Sendable (String, String) async -> String) throws -> NativeToolAdapter {
        let root = AppleToolSchema.root(toolName: name, parameters: parameters, limits: limits)
        return NativeToolAdapter(name: name,
                                 description: AppleToolSchema.toolDescription(description, limits: limits),
                                 parameters: try generationSchema(for: root),
                                 dispatch: dispatch)
    }

    /// Apple's schema for a converted root.
    static func generationSchema(for root: AppleToolSchema.Node) throws -> GenerationSchema {
        try GenerationSchema(root: dynamicSchema(root, path: "root"), dependencies: [])
    }

    /// The typed schema for one node. `path` names the constrained-string and object types the
    /// framework requires a unique name for.
    static func dynamicSchema(_ node: AppleToolSchema.Node, path: String) -> DynamicGenerationSchema {
        switch node {
        case .string(let choices):
            if let choices {
                return DynamicGenerationSchema(name: path, anyOf: choices)
            }
            return DynamicGenerationSchema(type: String.self)
        case .integer:
            return DynamicGenerationSchema(type: Int.self)
        case .number:
            return DynamicGenerationSchema(type: Double.self)
        case .boolean:
            return DynamicGenerationSchema(type: Bool.self)
        case .array(let item):
            return DynamicGenerationSchema(arrayOf: dynamicSchema(item, path: "\(path)_item"))
        case .object(let name, let description, let properties):
            return DynamicGenerationSchema(
                name: name,
                description: description,
                properties: properties.map { property in
                    DynamicGenerationSchema.Property(
                        name: property.name,
                        description: property.description,
                        schema: dynamicSchema(property.node, path: "\(name)_\(property.name)"),
                        isOptional: property.isOptional)
                })
        }
    }

    /// The session transcript for a turn: fresh instructions carrying the tool definitions, then
    /// the last `carry` entries of the app's conversation as prompt/response pairs.
    static func transcript(instructions: String, tools: [any Tool],
                           history: [(role: String, content: String)], carry: Int) -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: tools.map { Transcript.ToolDefinition(tool: $0) })),
        ]
        for turn in history.suffix(max(carry, 0)) where !turn.content.isEmpty {
            let segment = Transcript.Segment.text(Transcript.TextSegment(content: turn.content))
            switch turn.role {
            case "assistant":
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [segment])))
            case "user":
                entries.append(.prompt(Transcript.Prompt(segments: [segment])))
            default:
                continue
            }
        }
        return Transcript(entries: entries)
    }
}
#endif
