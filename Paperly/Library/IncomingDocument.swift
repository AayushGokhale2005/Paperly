import Foundation

/// Copy incoming provider files immediately; the destination chooser may outlive their URL grant.
struct IncomingDocument: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let fileURL: URL
    let isPDF: Bool
    static func stage(_ source: URL, root: URL) throws -> Self {
        let ext = source.pathExtension.lowercased()
        guard ["pdf", "paperly"].contains(ext) else { throw DocumentError.invalidManifest }
        let folder = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID(), target = folder.appendingPathComponent("\(id).\(ext)")
        try FileManager.default.copyItem(at: source, to: target)
        let request = Self(id: id, title: source.deletingPathExtension().lastPathComponent, fileURL: target, isPDF: ext == "pdf")
        do { try JSONEncoder().encode(request).write(to: folder.appendingPathComponent("\(id).json"), options: .atomic) }
        catch { try? FileManager.default.removeItem(at: target); throw error }
        return request
    }
    static func pending(root: URL) throws -> [Self] {
        let folder = root.appendingPathComponent("Inbox", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                let request = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
                // Resolve against this installation's container after restore or migration.
                let current = folder.appendingPathComponent(request.fileURL.lastPathComponent)
                guard FileManager.default.fileExists(atPath: current.path) else { return nil }
                return Self(id: request.id, title: request.title, fileURL: current, isPDF: request.isPDF)
            }
    }
    func remove() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingPathExtension().appendingPathExtension("json"))
        try FileManager.default.removeItem(at: fileURL)
    }
}
