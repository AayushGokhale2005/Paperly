import SwiftUI

extension FolderColor {
    var tint: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: Color(uiColor: .systemYellow)
        case .green: .green
        case .gray: .gray
        }
    }
}

struct FolderColorView: View {
    let name: String
    @Bindable var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(FolderColor.allCases, id: \.self) { color in
                        Button {
                            saving = true
                            Task {
                                do {
                                    try await model.repository.setFolderColor(name, color: color)
                                    await model.reload(); dismiss()
                                } catch { self.error = error.localizedDescription; saving = false }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill").font(.title2).foregroundStyle(color.tint)
                                Text(color.rawValue.capitalized).foregroundStyle(.primary)
                                Spacer()
                                if (model.folderAppearances[name]?.color ?? .blue) == color { Image(systemName: "checkmark").foregroundStyle(.blue) }
                            }.frame(minHeight: 44)
                        }.disabled(saving)
                    }
                } header: { Text(name) } footer: { Text("Saved locally and included in Google Drive workspace sync.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Folder color").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
        }
    }
}
