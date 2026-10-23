import SwiftUI

struct TextDocumentEditorView: View {
    @State var model: TextDocumentViewModel
    var incomingImportID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var share: ShareItem?
    @State private var closing = false
    @State private var exporting = false
    @FocusState private var titleFocused: Bool
#if targetEnvironment(macCatalyst)
    @State private var recordingWorkspace: MacRecordingWorkspace?
#endif

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = model.error {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                                Button("Retry") { Task { if model.loading { await model.load() } else { _ = await model.flush() } } }
                            }
                        }
                        TextField("Untitled document", text: Binding(get: { model.title }, set: { model.setTitle($0) }), axis: .vertical)
                            .font(.largeTitle.bold()).accessibilityLabel("Document title").focused($titleFocused)
                            .submitLabel(.next).onSubmit { model.focusedBlock = model.content.blocks.first?.id }
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(model.content.blocks.enumerated()), id: \.element.id) { index, block in
                                blockRow(block, index: index).id(block.id)
                            }
                        }
                        Menu {
                            ForEach(TextBlockKind.allCases, id: \.self) { kind in
                                Button(kind.title, systemImage: kind.symbol) { model.insert(after: model.content.blocks.last?.id, kind: kind) }
                            }
                        } label: { Label("Add block", systemImage: "plus").frame(minHeight: 44) }
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 700, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 80)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.focusedBlock) { _, id in
                    guard let id else { return }
                    if reduceMotion { proxy.scrollTo(id, anchor: .center) }
                    else { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            .disabled(model.loading)
            .overlay { if model.loading { ProgressView("Opening document…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { close() } label: { Label("Workspace", systemImage: "chevron.left") }.disabled(closing) }
#if targetEnvironment(macCatalyst)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        recordingWorkspace = MacRecordingWorkspace(repository: model.repository, notebookID: model.manifest.id)
                    } label: {
                        Label("Audio notes", systemImage: "waveform.badge.mic")
                    }
                    .disabled(model.loading || model.dirty || model.saving)
                }
#endif
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
                        Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
                        Section("Export") {
                            Button("Markdown", systemImage: "doc.plaintext") { export(markdown: true) }
                            Button("Editable Paperly document", systemImage: "square.and.arrow.up") { export(markdown: false) }
                        }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Document options").disabled(model.loading || exporting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Menu {
                        ForEach(TextBlockKind.allCases, id: \.self) { kind in
                            Button(kind.title, systemImage: kind.symbol) {
                                if let id = model.focusedBlock { model.setKind(id, kind) }
                            }
                        }
                    } label: { Label("Style", systemImage: "textformat") }.disabled(model.focusedBlock == nil)
                    Button { model.insert(after: model.focusedBlock) } label: { Image(systemName: "plus") }.accessibilityLabel("Insert block")
                    Spacer()
                    Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).accessibilityLabel("Undo")
                    Button("Done") {
                        model.focusedBlock = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .task { await model.load() }
        .onChange(of: titleFocused) { _, focused in if focused { model.focusedBlock = nil } }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
#if targetEnvironment(macCatalyst)
        .sheet(item: $recordingWorkspace) { workspace in
            MacRecordingView(model: workspace) { blocks, _ in
                model.appendGeneratedNotes(blocks)
                return await model.flush()
            }
        }
#endif
        .interactiveDismissDisabled(model.dirty || model.loading)
        .onChange(of: incomingImportID) { _, id in if id != nil { close() } }
        .onChange(of: phase) { _, value in
            guard value != .active else { return }
            let task = UIApplication.shared.beginBackgroundTask(withName: "Save text document", expirationHandler: nil)
            Task { _ = await model.flush(); UIApplication.shared.endBackgroundTask(task) }
        }
    }
    private func blockRow(_ block: TextBlock, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if block.kind == .checklist {
                Button { model.toggle(block.id) } label: { Image(systemName: block.checked ? "checkmark.square.fill" : "square").frame(width: 44, height: 44) }
                    .accessibilityLabel(block.checked ? "Mark incomplete" : "Complete task")
            } else if block.kind == .bullet {
                Image(systemName: "circle.fill").font(.system(size: 5)).frame(width: 24, height: 44).accessibilityHidden(true)
            } else if block.kind == .numbered {
                Text("\(listNumber(at: index)).").monospacedDigit().frame(minWidth: 24, minHeight: 44, alignment: .topTrailing).padding(.top, 10).accessibilityHidden(true)
            } else if block.kind == .quote {
                Image(systemName: "quote.opening").foregroundStyle(.secondary).frame(width: 24, height: 44).accessibilityHidden(true)
            }
            ZStack(alignment: .topLeading) {
                if block.text.isEmpty {
                    Text(block.kind == .paragraph ? "Write something…" : block.kind.title).font(.body).foregroundStyle(.tertiary)
                        .padding(.top, 8).allowsHitTesting(false).accessibilityHidden(true)
                }
                BlockTextView(block: block, focused: model.focusedBlock == block.id,
                    onChange: { model.setText(block.id, $0) }, onFocus: { model.focusedBlock = block.id },
                    onBlur: { if model.focusedBlock == block.id { model.focusedBlock = nil } },
                    onSplit: { model.split(block.id, atUTF16: $0.location, replacing: $0.length) },
                    onDeleteEmpty: { model.delete(block.id) })
            }
            Menu {
                Section("Turn into") {
                    ForEach(TextBlockKind.allCases, id: \.self) { kind in
                        Button(kind.title, systemImage: kind.symbol) { model.setKind(block.id, kind) }
                    }
                }
                Button("Insert below", systemImage: "plus") { model.insert(after: block.id) }
                Button("Move up", systemImage: "arrow.up") { model.move(block.id, by: -1) }.disabled(index == 0)
                Button("Move down", systemImage: "arrow.down") { model.move(block.id, by: 1) }.disabled(index == model.content.blocks.count - 1)
                Button("Delete block", systemImage: "trash", role: .destructive) { model.delete(block.id) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(.tertiary).frame(width: 44, height: 44) }
            .accessibilityLabel("Block \(index + 1) options")
        }
        .padding(.top, block.kind == .heading1 || block.kind == .heading2 ? 16 : 0)
        .padding(.horizontal, block.kind == .code ? 12 : 0)
        .background(block.kind == .code ? Color(uiColor: .secondarySystemBackground) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
    private func listNumber(at index: Int) -> Int {
        var first = index
        while first > 0 && model.content.blocks[first - 1].kind == .numbered { first -= 1 }
        return index - first + 1
    }
    private func close() {
        if model.loading { dismiss(); return }
        guard !closing else { return }; closing = true
        Task { if await model.flush() { dismiss() }; closing = false }
    }
    private func export(markdown: Bool) {
        exporting = true
        Task {
            defer { exporting = false }
            guard await model.flush() else { return }
            do {
                let data = markdown ? Data(model.content.markdown(title: model.title).utf8) : try await model.repository.exportData(model.manifest.id)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Document-\(UUID()).\(markdown ? "md" : "paperly")")
                try await Task.detached { try data.write(to: url, options: .atomic) }.value
                share = ShareItem(url: url)
            } catch { model.error = error.localizedDescription }
        }
    }
}
