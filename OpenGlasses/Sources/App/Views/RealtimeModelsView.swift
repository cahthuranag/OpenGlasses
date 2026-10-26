import SwiftUI

struct RealtimeModelForm: View {
    @Binding var configuration: RealtimeModelConfig
    @State private var testingSession: RealtimeProviderSession?
    @State private var testTask: Task<Void, Never>?
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var regionDrafts = ModelStudioRegionDrafts()

    var body: some View {
        Section {
            TextField("Display Name", text: $configuration.name)
            Picker("Provider", selection: Binding(get: { configuration.providerID }, set: applyTemplate)) {
                ForEach(RealtimeProviderCatalog.templates) { template in
                    Text(LocalizedStringKey(template.name)).tag(template.id)
                }
            }
            .accessibilityIdentifier("realtime.provider")
            if let template = RealtimeProviderCatalog.template(configuration.providerID),
               ModelStudioRegion.region(of: template.endpoint) != nil,
               let region = ModelStudioRegion.region(of: configuration.endpoint) {
                Picker("Region", selection: Binding(get: { region }, set: { switchRegion(from: region, to: $0) })) {
                    ForEach(ModelStudioRegion.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("realtime.region")
            }
            if configuration.providerID == "compatible" || configuration.profile == nil
                || RealtimeProviderCatalog.profiles(for: configuration.providerID).count > 1 {
                Picker("Protocol", selection: $configuration.profileID) {
                    if configuration.profile == nil { Text(String(localized: "Unsupported version")).tag(configuration.profileID) }
                    ForEach(RealtimeProviderCatalog.profiles(for: configuration.providerID)) { profile in Text(profile.title).tag(profile.rawValue) }
                }
            } else {
                LabeledContent("Protocol", value: configuration.profile?.title ?? String(localized: "Unsupported version"))
            }
        } header: { Text("Realtime model") }

        Section {
            TextField("WebSocket endpoint", text: $configuration.endpoint)
                .accessibilityIdentifier("realtime.endpoint")
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecretInputField(placeholder: String(localized: "API key"), text: $configuration.apiKey)
            TextField("Model ID", text: $configuration.model)
                .accessibilityIdentifier("realtime.model")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if configuration.profile?.mediaPolicy.usesVoiceSetting == true {
                TextField("Voice", text: $configuration.voice)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: { Text("Connection") }
        footer: { Text(RealtimeProviderCatalog.template(configuration.providerID)?.help ?? String(localized: "Choose a supported protocol version.")) }

        Section {
            if let capabilities = configuration.capabilities {
                LabeledContent("Images", value: capabilities.vision ? String(localized: "Supported") : String(localized: "Unavailable"))
                LabeledContent("App context updates", value: capabilities.contextUpdate ? String(localized: "Supported") : String(localized: "Unavailable"))
                LabeledContent("Text turns", value: capabilities.textTurn ? String(localized: "Supported") : String(localized: "Unavailable"))
                LabeledContent("Speak supplied text", value: capabilities.suppliedSpeech ? String(localized: "Supported") : String(localized: "Unavailable"))
            }
            Text("Credentials and endpoints are stored in Keychain. Changes apply to the next session. Test Connection checks setup; test audio in a conversation next.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(testingSession == nil ? String(localized: "Test Connection") : String(localized: "Connecting…")) { testConnection() }
                .disabled(testingSession != nil || !configuration.isConfigured)
            if let testResult { OGStatusLabel(testResult, kind: testSucceeded ? .ok : .error) }
        }
        .onChange(of: configuration) { _, _ in
            testTask?.cancel()
            testingSession?.disconnect()
            testingSession = nil
            testResult = nil
        }
        .onDisappear { testTask?.cancel(); testingSession?.disconnect(); testingSession = nil }
    }
    private func applyTemplate(_ id: String) {
        guard let template = RealtimeProviderCatalog.template(id) else { return }
        testTask?.cancel()
        testingSession?.disconnect()
        testingSession = nil
        testResult = nil
        let existingID = configuration.id
        let existingName = configuration.name
        let previousDefaultName = RealtimeProviderCatalog.template(configuration.providerID)?.name
        let previousRegion = ModelStudioRegion.region(of: configuration.endpoint)
        configuration = template.modelConfiguration()
        configuration.id = existingID
        // Moving between Qwen services keeps the chosen region; workspace and key start fresh.
        if let previousRegion { configuration.endpoint = ModelStudioRegion.endpoint(template.endpoint, in: previousRegion) }
        regionDrafts = ModelStudioRegionDrafts()
        if !existingName.isEmpty, existingName != previousDefaultName { configuration.name = existingName }
        // Speech and chat credentials can belong to different services. Never carry a key
        // from the previous provider across a template change.
    }
    private func switchRegion(from: ModelStudioRegion, to: ModelStudioRegion) {
        guard from != to, let template = RealtimeProviderCatalog.template(configuration.providerID) else { return }
        let draft = regionDrafts.switchRegion(from: from, to: to,
                                              current: .init(endpoint: configuration.endpoint, apiKey: configuration.apiKey),
                                              templateEndpoint: template.endpoint)
        configuration.endpoint = draft.endpoint
        configuration.apiKey = draft.apiKey
    }
    private func testConnection() {
        let session = RealtimeProviderSession(model: configuration)
        testingSession = session
        testResult = nil
        session.configure(systemInstruction: "Connection test.", toolDeclarations: [])
        testTask = Task { @MainActor in
            let ready = await session.connect()
            guard !Task.isCancelled else { return }
            testSucceeded = ready
            if ready { testResult = String(localized: "Authenticated session ready. Test microphone audio, replies and tools in a live conversation next.") }
            else if case .error(let message) = session.connectionState { testResult = message }
            else { testResult = String(localized: "The service did not finish session setup. Check the model settings.") }
            session.disconnect()
            testingSession = nil
        }
    }
}

struct RealtimeModelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: RealtimeModelConfig
    @State private var errorMessage: String?
    let onSave: (RealtimeModelConfig) -> Bool
    init(model: RealtimeModelConfig, onSave: @escaping (RealtimeModelConfig) -> Bool) {
        _configuration = State(initialValue: model)
        self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                RealtimeModelForm(configuration: $configuration)
                if let errorMessage { OGStatusLabel(errorMessage, kind: .error) }
            }
            .ogFormStyle()
            .navigationTitle("Realtime Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            _ = try configuration.request()
                            if onSave(configuration) { dismiss() }
                            else { errorMessage = String(localized: "Couldn't save the model to Keychain.") }
                        }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
    }
}

struct RealtimeModelsView: View {
    @State private var models = Config.savedRealtimeModels
    @State private var editingModel: RealtimeModelConfig?
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section {
                ForEach(models) { model in
                    Button { editingModel = model } label: {
                        VStack(alignment: .leading) {
                            Text(model.name).foregroundStyle(.primary)
                            Text(model.profile?.title ?? String(localized: "Unsupported protocol version")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    var updated = models; updated.remove(atOffsets: offsets)
                    if Config.setSavedRealtimeModels(updated) { models = updated }
                    else { errorMessage = String(localized: "Couldn't save the model list to Keychain.") }
                }
                Button { editingModel = RealtimeProviderCatalog.templates[0].modelConfiguration() } label: {
                    Label("Add Realtime Model", systemImage: "plus.circle")
                }
            } footer: { Text("Select a saved model from the conversation's Realtime model picker.") }
            if let errorMessage { OGStatusLabel(errorMessage, kind: .error) }
        }
        .navigationTitle("Realtime Models")
        .ogFormStyle()
        .onAppear { Config.migrateRealtimeModelsIfNeeded(); models = Config.savedRealtimeModels }
        .sheet(item: $editingModel) { model in
            RealtimeModelEditorView(model: model) { saved in
                var updated = models
                if let index = updated.firstIndex(where: { $0.id == saved.id }) { updated[index] = saved }
                else { updated.append(saved) }
                guard Config.setSavedRealtimeModels(updated) else { return false }
                models = updated
                return true
            }
        }
    }
}
