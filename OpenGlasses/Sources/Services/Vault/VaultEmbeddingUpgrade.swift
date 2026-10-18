import Foundation

/// Keeps every vault's manuals on Field Assist's embedding model (Plan IV P4).
///
/// Field Assist searches manuals with the contextual model while "Smarter manual search" is on —
/// the default — and its asset is on the device. The asset may not be there yet: it downloads from
/// Apple on first use, and a phone offline or a failed request leaves it missing. Until it lands,
/// a vault indexes and answers with the standard model and stays searchable; when it lands, or
/// when the setting changes either way, each vault is re-indexed once in the background
/// (`DocumentStore.upgradeVaultEmbeddings`). The index that answers is untouched until the new one
/// is complete, a run the app leaves behind carries on from where it stopped, and progress shows
/// where every other index's does (`VaultIndexingMonitor`).
@MainActor
enum VaultEmbeddingUpgrade {

    /// The model a vault should be on now. A seam: tests pass their own.
    static var target: () -> Embedder = { Embedder.fieldAssist() }
    /// Asks for the contextual model's asset; true when it's on the device afterwards.
    static var prepareAssets: () async -> Bool = { await Embedder.prepareFieldAssistAssets() }

    private static var running: Task<Void, Never>?
    private static var generation = 0

    /// Bring every installed vault onto the target model — at launch, when the setting changes,
    /// and when the model's asset arrives. A run already going is superseded: it stops at its next
    /// chunk, keeping what it built, and the new run carries on.
    static func start(store: DocumentStore, manifests: @escaping () -> [VaultManifest] = { VaultImporter.installedManifests() },
                      monitor: VaultIndexingMonitor = .shared) {
        generation += 1
        let mine = generation
        running = Task { @MainActor in
            await run(store: store, manifests: manifests(), monitor: monitor) { generation == mine }
            guard generation == mine, Config.fieldAssistContextualSearchEnabled,
                  !target().version.modelId.hasPrefix("nl-contextual") else { return }
            // Switched on but the model isn't here: ask for it, and re-index once it arrives.
            if await prepareAssets(), generation == mine {
                await run(store: store, manifests: manifests(), monitor: monitor) { generation == mine }
            }
        }
    }

    /// One pass over the vaults. Returns each vault's outcome, for the tests.
    @discardableResult
    static func run(store: DocumentStore, manifests: [VaultManifest], monitor: VaultIndexingMonitor,
                    shouldContinue: @escaping () -> Bool = { true }) async -> [String: DocumentStore.UpgradeOutcome] {
        let model = target()
        store.fieldAssistEmbedder = model
        var outcomes: [String: DocumentStore.UpgradeOutcome] = [:]
        for manifest in manifests where manifest.hasDocuments {
            let namespace = DocumentStore.vaultNamespace(manifest.id)
            guard store.documentCount(namespace: namespace) > 0, shouldContinue() else { continue }
            let progress = store.upgradeProgress(namespace: namespace, targetTag: model.version.tag)
            guard progress.done < progress.total || store.servingVersionTag(namespace: namespace) != model.version.tag else {
                outcomes[manifest.id] = .current
                continue
            }
            await VaultOperationLock.withLock(manifest.id) {
                monitor.begin(vaultId: manifest.id, titles: manifest.documents.map(\.title))
                let background = monitor.backgroundTasks.begin(name: "Indexing manuals")
                defer {
                    monitor.backgroundTasks.end(background)
                    monitor.end(vaultId: manifest.id)
                }
                outcomes[manifest.id] = await store.upgradeVaultEmbeddings(
                    namespace: namespace, to: model,
                    progress: { title, done, total in
                        monitor.progress(vaultId: manifest.id, title: title, completed: done, total: total)
                    },
                    shouldContinue: shouldContinue)
            }
        }
        return outcomes
    }
}
