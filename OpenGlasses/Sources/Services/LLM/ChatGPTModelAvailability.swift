import Foundation

/// Whether the signed-in ChatGPT account offers the model a turn is about to send.
///
/// The subscription backend serves only the models in the account's own catalog, and answers any
/// other id with a 400 ("…model is not supported when using Codex with a ChatGPT account"). A saved
/// model drops out of that catalog when the account's plan changes, when the catalog rotates a
/// family out, or when it was only ever the app's pre-discovery default
/// (`ChatGPTOAuth.defaultModel`). Without a check every turn on it fails the same way, so the turn
/// sends the catalog's own default instead — for that turn only: the saved setting is the
/// wearer's and is left as it is.
///
/// Pure: the catalog is a value read from `ChatGPTContextCatalog`, so every rule is a unit test.
enum ChatGPTModelAvailability {

    /// The models one account's catalog lists.
    struct Catalog: Codable, Equatable {
        /// Every model id listed, hidden ones included: a hidden model is still served.
        let ids: [String]
        /// The ids the picker offers, in catalog order — the candidates for a replacement.
        let pickable: [String]
        /// The model the catalog marks as its default, when it marks one.
        let defaultID: String?

        init(ids: [String], pickable: [String], defaultID: String?) {
            self.ids = ids
            self.pickable = pickable
            self.defaultID = defaultID
        }

        /// Read from the `/codex/models` payload — the same rows `ModelFetcher` parses for the
        /// picker. Nil for a payload that is not a catalog.
        init?(data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let rows = object["models"] as? [[String: Any]] ?? object["data"] as? [[String: Any]] ?? []
            var seen = Set<String>()
            let ids = rows.compactMap { row -> String? in
                guard let id = row["slug"] as? String ?? row["id"] as? String ?? row["model"] as? String,
                      !id.isEmpty, seen.insert(id).inserted else { return nil }
                return id
            }
            let pickable = ModelFetcher.parseChatGPTModels(data)
            self.init(ids: ids, pickable: pickable.map(\.id),
                      defaultID: pickable.first(where: \.isDefault)?.id)
        }
    }

    enum Decision: Equatable {
        /// Send the model as saved: the catalog lists it, or there is no catalog to judge by.
        case send
        /// The catalog does not list the saved model; send this one instead.
        case substitute(String)
    }

    /// Said once per saved model per process, ahead of the first reply that used another one.
    /// It names no model: an id read aloud is noise, and the setting is where the names are.
    static let substitutionNotice =
        "The model you picked isn't on your ChatGPT plan, so I used the plan's default. You can change it in Settings."

    /// The decision for one turn. Never blocks a turn: with no catalog, an empty one, or nothing to
    /// offer in its place, the saved model is sent and the backend has the last word.
    static func decide(model: String, catalog: Catalog?) -> Decision {
        guard let catalog, !catalog.ids.isEmpty, !catalog.ids.contains(model) else { return .send }
        if let defaultID = catalog.defaultID, catalog.ids.contains(defaultID) {
            return .substitute(defaultID)
        }
        return catalog.pickable.first.map(Decision.substitute) ?? .send
    }
}
