import AppIntents
import WidgetKit

// MARK: - Configuration Intents (required by AppIntentTimelineProvider)

struct ListenComplicationConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Listen Configuration"
    static var description = IntentDescription("Configure the listen complication.")
}

struct RecordComplicationConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Transcribe Configuration"
    static var description = IntentDescription("Configure the transcribe complication.")
}

struct PhotoComplicationConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Photo Note Configuration"
    static var description = IntentDescription("Configure the photo note complication.")
}
