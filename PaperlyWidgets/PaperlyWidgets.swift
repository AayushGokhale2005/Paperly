import SwiftUI
import WidgetKit

@main
struct PaperlyWidgetBundle: WidgetBundle {
    var body: some Widget {
        PaperlyQuickActionsWidget()
        PaperlyAudioWidget()
        AudioNoteLiveActivity()
    }
}

private struct PaperlyEntry: TimelineEntry {
    let date: Date
}

private struct PaperlyProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaperlyEntry { PaperlyEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (PaperlyEntry) -> Void) {
        completion(PaperlyEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PaperlyEntry>) -> Void) {
        completion(Timeline(entries: [PaperlyEntry(date: Date())], policy: .never))
    }
}

struct PaperlyQuickActionsWidget: Widget {
    let kind = "PaperlyQuickActions"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaperlyProvider()) { _ in
            PaperlyQuickActionsView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Paperly")
        .description("Create a text document or audio note.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PaperlyQuickActionsView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "waveform.badge.mic")
                    .font(.title).foregroundStyle(.blue)
                Spacer()
                Text("Audio note").font(.headline)
                Text("Record and create notes").font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "paperly://audio"))
        } else {
            HStack(spacing: 12) {
                action("Text", symbol: "doc.badge.plus", url: "paperly://new-text")
                action("Audio", symbol: "waveform.badge.mic", url: "paperly://audio")
                action("Workspace", symbol: "books.vertical", url: "paperly://workspace")
            }
        }
    }

    private func action(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(.blue)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct PaperlyAudioWidget: Widget {
    let kind = "PaperlyAudio"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaperlyProvider()) { _ in
            Image(systemName: "waveform.badge.mic")
                .font(.title2)
                .foregroundStyle(.blue)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "paperly://audio"))
                .accessibilityLabel("Create a Paperly audio note")
        }
        .configurationDisplayName("Audio Note")
        .description("Start a new Paperly audio note.")
        .supportedFamilies([.accessoryCircular])
    }
}
