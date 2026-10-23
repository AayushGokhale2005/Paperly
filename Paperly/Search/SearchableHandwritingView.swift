import SwiftUI

struct SearchableHandwritingView: View {
    let repository: NotebookRepository
    let notebook: UUID
    let page: UUID
    let pageNumber: Int
    let onSave: (NotebookManifest) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recognized = ""
    @State private var terms = ""
    @State private var loading = true
    @State private var saving = false
    @State private var loadedTerms = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Recognized on page \(pageNumber)") {
                    if loading { ProgressView("Recognizing saved handwriting…") }
                    else { Text(recognized.isEmpty ? "No text recognized on this page." : recognized).textSelection(.enabled) }
                }
                Section {
                    TextEditor(text: $terms).frame(minHeight: 150).accessibilityLabel("Additional searchable words or symbols")
                } header: { Text("Additional words or symbols") } footer: {
                    Text("Add anything recognition missed, such as ∫, alpha, or an unusual name. These terms are saved in the editable notebook. Recognition runs on this device; cursive and mathematical notation may be incomplete.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red); Button("Retry recognition") { Task { await load() } } }
                }
            }
            .navigationTitle("Searchable handwriting").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                let m = try await repository.saveSearchTerms(terms, notebook: notebook, page: page)
                                onSave(m); dismiss()
                            } catch { self.error = error.localizedDescription; saving = false }
                        }
                    }.disabled(loading || saving)
                }
            }
        }
        .task { await load() }
        .interactiveDismissDisabled(saving)
    }
    private func load() async {
        loading = true; error = nil
        do {
            let m = try await repository.load(notebook)
            if !loadedTerms { terms = m.pages.first { $0.id == page }?.searchTerms ?? ""; loadedTerms = true }
            recognized = try await HandwritingIndexer(repository: repository).indexPage(notebook: notebook, page: page)
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
