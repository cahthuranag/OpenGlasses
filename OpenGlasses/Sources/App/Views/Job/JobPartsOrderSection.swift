import SwiftUI

/// A job's parts requests that have not gone yet, and the button that emails them.
///
/// The Jobs list and the day view badge a job whose requests are "waiting to be emailed"; this is
/// where that badge leads. The order is the one `parts_request` action `send` prepares by voice —
/// the same subject, lines and recipients — opened in the composer, and the requests are marked
/// sent only once it goes. Draws nothing when every request on the job has been sent or answered.
struct JobPartsOrderSection: View {
    /// The job; nil draws nothing.
    let sessionId: String?

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var sessions = FieldSessionService.shared
    @State private var problem: String?

    var body: some View {
        if let sessionId, let order = sessions.partsOrder(sessionId: sessionId) {
            Section {
                ForEach(order.requests) { request in
                    Text(order.line(for: request))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    problem = appState.emailPartsOrder(sessionId: sessionId)
                } label: {
                    Text("Email parts request")
                        .frame(maxWidth: .infinity, minHeight: OGMetrics.minTouchTarget, alignment: .leading)
                }
                .accessibilityHint("Opens the order with the parts filled in. Nothing leaves the phone until you tap Send.")
            } header: {
                Text(order.requests.count == 1 ? "Parts request waiting to be emailed"
                     : "\(order.requests.count) parts requests waiting to be emailed")
            } footer: {
                Text("Separate from the job report. A request is marked sent once the order goes.")
            }
            .alert("Can't email the parts request", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) { problem = nil }
            } message: {
                Text(problem ?? "")
            }
        }
    }
}
