import SwiftUI

@main
struct OpenGlassesWatchApp: App {
    /// Owned here, not by the view, so the session with the phone is up whenever the app runs —
    /// including a launch in the background to take a status update, where no view is drawn.
    @StateObject private var connectivity = WatchConnectivityService()

    var body: some Scene {
        WindowGroup {
            WatchMainView(connectivity: connectivity)
        }
    }
}
