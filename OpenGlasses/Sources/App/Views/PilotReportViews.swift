import SwiftUI

struct PilotReportOffer: View {
    let days: [Date]
    let send: (Date) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(days.count == 1 && days.first.map { Calendar.current.isDateInYesterday($0) } == true
                 ? "Yesterday's report is ready" : "Pilot reports are ready")
                .font(.headline)
            if days.count == 1, let day = days.first {
                Button("Review and Send — \(day.formatted(date: .abbreviated, time: .omitted))") { send(day) }
            } else {
                Menu("Review a day…") {
                    ForEach(days, id: \.self) { day in
                        Button(day.formatted(date: .abbreviated, time: .omitted)) { send(day) }
                    }
                }
            }
            Button("Not now", action: dismiss)
                .font(.footnote)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
        .accessibilityElement(children: .contain)
    }
}

struct PilotReportSettings: View {
    @ObservedObject var appState: AppState
    @AppStorage("pilotReportsEnabled") private var enabled = false
    @State private var addresses = ""

    private var parsed: [String] {
        addresses.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
    var body: some View {
        OGSection(header: "Pilot reports",
                  footer: "On the first open after a day with activity, offers that day's conversations, jobs, AI turn details and app events. Company and technician details are included; keys are masked. You review the file and send it yourself. You can always turn this off.") {
            Toggle("Pilot reports", isOn: $enabled)
                .padding(14)
                .onChange(of: enabled) { _, on in
                    if !on { appState.pilotReportDays = [] }
                }
            if enabled {
                TextField("Send to (up to three addresses, separated by commas)", text: $addresses)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .onChange(of: addresses) { _, _ in
                        if let checked = PilotReportRecipients.validated(parsed) {
                            UserDefaults.standard.set(checked, forKey: "pilotReportRecipients")
                        } else {
                            UserDefaults.standard.removeObject(forKey: "pilotReportRecipients")
                        }
                    }
                if PilotReportRecipients.validated(parsed) == nil {
                    Text("Enter one to three valid email addresses. Reports won't be offered until these are valid.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            addresses = (PilotReportStore.shared.recipients ?? []).joined(separator: ", ")
        }
    }
}

/// Unlock only after a tap; building the list must not raise Face ID on every Settings visit.
struct ActivityDayMenu: View {
    @ObservedObject var appState: AppState
    @ObservedObject var store: ConversationStore
    @State private var unlocked = false

    var body: some View {
        if store.isLocked && !unlocked {
            Button("Unlock to Send a Day's Activity…") {
                Task { unlocked = await store.unlock() }
            }.padding(14)
        } else {
            Menu {
                ForEach(appState.reportActivityDays) { entry in
                    Button(entry.day.formatted(date: .abbreviated, time: .omitted) + " — " + entry.summary) {
                        appState.openSupportReport(.day(entry.day))
                    }
                }
                if appState.reportActivityDays.isEmpty { Text("No activity in the last 14 days") }
            } label: {
                OGRow("Send a Day's Activity…", icon: "calendar", subtitle: "Choose an earlier day to review")
            }
        }
    }
}
