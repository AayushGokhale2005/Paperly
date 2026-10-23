import SwiftUI
import UniformTypeIdentifiers

extension UTType { static let paperly = UTType(exportedAs: "app.paperly.notebook", conformingTo: .data) }

struct LibraryView: View {
    @State var model: LibraryViewModel
    let sync: SyncService
    let account: GoogleAccount
    let shortcuts: ShortcutRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selection = "Library"
    @State private var grid = true
    @State private var phonePath: [String] = []
    private enum PhoneSection: Hashable { case workspace, recents, trash, settings }
    @State private var phoneSection: PhoneSection = .workspace
    @State private var create = false
    @State private var importer = false
    @State private var editor: NotebookManifest?
    @State private var editorPageID: UUID?
    @State private var folderName = ""
    @State private var addingFolder = false
    @State private var coloringFolder: String?
    @State private var trashPath: [String] = []
    @State private var deletingNotebook: NotebookSummary?
    @State private var deletingFolder: String?
    @State private var selectedForMove: NotebookSummary?
    @State private var moveFolder = ""
    @State private var choosingImportLocation = false
    @State private var importedToOpen: NotebookManifest?
#if !targetEnvironment(macCatalyst)
    @AppStorage("audioNotesEnabled") private var audioNotesEnabled = true
    @State private var recordingAudioNote = false
    @State private var audioNoteToOpen: NotebookManifest?
    @State private var audioNoteUnavailable = false
    @State private var audioNotesDisabled = false
#endif
    private var isWorkspace: Bool { selection == "Library" && model.folder == nil && model.query.isEmpty }

    private var workspaceSummary: String {
        let count = model.filtered.count
        let documents = "\(count) \(count == 1 ? "document" : "documents")"
        if isWorkspace || (model.showTrash && model.folder == nil && model.query.isEmpty) {
            let folders = model.showTrash ? model.deletedFolders.count : model.folders.count
            return "\(folders) \(folders == 1 ? "folder" : "folders") · " + documents
        }
        return documents + (model.showTrash ? " · in Trash" : " · available offline")
    }

    var body: some View {
        Group {
            if sizeClass == .compact { phoneWorkspace }
            else { tabletWorkspace }
        }
        .task { await model.reload(); if model.pendingImport != nil { choosingImportLocation = true }; sync.start() }
        .onChange(of: shortcuts.pending) { _, shortcut in
            guard let shortcut else { return }
            shortcuts.pending = nil
            handle(shortcut)
        }
        .onChange(of: model.pendingImport?.id) { _, id in
            if id != nil, editor == nil { create = false; choosingImportLocation = true }
        }
        .onChange(of: editor?.id) { _, id in if id != nil { model.pauseIndexing() } }
        .onChange(of: sync.running) { _, running in if !running { Task { await model.reload(indexHandwriting: editor == nil) } } }
        .sheet(isPresented: $create) {
            CreateNotebookView(repository: model.repository, folder: model.folder) { manifest in
                Task { await model.reload() }; sync.openNotebook = manifest.id; editorPageID = nil; editor = manifest
            }
        }
        .fullScreenCover(item: $editor, onDismiss: {
            sync.openNotebook = nil
            if model.pendingImport != nil { choosingImportLocation = true }
            Task { await model.reload(); if model.pendingImport == nil { await sync.sync(); await model.reload() } }
        }) { manifest in
            if manifest.isTextDocument {
                TextDocumentEditorView(model: TextDocumentViewModel(manifest: manifest, repository: model.repository), incomingImportID: model.pendingImport?.id)
            } else {
                NotebookEditorView(model: EditorViewModel(manifest: manifest, repository: model.repository), incomingImportID: model.pendingImport?.id, initialPageID: editorPageID)
            }
        }
#if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $recordingAudioNote, onDismiss: {
            guard let manifest = audioNoteToOpen else { return }
            audioNoteToOpen = nil
            Task {
                await model.reload()
                sync.openNotebook = manifest.id
                editorPageID = nil
                editor = manifest
            }
        }) {
            PhoneAudioNoteView(
                model: PhoneAudioNoteWorkspace(repository: model.repository, folder: model.folder),
                onComplete: { manifest in
                    audioNoteToOpen = manifest
                    recordingAudioNote = false
                },
                onCancel: { recordingAudioNote = false }
            )
        }
#endif
        .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf, .paperly]) { result in
            switch result { case .success(let url): Task { await model.importFile(url) }; case .failure(let error): model.error = error.localizedDescription }
        }
        .sheet(isPresented: $choosingImportLocation, onDismiss: {
            if let imported = importedToOpen { importedToOpen = nil; sync.openNotebook = imported.id; editorPageID = nil; editor = imported }
            else if model.pendingImport != nil { Task { await Task.yield(); choosingImportLocation = true } }
        }) {
            if let incoming = model.pendingImport {
                ImportLocationView(model: model, incoming: incoming, initialFolder: model.folder) { manifest in
                    importedToOpen = manifest; choosingImportLocation = false
                }.id(incoming.id)
            }
        }
        .sheet(isPresented: Binding(get: { coloringFolder != nil }, set: { if !$0 { coloringFolder = nil } })) {
            if let name = coloringFolder { FolderColorView(name: name, model: model) }
        }
        .confirmationDialog("Move to Trash?", isPresented: Binding(get: { deletingNotebook != nil || deletingFolder != nil }, set: { if !$0 { deletingNotebook = nil; deletingFolder = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                let item = deletingNotebook, folder = deletingFolder
                deletingNotebook = nil; deletingFolder = nil
                Task {
                    do {
                        if let item { try await model.repository.trashNotebook(item.id) }
                        if let folder { try await model.repository.trashFolder(folder) }
                        await model.reload(); await sync.sync()
                    } catch { model.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { deletingNotebook = nil; deletingFolder = nil }
        } message: {
            Text(deletingFolder.map { "“\($0)” and its documents will move to Trash. You can restore them later." } ?? "“\(deletingNotebook?.manifest.title ?? "Document")” will move to Trash. You can restore it later.")
        }
        .alert("New folder", isPresented: $addingFolder) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) { folderName = "" }
            Button("Create folder") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    do { try await model.repository.createFolder(name); model.folder = name; phonePath = [name]; phoneSection = .workspace; selection = "Library"; model.showAll = false; model.showTrash = false; folderName = ""; await model.reload() }
                    catch { model.error = error.localizedDescription }
                }
            }.disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Move or rename document", isPresented: Binding(get: { selectedForMove != nil }, set: { if !$0 { selectedForMove = nil } })) {
            TextField("Document title", text: $folderName)
            TextField("Folder (empty for Workspace)", text: $moveFolder)
            Button("Cancel", role: .cancel) { selectedForMove = nil }
            Button("Save") {
                guard let item = selectedForMove else { return }; selectedForMove = nil
                Task {
                    do { try await model.repository.rename(item.id, title: folderName.isEmpty ? item.manifest.title : folderName, folder: moveFolder.isEmpty ? nil : moveFolder); await model.reload() }
                    catch { model.error = error.localizedDescription }
                }
            }
        }
        .alert("Could not complete action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
#if !targetEnvironment(macCatalyst)
        .alert("Apple Intelligence required", isPresented: $audioNoteUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is currently only supported on iPhones with Apple Intelligence.")
        }
        .alert("Audio Notes is turned off", isPresented: $audioNotesDisabled) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable Audio Notes in Paperly Settings to use this widget.")
        }
#endif
    }
    private var newDocumentMenu: some View {
        Menu {
            Button("Text document", systemImage: "doc.text") {
                createTextDocument()
            }
            Button("Handwritten notebook", systemImage: "pencil.and.scribble") { create = true }
#if !targetEnvironment(macCatalyst)
            if sizeClass == .compact, audioNotesEnabled {
                Button("Audio note", systemImage: "waveform.badge.mic") {
                    if AudioNoteSupport.isAvailable { recordingAudioNote = true }
                    else { audioNoteUnavailable = true }
                }
            }
#endif
            Button("Import PDF or Paperly file", systemImage: "square.and.arrow.down") { importer = true }
            Button("Folder", systemImage: "folder.badge.plus") { addingFolder = true }
        } label: { Label("New", systemImage: "plus").frame(minWidth: 44, minHeight: 44) }
        .accessibilityLabel("New document or folder")
    }
    private func createTextDocument() {
        Task {
            do {
                let manifest = try await model.repository.createText(title: "Untitled document", folder: model.folder)
                await model.reload(); sync.openNotebook = manifest.id; editorPageID = nil; editor = manifest
            } catch { model.error = error.localizedDescription }
        }
    }
    private func handle(_ shortcut: PaperlyShortcut) {
        selection = "Library"; model.showAll = false; model.showTrash = false; model.folder = nil
        phoneSection = .workspace; phonePath = []
        switch shortcut {
        case .workspace:
            break
        case .newText:
            createTextDocument()
        case .audio:
#if !targetEnvironment(macCatalyst)
            guard audioNotesEnabled else { audioNotesDisabled = true; return }
            if AudioNoteSupport.isAvailable { recordingAudioNote = true }
            else { audioNoteUnavailable = true }
#endif
        }
    }
    private func folderTint(_ name: String) -> Color { (model.folderAppearances[name]?.color ?? .blue).tint }
    private func chooseFolder(_ folder: String) {
        model.folder = folder; model.showAll = false; model.showTrash = false; selection = "Library"
        if sizeClass == .compact { phonePath = [folder] }
    }
    private var phoneWorkspace: some View {
        TabView(selection: $phoneSection) {
            NavigationStack(path: $phonePath) {
                workspaceScreen
                    .navigationTitle("Workspace")
                    .navigationDestination(for: String.self) { folder in workspaceScreen.navigationTitle(folder) }
            }
            .tabItem { Label("Workspace", systemImage: "books.vertical") }.tag(PhoneSection.workspace)
            NavigationStack {
                workspaceScreen.navigationTitle("Recents")
            }
            .tabItem { Label("Recents", systemImage: "clock") }.tag(PhoneSection.recents)
            NavigationStack(path: $trashPath) {
                workspaceScreen.navigationTitle("Trash")
                    .navigationDestination(for: String.self) { name in workspaceScreen.navigationTitle(name) }
            }
            .tabItem { Label("Trash", systemImage: "trash") }.tag(PhoneSection.trash)
            SettingsView(repository: model.repository, account: account, sync: sync)
                .tabItem { Label("Settings", systemImage: "gearshape") }.tag(PhoneSection.settings)
        }
        .onChange(of: phoneSection) { _, section in
            selection = section == .settings ? "Settings" : section == .recents ? "Recents" : section == .trash ? "Trash" : "Library"
            model.folder = section == .workspace ? phonePath.last : section == .trash ? trashPath.last : nil
            model.showAll = section == .recents
            model.showTrash = section == .trash
            model.query = ""
        }
        .onChange(of: trashPath) { _, path in
            if phoneSection == .trash { model.folder = path.last }
        }
        .onChange(of: phonePath) { _, path in
            if phoneSection == .workspace { model.folder = path.last; model.showAll = false }
        }
    }
    private var workspaceScreen: some View {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    if model.folder != nil, sizeClass != .compact {
                                        Button { model.folder = nil; model.showAll = false } label: { Label(model.showTrash ? "Trash" : "Workspace", systemImage: "chevron.left") }
                                    }
                                    if sizeClass != .compact {
                                        Text(model.folder ?? (model.showTrash ? "Trash" : selection == "Recents" ? "Recents" : "Workspace")).font(.largeTitle.bold())
                                    }
                                    Text(workspaceSummary).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.query.isEmpty && !model.showTrash {
                                    Picker("View", selection: $grid) {
                                        Image(systemName: "square.grid.2x2.fill").tag(true)
                                        Image(systemName: "list.bullet").tag(false)
                                    }.pickerStyle(.segmented).frame(width: 110)
                                }
                            }
                            Picker("Document type", selection: $model.contentFilter) {
                                ForEach(LibraryViewModel.ContentFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                            if !model.query.isEmpty {
                                HStack(spacing: 8) {
                                    if model.indexing || model.searching { ProgressView().controlSize(.small) }
                                    Text(model.indexing ? "Indexing saved handwriting on this device…" : "Searches titles, text, and saved handwriting").font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = model.recognitionError {
                                    VStack(alignment: .leading) {
                                        Text("Some handwriting could not be indexed: " + error).font(.caption).foregroundStyle(.secondary)
                                        Button("Retry recognition") { model.scheduleIndexing() }
                                    }
                                }
                            }
                            if (selection == "Library" || model.showTrash), model.folder == nil, !model.visibleFolders.isEmpty {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 20)], spacing: 20) {
                                    ForEach(model.visibleFolders, id: \.self) { folder in
                                        HStack(spacing: 0) {
                                            Button { if model.showTrash { model.folder = folder; trashPath = [folder] } else { chooseFolder(folder) } } label: {
                                                HStack(spacing: 16) {
                                                    Image(systemName: "folder.fill").font(.largeTitle).foregroundStyle(folderTint(folder))
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text(folder).font(.headline).foregroundStyle(.primary)
                                                        Text("\(model.notebooks.filter { $0.manifest.folder == folder && $0.manifest.isTrashed == model.showTrash }.count) documents").font(.caption).foregroundStyle(.secondary)
                                                    }
                                                    Spacer(minLength: 0)
                                                }.padding(20).frame(minHeight: 100).contentShape(Rectangle())
                                            }.buttonStyle(.plain)
                                            Menu {
                                                folderActions(folder)
                                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                            .accessibilityLabel("Folder options for \(folder)").padding(.trailing, 8)
                                        }
                                        .background(RoundedRectangle(cornerRadius: 16).stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1))
                                        .contextMenu { folderActions(folder) }
                                    }
                                }
                            }
                            if model.showTrash, let folder = model.folder {
                                Button("Restore folder and its contents", systemImage: "arrow.uturn.backward") { restore(folder: folder) }
                            }
                            if model.loading && model.notebooks.isEmpty { ProgressView().frame(maxWidth: .infinity, minHeight: 260) }
                            else if model.filtered.isEmpty && !(model.folder == nil && !model.visibleFolders.isEmpty && (selection == "Library" || model.showTrash)) {
                                ContentUnavailableView {
                                    Label(model.query.isEmpty ? (model.showTrash ? "Trash is empty" : "A fresh page awaits") : "No matching documents", systemImage: model.query.isEmpty ? (model.showTrash ? "trash" : "book.closed") : "magnifyingglass")
                                } description: {
                                    Text(model.query.isEmpty ? (model.showTrash ? "Deleted documents and folders will appear here. Restore them whenever you need them." : "Create a text document, handwritten notebook, or import a PDF. Your work is available offline.") : "Try another word or symbol. Cursive and equations may need additional search terms.")
                                } actions: { if model.query.isEmpty && !model.showTrash { newDocumentMenu.buttonStyle(.borderedProminent) } }
                                .frame(minHeight: 350)
                            } else if model.showTrash {
                                trashDocuments
                            } else if !model.query.isEmpty {
                                searchResults
                            } else if grid {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : (sizeClass == .compact ? 150 : 235), maximum: 360), spacing: 20)], spacing: 20) {
                                    ForEach(model.filtered) { item in notebookCard(item).transition(.opacity) }
                                }
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(model.filtered) { item in
                                        HStack(spacing: 0) {
                                            Button { open(item) } label: {
                                                HStack(spacing: 18) {
                                                    DocumentCover(manifest: item.manifest).frame(width: 54, height: 70).padding(.vertical, 12)
                                                    VStack(alignment: .leading, spacing: 5) { Text(item.manifest.title).font(.headline); details(item) }
                                                    Spacer()
                                                }.contentShape(Rectangle())
                                            }.buttonStyle(.plain).contextMenu { documentActions(item) }
                                            Menu { documentActions(item) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(item.manifest.title)")
                                        }
                                        Divider()
                                    }
                                }
                            }
                        }.padding(sizeClass == .compact ? 20 : 28)
                    }
                    .animation(reduceMotion ? nil : .snappy(duration: 0.24, extraBounce: 0), value: grid)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.contentFilter)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.filtered.map(\.id))
                    .background(Color(uiColor: .systemBackground))
                    .searchable(text: $model.query, prompt: model.showTrash ? "Search Trash" : "Search workspace")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if UIDevice.current.userInterfaceIdiom == .phone, phoneSection == .workspace, phonePath.isEmpty {
                                Image("PaperlyMark")
                                    .resizable().scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .frame(width: 44, height: 44, alignment: .center)
                                    .accessibilityLabel("Paperly")
                            }
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Menu {
                                Picker("Sort", selection: $model.sort) { ForEach(LibraryViewModel.SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Sort documents")
                            if !model.showTrash && sizeClass != .compact { Button { importer = true } label: { Label("Import", systemImage: "square.and.arrow.down") } }
                            if !model.showTrash { newDocumentMenu }
                        }
                    }
    }
    private var tabletWorkspace: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("Paperly").font(.largeTitle.bold()); Spacer(); Image(systemName: "book.closed").font(.title3).foregroundStyle(.secondary) }
                    .padding(24).padding(.top, 8)
                List {
                    Section {
                        sidebarRow("Workspace", symbol: "books.vertical", selected: selection == "Library" && model.folder == nil) { selection = "Library"; model.folder = nil; model.showAll = false; model.showTrash = false }
                        sidebarRow("Recents", symbol: "clock", selected: selection == "Recents") { selection = "Recents"; model.folder = nil; model.showAll = true; model.showTrash = false; model.sort = .modified }
                    }
                    Section {
                        sidebarRow("Trash", symbol: "trash", selected: model.showTrash) { selection = "Trash"; model.folder = nil; model.showAll = false; model.showTrash = true }
                    }
                    Section("Folders") {
                        ForEach(model.folders, id: \.self) { folder in
                            Button { chooseFolder(folder) } label: {
                                Label { Text(folder).foregroundStyle(.primary) } icon: { Image(systemName: "folder.fill").foregroundStyle(folderTint(folder)) }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                            }
                            .listRowBackground(model.folder == folder ? Color.accentColor.opacity(0.13) : .clear)
                            .contextMenu { folderActions(folder) }
                        }
                        Button { addingFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    }
                    Section {
                        sidebarRow("Settings", symbol: "gearshape", selected: selection == "Settings") { selection = "Settings"; model.folder = nil }
                    }
                }.listStyle(.sidebar)
                Button { selection = "Settings" } label: {
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Google Drive").font(.headline)
                                Text(account.email == nil ? "Connect account" : sync.status).font(.subheadline)
                            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                        HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.icloud").font(.title2).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Google Drive").font(.subheadline).foregroundStyle(.secondary)
                            Text(account.email == nil ? "Connect account" : sync.status).font(.subheadline.weight(.medium)).lineLimit(2)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }
                        }
                    }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).padding(18)
            }.background(Color(uiColor: .secondarySystemBackground))
                .toolbar(.hidden, for: .navigationBar)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } detail: {
            if selection == "Settings" {
                SettingsView(repository: model.repository, account: account, sync: sync)
            } else {
                NavigationStack { workspaceScreen }

            }
        }
    }
    private func sidebarRow(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.body.weight(selected ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9) }
            .listRowBackground(selected ? Color.accentColor.opacity(0.13) : Color.clear).foregroundStyle(selected ? Color.accentColor : Color.primary)
    }
    private func open(_ item: NotebookSummary, page: UUID? = nil) {
        guard !item.manifest.isTrashed else { return }
        editorPageID = page; sync.openNotebook = item.id; editor = item.manifest
    }
    private var searchResults: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(model.filtered) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Button { open(item, page: model.searchHits[item.id]?.first?.pageID) } label: {
                        Label(item.manifest.title, systemImage: item.manifest.isTextDocument ? "doc.text" : "book.closed").font(.headline).frame(minHeight: 44)
                    }.contextMenu { documentActions(item) }
                    if let hits = model.searchHits[item.id], !hits.isEmpty {
                        ForEach(hits) { hit in
                            Button { open(item, page: hit.pageID) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.pageNumber.map { "Page \($0)" } ?? "Text document").font(.subheadline.weight(.medium))
                                    Text(hit.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } else { Text("Title match").font(.caption).foregroundStyle(.secondary) }
                }
                Divider()
            }
        }
    }
    private func notebookCard(_ item: NotebookSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); Menu {
                documentActions(item)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(item.manifest.title)") }.padding(.horizontal, 8)
            Button { open(item) } label: {
                VStack(alignment: .leading, spacing: 20) {
                    DocumentCover(manifest: item.manifest).aspectRatio(168.0 / 218, contentMode: .fit).frame(maxWidth: 168, maxHeight: 218).frame(maxWidth: .infinity).padding(.bottom, 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.manifest.title).font(.title3.bold()).foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        details(item)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 20).padding(.bottom, 20).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.background(RoundedRectangle(cornerRadius: 16).stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1))
    }
    @ViewBuilder private func documentActions(_ item: NotebookSummary) -> some View {
        Button("Open", systemImage: "book") { open(item) }
        Button("Rename or move", systemImage: "folder") { folderName = item.manifest.title; moveFolder = item.manifest.folder ?? ""; selectedForMove = item }
        Button("Move to Trash", systemImage: "trash", role: .destructive) { deletingNotebook = item }
    }
    @ViewBuilder private func folderActions(_ name: String) -> some View {
        if model.folderAppearances[name]?.isDeleted == true {
            Button("Restore folder", systemImage: "arrow.uturn.backward") { restore(folder: name) }
        } else {
            Button("Folder color", systemImage: "paintpalette") { coloringFolder = name }
            Button("Move to Trash", systemImage: "trash", role: .destructive) { deletingFolder = name }
        }
    }
    private func restore(folder: String? = nil, document: UUID? = nil) {
        Task {
            do {
                if let folder { try await model.repository.restoreFolder(folder); model.folder = nil; trashPath = [] }
                if let document { try await model.repository.restoreNotebook(document) }
                await model.reload(); await sync.sync()
            } catch { model.error = error.localizedDescription }
        }
    }
    private var trashDocuments: some View {
        LazyVStack(spacing: 0) {
            ForEach(model.filtered) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.manifest.isTextDocument ? "doc.text" : "book.closed").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.manifest.title).font(.headline)
                        if let date = item.manifest.trashedAt { Text("Deleted " + date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Restore") { restore(document: item.id) }.buttonStyle(.bordered).accessibilityLabel("Restore \(item.manifest.title)")
                }.padding(.vertical, 14)
                Divider()
            }
        }
    }
    private func details(_ item: NotebookSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(item.manifest.isTextDocument ? "Text document" : "\(item.manifest.pages.count) pages") · \(item.manifest.modifiedAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
            Label(item.syncState.hasPrefix("Conflict") ? item.syncState : (item.baseGeneration == item.manifest.generation ? item.syncState : (account.email == nil ? "On this device" : "Waiting to sync")), systemImage: item.baseGeneration == item.manifest.generation ? "checkmark.icloud" : "internaldrive")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct DocumentCover: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let manifest: NotebookManifest
    var body: some View {
        if manifest.isTextDocument {
            RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    GeometryReader { geometry in
                        if geometry.size.width < 100 || typeSize.isAccessibilitySize {
                            Image(systemName: "doc.text").font(.title2).foregroundStyle(.blue)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.blue)
                                Text(manifest.title).font(.headline).lineLimit(3)
                                Spacer(minLength: 0)
                            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }.accessibilityHidden(true)
        } else { NotebookCover(cover: manifest.cover) }
    }
}

struct NotebookCover: View {
    let cover: String
    var color: Color {
        switch cover { case "sand": Color(red: 0.88, green: 0.83, blue: 0.72); case "sage": Color(red: 0.64, green: 0.76, blue: 0.65); case "lavender": Color(red: 0.72, green: 0.68, blue: 0.84); default: Color(red: 0.57, green: 0.71, blue: 0.89) }
    }
    var body: some View {
        RoundedRectangle(cornerRadius: 10).fill(color.gradient)
            .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.1)).frame(width: 2).padding(.leading, 17) }
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.25)).frame(width: 1).padding(.leading, 19) }
            .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 9)
            .accessibilityHidden(true)
    }
}

struct CreateNotebookView: View {
    let repository: NotebookRepository
    let folder: String?
    let onCreate: (NotebookManifest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @AppStorage("defaultTemplate") private var defaultTemplate = "ruled"
    @State private var template: PaperTemplate = .ruled
    @State private var cover = "blue"
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Notebook") { TextField("Untitled notebook", text: $title) }
                Section("Paper") {
                    Picker("Template", selection: $template) { ForEach(PaperTemplate.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.segmented)
                    PaperBackground(template: template).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Section("Cover") { Picker("Color", selection: $cover) { ForEach(["blue", "sand", "sage", "lavender"], id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.segmented) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("New Notebook").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") {
                    saving = true
                    Task {
                        do {
                            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            let m = try await repository.create(title: name.isEmpty ? "Untitled notebook" : name, template: template, cover: cover, folder: folder)
                            dismiss(); onCreate(m)
                        } catch { self.error = error.localizedDescription; saving = false }
                    }
                }.disabled(saving) }
            }.onAppear { template = PaperTemplate(rawValue: defaultTemplate) ?? .ruled }
        }.presentationDetents([.large])
    }
}
