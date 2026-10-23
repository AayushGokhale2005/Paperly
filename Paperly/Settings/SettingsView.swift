import SwiftUI

struct SettingsView: View {
    let repository: NotebookRepository
    let account: GoogleAccount
    let sync: SyncService
    var onDone: (() -> Void)? = nil
    @State private var bytes: Int64 = 0
    @AppStorage("defaultTemplate") private var template = "ruled"
    @AppStorage("appearance") private var appearance = "system"
#if !targetEnvironment(macCatalyst)
    @AppStorage("audioNotesEnabled") private var audioNotesEnabled = true
#endif
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "externaldrive.badge.icloud").font(.title).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.email ?? "Google Drive").font(.headline)
                            Text(account.email == nil ? "Connect to sync across your devices" : "Connected").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()

                    }.padding(.vertical, 6)
                    if account.email != nil { Button("Disconnect Google Drive") { account.disconnect() } }
                    else { Button("Sign in with Google") { Task { await account.connect(); await sync.sync() } } }
                    LabeledContent("Sync status", value: sync.status)
                    if let last = sync.lastSync { LabeledContent("Last synced", value: last.formatted(date: .abbreviated, time: .shortened)) }
                    Button { Task { await sync.sync() } } label: { Label(sync.running ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") }.disabled(sync.running || account.email == nil)
                    if let error = sync.error ?? account.error { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                } header: { Text("Google Drive") } footer: { Text("Paperly requests access only to files it creates or you explicitly open with it. Notebooks save locally before syncing.") }
                if !sync.conflicts.isEmpty {
                    Section {
                        ForEach(sync.conflicts) { snapshot in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(snapshot.name ?? "Remote notebook").font(.headline)
                                Button("Download as separate notebook") { Task { await sync.keepConflictAsCopy(snapshot) } }.disabled(sync.running)
                                if let id = snapshot.notebookID, sync.localNotebookIDs.contains(id) {
                                    Button("Keep local notebook as current") { Task { await sync.keepLocalAsCurrent(id) } }.disabled(sync.running)
                                }
                            }
                        }
                    } header: { Text("Conflicting versions") } footer: { Text("Your local notebook and every remote branch are preserved. Download a version to compare. Keep local as current to resume sync; previous remote versions remain in Drive.") }
                }
                Section {
                    LabeledContent("Offline storage", value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    Label("All documents are available offline", systemImage: "checkmark.circle")
                } header: { Text("Storage") } footer: { Text("Text documents, notebooks, and editable strokes stay in Paperly’s local Documents folder. Keep an exported backup before removing the app.") }
                Section {
                    Label("Open a notebook → Options → Export", systemImage: "square.and.arrow.up")
                    Text("Export editable .paperly files for backup. Text documents also export as Markdown; notebooks export as PDF with their original content and ink.").font(.subheadline).foregroundStyle(.secondary)
                } header: { Text("Notebook export") }
                Section("Search") {
                    Label("On-device handwriting recognition", systemImage: "text.magnifyingglass")
                    Text("Workspace search includes saved handwriting and text documents. Tap a page result to open it. If recognition misses a word or symbol, add search terms from Notebook options → Searchable handwriting.").font(.subheadline).foregroundStyle(.secondary)
                }
#if !targetEnvironment(macCatalyst)
                Section {
                    Toggle("Show Audio Note in the New menu", isOn: $audioNotesEnabled)
                } header: {
                    Text("Audio notes")
                } footer: {
                    Text(AudioNoteSupport.isAvailable
                         ? "Records, transcribes with a local Whisper model, and creates structured notes using Apple Intelligence."
                         : "This feature is currently only supported on iPhones with Apple Intelligence.")
                }
#endif
                Section("Paper templates") {
                    Picker("Default paper", selection: $template) { ForEach(PaperTemplate.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) } }
                }
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                }
                Section("About Paperly") { Text("A quiet place to write and think. On-device handwriting search and audio notes. No cloud AI, analytics, or backend server.").foregroundStyle(.secondary) }
            }.navigationTitle("Settings")
                .toolbar { if let onDone { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } } }
                .task { bytes = (try? await repository.storageBytes()) ?? 0 }
        }
    }
}
