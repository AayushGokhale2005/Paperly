import SwiftUI

struct ImportLocationView: View {
    @Bindable var model: LibraryViewModel
    let incoming: IncomingDocument
    let onImport: (NotebookManifest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var folder: String
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var importing = false
    @State private var error: String?

    init(model: LibraryViewModel, incoming: IncomingDocument, initialFolder: String?, onImport: @escaping (NotebookManifest) -> Void) {
        self.model = model; self.incoming = incoming; self.onImport = onImport
        _title = State(initialValue: incoming.title); _folder = State(initialValue: initialFolder ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Document") { TextField("Name", text: $title) }
                Section("Save in") {
                    destination("Workspace", value: "")
                    ForEach(model.folders, id: \.self) { destination($0, value: $0) }
                    Button("New folder", systemImage: "folder.badge.plus") { creatingFolder = true }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(incoming.isPDF ? "Import PDF" : "Import notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Task { await model.cancelImport(incoming); dismiss() } }.disabled(importing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importing ? "Importing…" : "Import & Open") {
                        importing = true
                        Task {
                            do {
                                let result = try await model.finishImport(incoming, title: title.trimmingCharacters(in: .whitespacesAndNewlines), folder: folder.isEmpty ? nil : folder)
                                onImport(result)
                            } catch { self.error = error.localizedDescription; importing = false }
                        }
                    }.disabled(importing || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("New folder", isPresented: $creatingFolder) {
                TextField("Folder name", text: $folderName)
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    Task {
                        do { try await model.repository.createFolder(folderName); await model.reload(); folder = folderName.trimmingCharacters(in: .whitespacesAndNewlines); folderName = "" }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.interactiveDismissDisabled().presentationDetents([.large])
    }
    private func destination(_ name: String, value: String) -> some View {
        Button { folder = value } label: {
            HStack { Label(name, systemImage: value.isEmpty ? "square.grid.2x2" : "folder"); Spacer(); if folder == value { Image(systemName: "checkmark") } }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.foregroundStyle(.primary).disabled(importing)
    }
}
