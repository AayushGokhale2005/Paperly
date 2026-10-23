#if !targetEnvironment(macCatalyst)
import SwiftUI

struct PhoneAudioNoteView: View {
    @State var model: PhoneAudioNoteWorkspace
    let onComplete: (NotebookManifest) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") {
                        model.cancel()
                        onCancel()
                    }
                    .disabled(!model.isRecording && model.phase != .failed)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 12)

                Spacer()
                Image(systemName: model.isRecording ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 68, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.isRecording ? .red : .blue)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(model.status)
                    .font(.title2.bold())
                    .padding(.top, 18)
                Text(model.isRecording ? duration(model.elapsed) : supportingText)
                    .font(model.isRecording ? .system(.title3, design: .monospaced) : .subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 7)

                waveform
                    .frame(height: 150)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 28)

                if model.isRecording {
                    Button {
                        Task {
                            if let manifest = await model.finish() { onComplete(manifest) }
                        }
                    } label: {
                        ZStack {
                            Circle().fill(.red.opacity(0.14)).frame(width: 92, height: 92)
                            RoundedRectangle(cornerRadius: 8).fill(.red).frame(width: 34, height: 34)
                        }
                    }
                    .accessibilityLabel("Stop recording and create notes")
                } else if model.phase == .failed {
                    VStack(spacing: 14) {
                        if let error = model.error {
                            Text(error).font(.callout).foregroundStyle(.red)
                                .multilineTextAlignment(.center).padding(.horizontal, 28)
                        }
                        Button("Try Again") { Task { await model.retry() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView().controlSize(.large)
                    Text("Keep Paperly open while it finishes.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 12)
                }
                Spacer()
            }
        }
        .interactiveDismissDisabled()
        .task { await model.start() }
        .onDisappear { model.cancel() }
    }

    private var waveform: some View {
        Canvas { context, size in
            let count = max(1, model.levels.count)
            let spacing: CGFloat = 3
            let width = max(2, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for (index, level) in model.levels.enumerated() {
                let height = max(5, size.height * CGFloat(level))
                let rect = CGRect(
                    x: CGFloat(index) * (width + spacing),
                    y: (size.height - height) / 2,
                    width: width,
                    height: height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .color(model.isRecording ? .red : .blue))
            }
        }
        .animation(.linear(duration: 0.07), value: model.levels)
        .accessibilityHidden(true)
    }

    private var supportingText: String {
        switch model.phase {
        case .preparing: "Checking microphone and Apple Intelligence"
        case .transcribing: "Whisper is processing the recording on this iPhone"
        case .generating: "Turning the transcript into structured Paperly blocks"
        case .saving: "Creating a new text document"
        case .failed: "Your recording was not saved"
        case .recording: ""
        }
    }

    private func duration(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
#endif
