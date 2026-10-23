#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacRecordingView: View {
    @State var model: MacRecordingWorkspace
    let addNotes: ([TextBlock], UUID) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: NotebookRecording?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: model.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(model.isRecording ? .red : .blue)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.isRecording ? "Recording" : "Record a conversation")
                                    .font(.headline)
                                Text(model.isRecording ? duration(model.elapsed) : "Audio stays in this Paperly document.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(model.isRecording ? "Stop" : "Record",
                                   systemImage: model.isRecording ? "stop.fill" : "record.circle") {
                                Task {
                                    if model.isRecording { await model.stopRecording() }
                                    else { await model.startRecording() }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(model.isRecording ? .red : .blue)
                        }
                        if let activity = model.activity {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(activity).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    if model.recordings.isEmpty {
                        ContentUnavailableView(
                            "No recordings",
                            systemImage: "waveform",
                            description: Text("Start a recording above. Paperly can transcribe it locally with Whisper afterward.")
                        )
                    } else {
                        ForEach(model.recordings) { recording in
                            recordingRow(recording)
                        }
                    }
                } header: {
                    Text("Saved recordings")
                } footer: {
                    Text("The first transcription downloads the Whisper base model. Transcription then runs locally. Generated notes use Apple Intelligence on this Mac.")
                }
            }
            .navigationTitle("Audio notes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(model.isRecording)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 500)
        .task { await model.load() }
        .alert("Audio notes", isPresented: Binding(
            get: { model.error != nil },
            set: { if !$0 { model.error = nil } }
        )) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        .confirmationDialog(
            "Delete recording?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Recording", role: .destructive) {
                guard let recording = deleting else { return }
                deleting = nil
                Task { await model.delete(recording) }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The audio and its transcript will be removed from this document.")
        }
    }

    private func recordingRow(_ recording: NotebookRecording) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.togglePlayback(recording) }
            } label: {
                Image(systemName: model.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.playingID == recording.id ? "Stop playback" : "Play recording")

            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(duration(recording.duration))
                    Text("•")
                    Text(recording.createdAt, style: .date)
                    if recording.transcriptFile != nil {
                        Text("•")
                        Label("Transcribed", systemImage: "checkmark.circle.fill")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if recording.transcriptFile == nil {
                Button("Transcribe & Create Notes") {
                    Task {
                        await model.transcribe(recording)
                        guard let transcribed = model.recordings.first(where: { $0.id == recording.id }),
                              transcribed.transcriptFile != nil,
                              let blocks = await model.generateNotes(transcribed),
                              await addNotes(blocks, recording.id) else { return }
                        await model.markNotesAdded(recording.id)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                    .disabled(model.busyRecordingID != nil || model.isRecording)
            } else {
                Button(recording.notesAddedAt == nil ? "Create notes" : "Add notes again") {
                    Task {
                        guard let blocks = await model.generateNotes(recording),
                              await addNotes(blocks, recording.id) else { return }
                        await model.markNotesAdded(recording.id)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busyRecordingID != nil || model.isRecording)
            }
            Menu {
                Button("Delete recording", systemImage: "trash", role: .destructive) { deleting = recording }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Recording options")
        }
        .opacity(model.busyRecordingID == nil || model.busyRecordingID == recording.id ? 1 : 0.55)
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
