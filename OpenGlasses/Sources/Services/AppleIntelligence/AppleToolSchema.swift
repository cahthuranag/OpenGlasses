import Foundation

/// A native tool's JSON-schema parameters, read into the shape Apple's on-device model takes
/// (Plan JD P0).
///
/// Every `NativeTool` describes its arguments as a JSON-schema dictionary — the shape every cloud
/// provider's declarations are built from. Apple's Foundation Models framework takes its own
/// `GenerationSchema` instead, and it is built from typed values, not a dictionary. This is the
/// pure reading between the two: a small tree the bridge turns into Apple's types one-to-one, with
/// no Foundation Models import, so every tool's conversion can be asserted headlessly.
///
/// The on-device model has a 4,096-token context window shared by instructions, tool definitions
/// and the conversation, so every description is **condensed** on the way through: a tool's
/// description keeps its first sentences up to `Limits.toolDescription` characters, a property's
/// up to `Limits.propertyDescription`. The cut lands on a sentence boundary when one is in reach,
/// so what survives is still a sentence the model can act on, not a fragment.
enum AppleToolSchema {

    /// One node of the converted schema.
    indirect enum Node: Equatable {
        /// A string, constrained to `choices` when the schema declared an `enum`.
        case string(choices: [String]?)
        case integer
        case number
        case boolean
        case array(Node)
        /// `name` is the unique type name Apple's schema needs for every object (nested objects are
        /// named by their path, `tool_property`, so two tools can share a property name).
        case object(name: String, description: String?, properties: [Property])
    }

    struct Property: Equatable {
        let name: String
        let description: String?
        let node: Node
        /// `true` unless the enclosing object listed the property under `required`.
        let isOptional: Bool
    }

    /// How much of each description survives. Characters, not tokens: the estimate below is what
    /// the budget reasons in, but a cut has to land in text.
    struct Limits: Equatable {
        var toolDescription: Int
        var propertyDescription: Int
        /// An `enum` longer than this is rendered as free text with the choices named in the
        /// description instead — the constrained form costs a token per choice.
        var maxChoices: Int

        static let standard = Limits(toolDescription: 360, propertyDescription: 150, maxChoices: 24)
    }

    /// The converted root for one tool. The root is always an object named after the tool, even
    /// when the tool declared no parameters at all, because that is the only shape a tool's
    /// `parameters` schema may have.
    static func root(toolName: String, parameters: [String: Any],
                     limits: Limits = .standard) -> Node {
        let node = Self.node(from: parameters, path: toolName, limits: limits)
        if case .object = node { return node }
        return .object(name: toolName, description: nil, properties: [])
    }

    /// The condensed description a tool definition carries.
    static func toolDescription(_ description: String, limits: Limits = .standard) -> String {
        condense(description, limit: limits.toolDescription)
    }

    /// One node, read from a schema fragment. An unknown or missing `type` reads as a string: the
    /// model can always produce text, and the tool parses what it is given as it always has.
    static func node(from schema: [String: Any], path: String, limits: Limits) -> Node {
        let type = (schema["type"] as? String)?.lowercased() ?? "string"
        switch type {
        case "object":
            let required = Set((schema["required"] as? [String]) ?? [])
            let raw = (schema["properties"] as? [String: Any]) ?? [:]
            // Sorted so the rendered definition is stable between launches — a dictionary's order
            // is not, and a changing definition would read as a changing tool to the model.
            let properties: [Property] = raw.keys.sorted().compactMap { key in
                guard let fragment = raw[key] as? [String: Any] else { return nil }
                var description = (fragment["description"] as? String)
                    .map { condense($0, limit: limits.propertyDescription) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                if let suffix = choicesSuffix(for: fragment, limits: limits) {
                    description = [description, suffix].compactMap { $0 }.joined(separator: " ")
                }
                return Property(name: key,
                                description: description,
                                node: node(from: fragment, path: "\(path)_\(key)", limits: limits),
                                isOptional: !required.contains(key))
            }
            let description = (schema["description"] as? String)
                .map { condense($0, limit: limits.propertyDescription) }
                .flatMap { $0.isEmpty ? nil : $0 }
            return .object(name: path, description: description, properties: properties)
        case "integer":
            return .integer
        case "number":
            return .number
        case "boolean":
            return .boolean
        case "array":
            let items = (schema["items"] as? [String: Any]) ?? ["type": "string"]
            return .array(node(from: items, path: "\(path)_item", limits: limits))
        default:
            if let choices = schema["enum"] as? [String], !choices.isEmpty,
               choices.count <= limits.maxChoices {
                return .string(choices: choices)
            }
            return .string(choices: nil)
        }
    }

    /// A property whose `enum` was too long to constrain still tells the model its choices, in the
    /// description. Pure, so the bridge and the tests agree on the text.
    static func choicesSuffix(for schema: [String: Any], limits: Limits = .standard) -> String? {
        guard let choices = schema["enum"] as? [String], choices.count > limits.maxChoices else {
            return nil
        }
        return "One of: " + choices.joined(separator: ", ")
    }

    // MARK: - Condensing

    /// `text` with its whitespace collapsed and cut to `limit` characters on a sentence boundary
    /// when one lies in the second half of the budget, else on a word boundary with an ellipsis.
    static func condense(_ text: String, limit: Int) -> String {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard collapsed.count > limit, limit > 0 else { return collapsed }
        let window = String(collapsed.prefix(limit))
        // The last sentence end inside the window: ". ", "! " or "? " followed by a space, or a
        // terminal mark that happens to sit exactly at the cut.
        if let end = lastSentenceEnd(in: window), end >= limit / 2 {
            return String(window.prefix(end + 1))
        }
        if let space = window.lastIndex(of: " "), window.distance(from: window.startIndex, to: space) >= limit / 2 {
            return String(window[..<space]) + "…"
        }
        return window + "…"
    }

    private static func lastSentenceEnd(in text: String) -> Int? {
        let characters = Array(text)
        var index = characters.count - 1
        while index >= 0 {
            let character = characters[index]
            if character == "." || character == "!" || character == "?" {
                // A mark counts as a sentence end when it is followed by a space or ends the text.
                // "e.g." and "1.5" have a letter or digit after the mark and are skipped.
                if index == characters.count - 1 || characters[index + 1] == " " {
                    // Not a decimal point or an abbreviation of the form "x." inside a word.
                    if index > 0, characters[index - 1].isNumber, index + 1 < characters.count,
                       characters[index + 1].isNumber {
                        index -= 1
                        continue
                    }
                    return index
                }
            }
            index -= 1
        }
        return nil
    }

    // MARK: - Size

    /// A rough token count for one converted tool: name, description, and every property's name,
    /// description, type and choices, at four characters a token plus a per-field overhead for the
    /// framework's rendering. Deliberately pessimistic — the budget it feeds is a ceiling.
    static func estimatedTokens(name: String, description: String, root: Node) -> Int {
        var characters = name.count + description.count
        var fields = 1
        func walk(_ node: Node) {
            switch node {
            case .string(let choices):
                characters += choices.map { $0.reduce(0) { $0 + $1.count + 2 } } ?? 0
            case .integer, .number, .boolean:
                break
            case .array(let item):
                walk(item)
            case .object(let objectName, let description, let properties):
                characters += objectName.count + (description?.count ?? 0)
                for property in properties {
                    fields += 1
                    characters += property.name.count + (property.description?.count ?? 0)
                    walk(property.node)
                }
            }
        }
        walk(root)
        return characters / 4 + fields * 6
    }
}

/// The arguments Apple's model produced for a tool call, read back into the dictionary every
/// `NativeTool.execute(args:)` takes. Pure.
enum AppleToolArguments {
    /// The JSON object as a dictionary, with explicit `null` values removed so an optional the
    /// model left out reads as absent — exactly as a cloud provider's call omits it — rather than
    /// as `NSNull` for a tool to trip over. Anything that is not a JSON object reads as no
    /// arguments.
    static func dictionary(fromJSON json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return [:] }
        return dictionary.filter { !($0.value is NSNull) }
    }
}

/// How much of the app's conversation the on-device session is rebuilt with each turn, and how
/// that shrinks when the model reports its window is full (Plan JD P0). Pure.
///
/// The session is rebuilt from `conversationHistory` every turn rather than kept: the lean prompt
/// changes every turn (date, location, memory), and the app's history is the single record a
/// cleared or reloaded conversation already keeps consistent. Tool calls and their outputs are not
/// carried — the answer that followed them is.
enum AppleSessionPolicy {
    /// Turns (user and assistant entries) carried into a fresh session.
    static let carriedEntryLimit = 12

    /// The next, smaller carry after the model refused the current one for size. `nil` when there
    /// is nothing left to drop: the prompt alone does not fit, which no retry can fix.
    static func carryAfterOverflow(_ current: Int) -> Int? {
        switch current {
        case ...0: return nil
        case 1...4: return 0
        default: return 4
        }
    }
}
