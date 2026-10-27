import SwiftUI

struct WorkizSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var controller: WorkizController
    @ObservedObject var connection: WorkizConnection
    @ObservedObject private var gate = AdminGate.shared
    @ObservedObject private var profile = OrgProfileManager.shared
    @State private var key = ""
    @State private var problem: String?
    @State private var unlocking = false
    @AppStorage("workizEnabled") private var enabled = true
    @AppStorage("workizReportFieldName") private var fieldName = WorkizWriteBack.defaultFieldName
    @AppStorage("workizClientNotes") private var notes = false
    @AppStorage("workizAccountTimeZone") private var timeZone = TimeZone.current.identifier
    private var canEditKey: Bool { !PolicyEnvelope.isManaged || gate.isSessionLive || gate.isAdministratorPhone }
    var body: some View {
        Form {
            if connection.officeRoute {
                Section { Text("Your office connects to Workiz for you.") }
            } else {
                Section {
                    Toggle("Connect to Workiz", isOn: Binding(get: { connection.enabled }, set: { if !PolicyEnvelope.isLocked(.workizEnabled) { enabled = $0 } }))
                        .disabled(PolicyEnvelope.isLocked(.workizEnabled))
                } footer: {
                    Text("The key can access the whole company. This phone shows only the technician's assigned jobs. Use an expiry and rotate the key when a phone leaves the company.")
                }
                Section {
                    if connection.credential != nil {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "key.fill").accessibilityHidden(true)
                            Text("Key stored on this phone").fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    SecureField("API key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(!canEditKey).accessibilityIdentifier("workiz.key")
                    Button("Save key") {
                        do {
                            try connection.pasteKey(key, administrator: canEditKey)
                            controller.keyChanged()
                            key = ""; problem = nil
                            Task { await appState.syncEngine.flush() }
                        } catch { key = ""; problem = String(localized: "The Workiz key could not be saved. Check administrator access and unlock this phone.") }
                    }.disabled(key.isEmpty || !canEditKey).accessibilityIdentifier("workiz.save")
                    if !canEditKey {
                        if let policy = gate.policy, gate.offersUnlock {
                            Button("Unlock Administrator Settings") { unlocking = true }
                                .sheet(isPresented: $unlocking) { AdminUnlockSheet(gate: gate, policy: policy) }
                        } else { Text("Your administrator must open an administrator session to change this key.").foregroundStyle(.secondary) }
                    }
                    Button { Task { await controller.testConnection() } } label: { Text(controller.testing ? "Testing…" : "Test connection").fixedSize(horizontal: false, vertical: true) }
                        .disabled(!connection.isRunning || controller.testing)
                        .accessibilityIdentifier("workiz.test")
                    if let line = problem ?? connection.problem ?? controller.message ?? controller.connectionMessage { Text(line).accessibilityIdentifier("workiz.message") }
                } header: { Text("Workiz API key") } footer: {
                    Text("In Workiz, open Feature center → Developer API, then Settings → Developer → v2 → Create New API Key. Allow Jobs: Read & Write, Users: Read, Custom fields: Read. Allow Clients: Read & Write only for client notes. Set an expiry. The key stays in this phone's device-only Keychain.")
                }
                if !controller.users.isEmpty || connection.credential?.technicianID != nil {
                    Section("Who are you in Workiz?") {
                        if let name = connection.credential?.technicianName { Text("You're \(name) in Workiz.") }
                        ForEach(controller.users) { user in
                            Button {
                                Task {
                                    do { try await controller.choose(user) }
                                    catch { problem = String(localized: "The technician choice could not be saved.") }
                                }
                            } label: {
                                HStack {
                                    Text(user.name).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    if user.id == connection.credential?.technicianID { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }
                            }.accessibilityIdentifier("workiz.user." + user.id)
                        }
                    }
                }
                Section("What goes back") {
                    TextField("Report field name", text: Binding(get: { connection.fieldName }, set: { if !PolicyEnvelope.isLocked(.workizReportFieldName) { fieldName = String($0.prefix(120)) } }), axis: .vertical)
                        .disabled(PolicyEnvelope.isLocked(.workizReportFieldName))
                    Toggle("Add a client note", isOn: Binding(get: { connection.clientNotes }, set: { if !PolicyEnvelope.isLocked(.workizClientNotes) { notes = $0 } })).disabled(PolicyEnvelope.isLocked(.workizClientNotes))
                    if PolicyEnvelope.isLocked(.workizReportFieldName) || PolicyEnvelope.isLocked(.workizClientNotes) {
                        ManagedLockNote(organization: ManagedLockReason.organization)
                    }
                    Text("Reports contain the work, findings, parts, recommendations, readings and technician identity. Job status stays as it is. Photos and the transcript use your usual report channel.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink {
                        List(TimeZone.knownTimeZoneIdentifiers, id: \.self) { zone in
                            Button { timeZone = zone } label: {
                                HStack {
                                    Text(zone).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    if timeZone == zone { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }
                            }
                        }.navigationTitle("Time zone")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Workiz account time zone").fixedSize(horizontal: false, vertical: true)
                            Text(timeZone).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("workiz.timezone")
                    Text("Use the same time zone as your Workiz account so booked times appear correctly.").font(.footnote)
                }
                if connection.credential != nil {
                    Section { Button(role: .destructive) { controller.remove() } label: { Text("Remove Workiz key").fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.buttonStyle(.plain).foregroundStyle(OGTheme.errorLabel).disabled(!canEditKey).accessibilityIdentifier("workiz.remove") }
                }
            }
        }
        .ogFormStyle().navigationTitle("Workiz")
        .onChange(of: enabled) { _, _ in controller.client.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .orgPolicyDidChange)) { _ in
            key = ""; controller.enforceRoute()
        }
        .onDisappear { key = "" }
    }
}

struct WorkizJobsStatus: View {
    @ObservedObject var controller: WorkizController
    @ObservedObject var store: UpcomingJobStore
    var body: some View {
        if controller.connection.isRunning || store.workizLastPull != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let date = store.workizLastPull { Text("From Workiz at \(date.formatted(date: .omitted, time: .shortened))").font(.caption) }
                if let message = controller.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if let notice = store.workizNotice { Text(notice).font(.caption) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WorkizDeliveryStatus: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var sink: WorkizSyncSink
    let sessionID: String
    init(appState: AppState, sessionID: String) {
        self.appState = appState; self.sessionID = sessionID; sink = appState.workizSink
    }
    var body: some View {
        if let status = appState.workizSink.status(sessionID: sessionID) {
            Section("Workiz") { Text(status).accessibilityIdentifier("workiz.delivery") }
        }
    }
}
