import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

struct NotebookEditorView: View {
    @State private var session: NotebookSession
    let incomingImportID: UUID?
    private var model: EditorViewModel { session.active }
    init(model: EditorViewModel, incomingImportID: UUID? = nil, initialPageID: UUID? = nil) {
        if let initialPageID, let index = model.manifest.pages.firstIndex(where: { $0.id == initialPageID }) { model.pageIndex = index }
        _session = State(initialValue: NotebookSession(model)); self.incomingImportID = incomingImportID
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var share: ShareItem?
    @State private var showingPages = false
    @State private var showingSearchText = false
    @State private var showingPenSettings = false
    @State private var importingImage = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingPhotos = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: sizeClass == .compact ? 4 : 16) {
                Button { Task { if await session.flushAll() { dismiss() } } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Back to library")
                Text(model.manifest.title).font(.headline).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    if sizeClass != .compact { Button { session.go(to: session.activeIndex - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(session.activeIndex == 0) }
                    Button("\(session.activeIndex + 1) / \(session.manifest.pages.count)") { showingPages = true }.monospacedDigit().frame(minWidth: 70, minHeight: 44)
                    if sizeClass != .compact { Button { session.go(to: session.activeIndex + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(session.activeIndex == session.manifest.pages.count - 1) }
                }.background(.quaternary, in: Capsule())
                Spacer()
                Menu {
                    Button("Searchable handwriting", systemImage: "text.magnifyingglass") {
                        Task { if await session.flushAll() { showingSearchText = true } }
                    }
                    Button("Add page", systemImage: "plus") { session.addPage() }
                    Button("Fit page", systemImage: "arrow.down.right.and.arrow.up.left") { session.zoomResetRevision += 1 }
                    Picker("Page view", selection: Binding(get: { model.preferences.pagePresentation }, set: { model.preferences.pagePresentation = $0 })) {
                        ForEach(PagePresentation.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Page scrolling", selection: Binding(get: { model.pageScrollDirection }, set: { model.pageScrollDirection = $0 })) {
                        ForEach(PageScrollDirection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Apple Pencil only", isOn: Binding(get: { model.pencilOnly }, set: { model.pencilOnly = $0 }))
                    Button("Export editable notebook", systemImage: "square.and.arrow.up") { export(pdf: false) }
                    Button("Export PDF", systemImage: "doc.richtext") { export(pdf: true) }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(.quaternary, in: Circle()) }.accessibilityLabel("Notebook options")
            }.padding(.horizontal, 16).padding(.vertical, 8)
            ContinuousNotebookView(session: session, resetRevision: session.zoomResetRevision)

        }
        .safeAreaInset(edge: .bottom, spacing: 0) { toolbar.padding(.vertical, 8) }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
        .task { await session.start() }
        .onChange(of: incomingImportID) { _, id in
            if id != nil { Task { if await session.flushAll() { dismiss() } } }
        }
        .onChange(of: phase) { _, value in
            if value != .active, model.canvas != nil {
                let background = UIApplication.shared.beginBackgroundTask(withName: "Finish page save", expirationHandler: nil)
                Task { await session.flushAll(); UIApplication.shared.endBackgroundTask(background) }
            }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            Task {
                do {
                    if let data = try await selection.loadTransferable(type: Data.self) { model.insertImage(data) }
                    else { model.error = "This photo could not be opened." }
                } catch { model.error = error.localizedDescription }
                photoSelection = nil
            }
        }
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try await Task.detached {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
                            return try Data(contentsOf: url)
                        }.value
                        model.insertImage(data)
                    } catch { model.error = error.localizedDescription }
                }
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $showingSearchText) {
            SearchableHandwritingView(repository: model.repository, notebook: session.manifest.id,
                page: model.page.id, pageNumber: session.activeIndex + 1) { manifest in
                session.manifest = manifest
                for pageModel in session.models.values { pageModel.manifest = manifest }
            }
        }
        .sheet(isPresented: $showingPages) {
            NavigationStack {
                List(Array(session.manifest.pages.enumerated()), id: \.element.id) { index, page in
                    Button { session.go(to: index); showingPages = false } label: {
                        HStack(spacing: 16) {
                            PageThumbnail(repository: model.repository, notebook: model.manifest.id, page: page)
                            Label("Page \(index + 1) · \(page.template.rawValue.capitalized)", systemImage: index == session.activeIndex ? "checkmark.circle.fill" : "doc")
                        }
                    }
                }.navigationTitle("Pages").toolbar { Button("Done") { showingPages = false } }
            }
        }
        .alert("Paperly", isPresented: Binding(get: { session.error != nil || model.error != nil }, set: { if !$0 { session.error = nil; model.error = nil } })) {
            Button("Retry") {
                session.error = nil; model.error = nil
                Task { await session.retry() }
            }
            Button("OK", role: .cancel) { session.error = nil; model.error = nil }
        } message: { Text(session.error ?? model.error ?? "") }
    }
    private var toolbar: some View {
        VStack(spacing: 6) {
            if model.tool == .image { imageActions }
            if sizeClass == .compact {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 2) { tools; clipboard; history } }
                ScrollView(.horizontal, showsIndicators: false) { colors }
            } else { ViewThatFits {
                HStack(spacing: 6) { tools; Divider().frame(height: 28); colors; Divider().frame(height: 28); clipboard; history }
                VStack(spacing: 0) { HStack { tools; clipboard; history }; HStack { colors } }
            } }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: sizeClass == .compact ? 18 : 40))
        .padding(.horizontal)
    }
    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(DrawingTool.allCases.filter { $0 != .image }, id: \.self) { tool in
                Button {
                    if tool == .pen && model.tool == .pen { showingPenSettings = true }
                    else { model.tool = tool }
                } label: {
                    Image(systemName: tool.symbol).font(.title3).frame(width: 44, height: 44)
                        .background(model.tool == tool ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }.accessibilityLabel(tool == .pen ? "Pen · \(model.penStyle.rawValue). Tap again for settings" : tool.rawValue.capitalized)
                    .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.tool)
                    .popover(isPresented: Binding(get: { tool == .pen && showingPenSettings }, set: { if !$0 { showingPenSettings = false } })) {
                        PenSettingsView(model: model).presentationCompactAdaptation(.sheet)
                    }
            }
            Menu {
                Button("Select and move images", systemImage: "hand.draw") { model.tool = .image }
                Button("Insert from Files", systemImage: "folder") { importingImage = true }
                Button("Insert from Photos", systemImage: "photo.on.rectangle") { showingPhotos = true }
                Button("Paste", systemImage: "doc.on.clipboard") { paste(image: true) }
            } label: {
                Image(systemName: "photo").font(.title3).frame(width: 44, height: 44)
                    .background(model.tool == .image ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityLabel("Image options").disabled(model.loading || model.importingImage)
        }
    }
    private var colors: some View {
        HStack(spacing: 2) {
            ForEach([Color.black, .blue, .red, .green, .purple], id: \.self) { color in
                Button { model.color = color } label: {
                    Circle().fill(color).frame(width: 23, height: 23)
                        .padding(4).overlay(Circle().stroke(model.color == color ? Color.accentColor : .clear, lineWidth: 2)).frame(width: 44, height: 44)
                }.accessibilityLabel(color.description + " ink")
            }
            Menu {
                ForEach([1.0, 3, 5, 8], id: \.self) { width in Button("\(Int(width)) pt") { model.width = width } }
                ColorPicker("Custom ink", selection: Binding(get: { model.color }, set: { model.color = $0 }))
            } label: { Image(systemName: "lineweight").frame(width: 44, height: 44) }.accessibilityLabel("Stroke width and custom color")
        }
    }
    private var history: some View {
        HStack(spacing: 0) {
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }.accessibilityLabel("Undo").disabled(!model.canUndo || model.importingImage)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }.accessibilityLabel("Redo").disabled(!model.canRedo || model.importingImage)
        }
    }
    private var clipboard: some View {
        Menu {
            Button("Copy selection", systemImage: "doc.on.doc") {
                if model.selectedImage != nil { model.copySelectedImage() }
                else { (model.canvas as? PaperlyCanvasView)?.copySelection() }
            }
            Button("Cut selection", systemImage: "scissors") {
                if model.selectedImage != nil { model.copySelectedImage(cut: true) }
                else { (model.canvas as? PaperlyCanvasView)?.copySelection(cut: true) }
            }
            Button("Paste", systemImage: "doc.on.clipboard") { paste() }
        } label: { Image(systemName: "doc.on.clipboard").frame(width: 44, height: 44) }
            .accessibilityLabel("Copy, cut and paste").disabled(model.loading || model.importingImage)
    }
    private var imageActions: some View {
        HStack(spacing: 4) {
            if model.importingImage { ProgressView(); Text("Preparing image…").font(.caption) }
            else if model.selectedImage != nil {
                Button { model.copySelectedImage() } label: { Label("Copy", systemImage: "doc.on.doc").frame(minHeight: 44) }
                Button { model.duplicateSelectedImage() } label: { Image(systemName: "plus.square.on.square").frame(width: 44, height: 44) }.accessibilityLabel("Duplicate image")
                Button { model.rotateSelectedImage() } label: { Image(systemName: "rotate.right").frame(width: 44, height: 44) }.accessibilityLabel("Rotate image")
                Button(role: .destructive) { model.deleteSelectedImage() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Delete image")
                Button("Done") { model.tool = .pen }.frame(minHeight: 44)
            } else { Text("Tap an image to select it, then drag to move.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func paste(image: Bool = false) {
        (model.canvas as? PaperlyCanvasView)?.pasteSelection(preferImages: image || model.tool == .image)
    }
    private func export(pdf: Bool) {
        guard !model.loading else { return }
        Task {
            guard await session.flushAll() else { return }
            do {
                let url: URL
                if pdf { url = try await PDFService.export(model.manifest.id, repository: model.repository) }
                else {
                    let data = try await model.repository.exportData(model.manifest.id)
                    url = FileManager.default.temporaryDirectory.appendingPathComponent("Notebook-\(UUID()).paperly")
                    try await Task.detached { try data.write(to: url, options: .atomic) }.value
                }
                share = ShareItem(url: url)
            } catch { model.error = error.localizedDescription }
        }
    }
}

struct PageThumbnail: View {
    let repository: NotebookRepository
    let notebook: UUID
    let page: NotebookPage
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            PaperBackground(template: page.template)
            if let image { Image(uiImage: image).resizable().scaledToFit() }
        }
        .frame(width: 48, height: 64).clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: page.drawingFile) {
            if let bytes = try? await repository.thumbnailData(notebook, page: page.id) { image = UIImage(data: bytes) }
        }
        .accessibilityHidden(true)
    }
}
