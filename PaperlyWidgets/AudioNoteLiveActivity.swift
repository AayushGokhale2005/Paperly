import ActivityKit
import SwiftUI
import WidgetKit

struct AudioNoteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AudioNoteActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: symbol(for: context.state.phase))
                    .font(.title2)
                    .foregroundStyle(tint(for: context.state.phase))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.headline)
                    if context.state.phase == .recording {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text(detail(for: context.state.phase))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if processing(context.state.phase) { ProgressView() }
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.blue)
            .widgetURL(URL(string: "paperly://audio"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: symbol(for: context.state.phase))
                        .font(.title2).foregroundStyle(tint(for: context.state.phase))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .recording {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                    } else if processing(context.state.phase) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: context.state.phase == .complete ? "checkmark" : "exclamationmark")
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(detail(for: context.state.phase))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: symbol(for: context.state.phase))
                    .foregroundStyle(tint(for: context.state.phase))
            } compactTrailing: {
                if context.state.phase == .recording {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption2.monospacedDigit())
                        .frame(width: 42)
                } else {
                    Text(context.state.compactLabel)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
            } minimal: {
                Image(systemName: symbol(for: context.state.phase))
                    .foregroundStyle(tint(for: context.state.phase))
            }
            .widgetURL(URL(string: "paperly://audio"))
            .keylineTint(.blue)
        }
    }

    private func processing(_ phase: AudioNoteActivityAttributes.ContentState.Phase) -> Bool {
        [.transcribing, .generating, .saving].contains(phase)
    }

    private func symbol(for phase: AudioNoteActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .recording: "waveform"
        case .transcribing: "text.viewfinder"
        case .generating: "sparkles"
        case .saving: "arrow.down.doc"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private func tint(for phase: AudioNoteActivityAttributes.ContentState.Phase) -> Color {
        phase == .recording ? .red : phase == .failed ? .orange : .blue
    }

    private func detail(for phase: AudioNoteActivityAttributes.ContentState.Phase) -> String {
        switch phase {
        case .recording: "Paperly is recording in the background."
        case .transcribing: "Whisper is transcribing locally on this iPhone."
        case .generating: "Apple Intelligence is structuring your notes."
        case .saving: "Audio, transcript, and notes are being saved."
        case .complete: "Tap to open the new note."
        case .failed: "Open Paperly to try again."
        }
    }
}
