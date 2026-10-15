import SwiftUI

/// Settings view for configuring medical platform exports.
/// Accessible from Medical Compliance settings.
struct MedicalExportSettingsView: View {
    @ObservedObject var exportService: MedicalExportService
    @State private var config = FHIRConfigurationStore.shared.configuration
    @State private var selectedPlatform: MedicalPlatform = FHIRConfigurationStore.shared.configuration.platform
    /// Transient editor state. The stored credential is never decrypted back into this field —
    /// once saved, the UI can only report that one exists, replace it, or clear it.
    @State private var tokenDraft = ""
    @State private var isReplacingCredential = false
    @State private var hasStoredCredential = FHIRConfigurationStore.shared.hasStoredCredential()
    @State private var patientIDDraft = ""
    @State private var practitionerIDDraft = ""
    @State private var autoExportEnabled = Config.autoExportEnabled
    @State private var defaultExportFormat: ExportFormat = Config.defaultExportFormat
    @State private var showTestResult = false
    @State private var testResultMessage = ""
    @State private var isTesting = false
    @State private var saveMessage: String?
    /// A device-owner prompt for Clear is on screen; a second tap must not stack another.
    @State private var isAuthorizingClear = false

    private var store: FHIRConfigurationStore { exportService.configurationStore }

    var body: some View {
        List {
            // MARK: - Platform Selection
            Section {
                ForEach(MedicalPlatform.allCases) { platform in
                    Button {
                        selectedPlatform = platform
                        config.platformType = platform.rawValue
                        // Only the platform is saved here. The server address is saved by
                        // Save Configuration, which keeps the credential bound to its address.
                        var saved = store.configuration
                        saved.platformType = platform.rawValue
                        store.save(saved)
                    } label: {
                        HStack(spacing: 12) {
                            Text(platform.flag)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.rawValue)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(platform.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if selectedPlatform == platform {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            } header: {
                Text("Platform")
            } footer: {
                Text("Select your target EMR or health record system. FHIR R4 works with most modern systems including Epic and Cerner.")
            }

            // MARK: - FHIR Configuration (for FHIR-based platforms)
            if selectedPlatform.usesFHIR {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://fhir.example.com/r4", text: $config.baseURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }

                    credentialRow

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patient ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Optional — e.g. 12345", text: $patientIDDraft)
                            .autocapitalization(.none)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Practitioner ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Optional — e.g. dr-smith-001", text: $practitionerIDDraft)
                            .autocapitalization(.none)
                    }

                    Button {
                        saveConfiguration()
                    } label: {
                        Label("Save Configuration", systemImage: "checkmark.circle")
                    }
                    .tint(Color.accentColor)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("FHIR Server")
                } footer: {
                    if selectedPlatform == .epic {
                        Text("Epic uses SMART on FHIR. Obtain a bearer token from your Epic administrator.")
                    } else if selectedPlatform == .cerner {
                        Text("Oracle Health (Cerner) uses FHIR R4 with Millennium platform integration.")
                    } else {
                        Text("Enter the base URL of your FHIR R4 server and an authentication token.")
                    }
                }

                // Test Connection
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!config.isConfigured || isTesting)
                } footer: {
                    Text("Sends a metadata request to verify the FHIR server is reachable and responds to capability queries.")
                }
            }

            // MARK: - Auto Export
            Section {
                Toggle("Auto-Export on Recording Stop", isOn: $autoExportEnabled)
                    .tint(Color.accentColor)
                    .onChange(of: autoExportEnabled) { _, val in
                        Config.autoExportEnabled = val
                    }

                Picker("Default Format", selection: $defaultExportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .onChange(of: defaultExportFormat) { _, val in
                    Config.defaultExportFormat = val
                }
            } header: {
                Text("Automation")
            } footer: {
                if autoExportEnabled && selectedPlatform.usesFHIR {
                    Text("Transcripts will be automatically uploaded to the configured FHIR server when a recording stops. You can also share manually at any time.")
                } else if autoExportEnabled {
                    Text("A share sheet will be presented with the transcript in the selected format when a recording stops.")
                } else {
                    Text("You can still share transcripts manually via the share button or by asking the AI assistant.")
                }
            }

            // MARK: - Manual Share Info
            if selectedPlatform == .manual {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share Sheet")
                                .font(.subheadline)
                            Text("AirDrop, email, Files, or any installed app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Files App")
                                .font(.subheadline)
                            Text("Transcripts saved to Documents/Transcripts folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Command")
                                .font(.subheadline)
                            Text("\"Share the transcript\" or \"Export the recording\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Manual Sharing Options")
                }
            }

            // MARK: - Platform-Specific Notes
            if !selectedPlatform.usesFHIR && selectedPlatform != .manual {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Coming Soon", systemImage: "clock.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.accentColor)

                        Text(platformNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("For now, use FHIR R4 or Manual Share to export transcripts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Medical Export")
        .ogFormStyle()
        .onAppear(perform: loadProtectedValues)
        .alert("Connection Test", isPresented: $showTestResult) {
            Button("OK") {}
        } message: {
            Text(testResultMessage)
        }
    }

    // MARK: - Credential

    /// A stored credential is reported, never rendered. Entry is only offered when there is
    /// nothing stored, or after the user explicitly asks to replace what is.
    @ViewBuilder
    private var credentialRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bearer Token")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasStoredCredential && !isReplacingCredential {
                HStack(spacing: 12) {
                    Label("Credential stored", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Replace") {
                        tokenDraft = ""
                        isReplacingCredential = true
                    }
                    .buttonStyle(.borderless)
                    Button("Clear", role: .destructive) {
                        clearCredential()
                    }
                    .buttonStyle(.borderless)
                    .disabled(isAuthorizingClear)
                }
                Text("Kept only on this phone. Clearing it asks for Face ID, Touch ID or your passcode, and also deletes any exports still waiting to be shared.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                SecretInputField(placeholder: "Pre-obtained OAuth token", text: $tokenDraft)
            }
        }
    }

    /// Clearing needs the device owner: fail-closed, so a cancelled or unavailable prompt clears
    /// nothing, and the row says so rather than looking as if it worked.
    private func clearCredential() {
        guard !isAuthorizingClear else { return }
        isAuthorizingClear = true
        OwnerGateAuth.authorize(reason: String(localized: "Clear the FHIR credential and pending exports")) { authorization in
            Task { @MainActor in
                isAuthorizingClear = false
                let outcome = exportService.clearCredentialAndPendingExports(authorization: authorization)
                if outcome.didClear {
                    tokenDraft = ""
                    hasStoredCredential = false
                    isReplacingCredential = false
                }
                saveMessage = outcome.message
            }
        }
    }

    // MARK: - Helpers

    private var platformNote: String {
        switch selectedPlatform {
        case .myHealthRecord:
            return "My Health Record integration requires registration with the Australian Digital Health Agency and a conformant FHIR gateway. Contact your ADHA representative."
        case .nzHealthConnect:
            return "NZ Health Connect integration requires a Health Information Platform (HIP) connector. Contact your PHO or DHB IT team."
        case .nhsSpine:
            return "NHS Spine integration requires an NHS Digital connection agreement and MESH mailbox. Contact your trust's IT department."
        default:
            return ""
        }
    }

    /// Clinical identifiers are editable, so they are loaded back into their fields; the
    /// credential deliberately is not.
    private func loadProtectedValues() {
        // @State initializers cannot reach `exportService`, so the injected store is the authority
        // from here on — it and the singleton are the same object outside tests.
        config = store.configuration
        selectedPlatform = config.platform
        hasStoredCredential = store.hasStoredCredential()
        guard let context = try? store.loadPrivateContext() else { return }
        patientIDDraft = context.patientID ?? ""
        practitionerIDDraft = context.practitionerID ?? ""
    }

    private func saveConfiguration() {
        let outcome = exportService.saveServerSettings(
            config,
            enteredCredential: tokenDraft,
            privateContext: FHIRPrivateContext(patientID: patientIDDraft, practitionerID: practitionerIDDraft)
        )
        if case .saved(let storedCredential) = outcome, storedCredential {
            tokenDraft = ""
            isReplacingCredential = false
            hasStoredCredential = true
        }
        saveMessage = outcome.message
    }

    /// The service decides which credential, if any, the test may send: the stored one goes only
    /// to the address it was saved with (`FHIRConnectionTestPolicy`).
    private func testConnection() {
        isTesting = true
        let baseURL = config.baseURL
        let entered = tokenDraft
        Task {
            testResultMessage = await exportService.testConnection(baseURL: baseURL, enteredCredential: entered)
            showTestResult = true
            isTesting = false
        }
    }
}
