import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showLaunchScreen = true
    @ObservedObject private var manualCapture = ManualCaptureService.shared
    @ObservedObject private var personalCapture = PersonalManualCapture.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MainView()
                // Same reason as the onboarding overlay: the launch screen covers the app for two
                // seconds without covering its accessibility tree, so VoiceOver would start
                // reading a UI the user cannot yet see or touch.
                .accessibilityHidden(showLaunchScreen)

            // Structured-vision result card (vision_assess), presented over the main UI.
            AssessmentCardOverlay()
                .zIndex(0.5)
                .accessibilityHidden(showLaunchScreen)

            if showLaunchScreen {
                LaunchScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            // Show launch screen for 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                    showLaunchScreen = false
                }
            }
        }
        // High-impact action confirmation (prompt-injection backstop). Presented whenever a
        // destructive tool call is awaiting the user's approval in agent mode.
        .toolConfirmation(coordinator: appState.toolConfirmationCoordinator)
        .sheet(item: $manualCapture.request) { request in
            if CapturedManualCatalog.mayUse {
                ManualDocumentCamera(request: request).ignoresSafeArea()
            } else {
                Text("Manual capture is unavailable under the current policy.")
                    .onAppear { manualCapture.cancel() }
            }
        }
        .sheet(item: Binding(get: { personalCapture.request }, set: { value in
            if value == nil, let request = personalCapture.request { personalCapture.cancel(request.id) }
        })) { request in
            if PersonalManualLibrary.canManage { ManualDocumentCamera(request: request).ignoresSafeArea() }
            else { Text("Manual capture is unavailable under the current policy.").onAppear { personalCapture.cancel(request.id) } }
        }
        .task {
            await manualCapture.resume()
            appState.offerPilotReports()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let request = personalCapture.request { personalCapture.cancel(request.id) }
            if phase == .active {
                appState.offerPilotReports()
                Task { await manualCapture.resume() }
            }
        }
    }
}

/// Presents the shared, source-attributed consent card for a pending remote/high-impact action
/// (BN P1) — one surface for agent confirms, gateway capture consent, and assistant tool calls.
private struct ToolConfirmationModifier: ViewModifier {
    @ObservedObject var coordinator: ToolConfirmationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let pending = coordinator.pending {
                RemoteActionConsentView(pending: pending,
                                        respond: { coordinator.resolve($0) },
                                        sendText: { coordinator.resolveText($0) })
                    // The card still arrives; Reduce Motion drops the slide, not
                    // the confirmation.
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: coordinator.pending?.id)
    }
}

private extension View {
    func toolConfirmation(coordinator: ToolConfirmationCoordinator) -> some View {
        modifier(ToolConfirmationModifier(coordinator: coordinator))
    }
}
