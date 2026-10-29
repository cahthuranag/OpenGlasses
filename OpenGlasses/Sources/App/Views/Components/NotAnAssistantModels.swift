import SwiftUI

/// The models a provider's list offers that can't be the assistant — speech, transcription, live
/// voice, image, embedding and the rest — shown under the chat models in their own section: dimmed,
/// not selectable, each labelled with what it is for. Labelled rather than hidden, so a wearer who
/// knows a model by name can see where it went and why it isn't offered.
struct NotAnAssistantModelsSection: View {
    let models: [ModelFetcher.RemoteModel]

    var body: some View {
        if !models.isEmpty {
            Section {
                ForEach(models) { model in
                    NotAnAssistantModelRow(model: model)
                }
            } header: {
                Text("Can't be your assistant")
            } footer: {
                Text("These models do other jobs, such as speech, transcription or images, so they can't answer as your assistant.")
            }
        }
    }
}

/// One model that can't be chosen as the assistant: its name, its id when that differs, and what
/// it is for. Not a button, so it can't be selected.
struct NotAnAssistantModelRow: View {
    let model: ModelFetcher.RemoteModel

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: OGMetrics.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if model.name != model.id {
                    Text(model.id)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(model.kind.label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: minHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.kind.spokenUnavailableRow(name: model.name))
    }
}
