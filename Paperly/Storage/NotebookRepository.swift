import Foundation
import GRDB

struct NotebookSummary: Identifiable, Sendable {
    var manifest: NotebookManifest
    var baseGeneration: UUID?
    var remoteID: String?
    var remoteVersion: String?
    var syncState: String
    var id: UUID { manifest.id }
}

actor NotebookRepository {
    let root: URL
    private let db: DatabaseQueue
    private let fm = FileManager.default
    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        db = try DatabaseQueue(path: root.appendingPathComponent("metadata.sqlite").path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: "CREATE TABLE notebooks (id TEXT PRIMARY KEY, manifest BLOB NOT NULL, base TEXT, remoteID TEXT, remoteVersion TEXT, state TEXT NOT NULL DEFAULT 'Local only')")
        }
        migrator.registerMigration("v2-folders") { db in
            try db.execute(sql: "CREATE TABLE folders (name TEXT PRIMARY KEY NOT NULL)")
            for row in try Row.fetchAll(db, sql: "SELECT manifest FROM notebooks") {
                let data: Data = row["manifest"]
                if let folder = try JSONDecoder().decode(NotebookManifest.self, from: data).folder {
                    try db.execute(sql: "INSERT OR IGNORE INTO folders(name) VALUES (?)", arguments: [folder])
                }
            }
        }
        migrator.registerMigration("v3-folder-colors") { db in
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN color TEXT NOT NULL DEFAULT 'blue'")
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN colorModified REAL NOT NULL DEFAULT 0")
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN colorRevision TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000'")
        }
        migrator.registerMigration("v4-search-index") { db in
            try db.execute(sql: "CREATE TABLE pageSearch (notebook TEXT NOT NULL, page TEXT NOT NULL, fingerprint TEXT NOT NULL, recognized TEXT NOT NULL, searchText TEXT NOT NULL, PRIMARY KEY(notebook,page))")
        }
        migrator.registerMigration("v5-folder-trash") { db in
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "ALTER TABLE folders ADD COLUMN trashGroup TEXT")
        }
        try migrator.migrate(db)
    }
    func createFolder(_ name: String) throws {
        let trimmed = try WorkspaceFolder.name(name)
        if try folderAppearances().contains(where: { $0.name == trimmed && $0.isDeleted }) { throw DocumentError.folderInTrash(trimmed) }
        try db.write { db in try db.execute(sql: "INSERT OR IGNORE INTO folders(name) VALUES (?)", arguments: [trimmed]) }
    }
    func mergeFolders(_ remote: [String]) throws {
        let merged = try WorkspaceFolder.merge(folders(), remote)
        try db.write { db in
            for name in merged { try db.execute(sql: "INSERT OR IGNORE INTO folders(name) VALUES (?)", arguments: [name]) }
        }
    }
    func folderAppearances() throws -> [FolderAppearance] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM folders ORDER BY name COLLATE NOCASE").map { row in
                let color: String = row["color"], revision: String = row["colorRevision"], time: Double = row["colorModified"]
                return FolderAppearance(name: row["name"], color: FolderColor(rawValue: color) ?? .blue,
                    modifiedAt: Date(timeIntervalSinceReferenceDate: time), revision: UUID(uuidString: revision) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                    isDeleted: row["deleted"], trashGroup: (row["trashGroup"] as String?).flatMap(UUID.init(uuidString:)))
            }
        }
    }
    func setFolderColor(_ name: String, color: FolderColor) throws {
        let normalized = try WorkspaceFolder.name(name)
        let previous = try folderAppearances().first { $0.name == normalized } ?? FolderAppearance(name: normalized)
        let time = max(Date(), previous.modifiedAt.addingTimeInterval(0.001))
        try mergeFolderAppearances([FolderAppearance(name: normalized, color: color, modifiedAt: time, revision: UUID(), isDeleted: previous.isDeleted, trashGroup: previous.trashGroup)])
    }
    func mergeFolderAppearances(_ remote: [FolderAppearance]) throws {
        let merged = try FolderAppearance.merged(folderAppearances() + remote)
        try db.write { db in
            for style in merged {
                try db.execute(sql: "INSERT INTO folders(name,color,colorModified,colorRevision,deleted,trashGroup) VALUES (?,?,?,?,?,?) ON CONFLICT(name) DO UPDATE SET color=excluded.color,colorModified=excluded.colorModified,colorRevision=excluded.colorRevision,deleted=excluded.deleted,trashGroup=excluded.trashGroup",
                    arguments: [style.name, style.color.rawValue, style.modifiedAt.timeIntervalSinceReferenceDate, style.revision.uuidString, style.isDeleted, style.trashGroup?.uuidString])
            }
        }
    }
    func folders() throws -> [String] {
        try db.read { db in try String.fetchAll(db, sql: "SELECT name FROM folders WHERE deleted=0 ORDER BY name COLLATE NOCASE") }
    }
    func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".paperly", isDirectory: true) }
    func load(_ id: UUID) throws -> NotebookManifest {
        let m = try JSONDecoder().decode(NotebookManifest.self, from: Data(contentsOf: directory(id).appendingPathComponent("manifest.json")))
        try m.validate(); return m
    }
    private func index(_ m: NotebookManifest) throws {
        let bytes = try JSONEncoder().encode(m)
        try db.write { db in
            if let folder = m.folder { try db.execute(sql: "INSERT OR IGNORE INTO folders(name) VALUES (?)", arguments: [folder]) }
            try db.execute(sql: "INSERT INTO notebooks(id,manifest) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET manifest=excluded.manifest", arguments: [m.id.uuidString, bytes])
        }
    }
    /// Files are authoritative: rebuild index after a crash between manifest commit and SQLite update.
    func list() throws -> [NotebookSummary] {
        for url in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "paperly" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            try index(load(id))
        }
        return try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM notebooks").map { row in
                let data: Data = row["manifest"]
                let base: String? = row["base"]
                return NotebookSummary(manifest: try JSONDecoder().decode(NotebookManifest.self, from: data), baseGeneration: base.flatMap(UUID.init(uuidString:)), remoteID: row["remoteID"], remoteVersion: row["remoteVersion"], syncState: row["state"])
            }
        }
    }
    private func commit(_ manifest: NotebookManifest) throws {
        try manifest.validate()
        let dir = directory(manifest.id)
        try fm.createDirectory(at: dir.appendingPathComponent("strokes"), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        try index(manifest)
    }
    func create(title: String, template: PaperTemplate, cover: String, folder: String? = nil) throws -> NotebookManifest {
        var m = NotebookManifest(title: title, template: template, cover: cover); m.folder = folder
        try commit(m); return m
    }
    func createText(title: String, folder: String? = nil) throws -> NotebookManifest {
        var m = NotebookManifest(title: title)
        m.pages = []; m.folder = folder; m.formatVersion = 3
        let path = "text/\(UUID()).json"
        m.textFile = path
        let destination = directory(m.id).appendingPathComponent(path)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TextDocument().encoded().write(to: destination, options: .atomic)
        try commit(m); return m
    }
    func textDocument(_ id: UUID) throws -> TextDocument {
        let m = try load(id)
        guard let path = m.textFile else { throw DocumentError.invalidManifest }
        return try TextDocument.decode(Data(contentsOf: directory(id).appendingPathComponent(path)))
    }
    /// New content becomes durable before the manifest points to it; the preceding snapshot
    /// remains valid if the process exits between these two atomic writes.
    func saveText(_ content: TextDocument, title: String, notebook id: UUID) throws -> NotebookManifest {
        var m = try load(id)
        guard let previous = m.textFile else { throw DocumentError.invalidManifest }
        let bytes = try content.encoded()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Untitled document" : trimmed
        if m.title == name, (try? Data(contentsOf: directory(id).appendingPathComponent(previous))) == bytes { return m }
        let path = "text/\(UUID()).json"
        try bytes.write(to: directory(id).appendingPathComponent(path), options: .atomic)
        m.textFile = path; m.title = name; m.modifiedAt = Date(); m.generation = UUID()
        try commit(m)
        try? fm.removeItem(at: directory(id).appendingPathComponent(previous))
        return m
    }
    func recordings(_ id: UUID) throws -> [NotebookRecording] {
        try load(id).recordingItems.sorted { $0.createdAt > $1.createdAt }
    }
    func addRecording(_ bytes: Data, title: String, duration: Double, notebook id: UUID) throws -> NotebookRecording {
        guard bytes.count <= NotebookRecording.maximumBytes else { throw DocumentError.recordingTooLarge }
        var m = try load(id)
        guard m.isTextDocument, m.recordingItems.count < 100 else { throw DocumentError.invalidManifest }
        let recordingID = UUID()
        let path = "assets/audio/\(recordingID).m4a"
        let recording = NotebookRecording(id: recordingID, title: title, duration: duration, audioFile: path)
        try recording.validate()
        let destination = directory(id).appendingPathComponent(path)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: destination, options: .atomic)
        do {
            m.recordings = m.recordingItems + [recording]
            m.formatVersion = max(6, m.formatVersion); m.generation = UUID(); m.modifiedAt = Date()
            try commit(m)
            return recording
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }
    func recordingURL(_ recordingID: UUID, notebook id: UUID) throws -> URL {
        let m = try load(id)
        guard let recording = m.recordingItems.first(where: { $0.id == recordingID }) else { throw DocumentError.invalidManifest }
        try recording.validate()
        let url = directory(id).appendingPathComponent(recording.audioFile)
        guard fm.fileExists(atPath: url.path) else {
            throw DocumentError.missingAsset(recording.audioFile)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size <= NotebookRecording.maximumBytes else { throw DocumentError.recordingTooLarge }
        return url
    }
    func saveTranscript(_ transcript: RecordingTranscript, recording recordingID: UUID, notebook id: UUID) throws -> NotebookRecording {
        try transcript.validate()
        let bytes = try JSONEncoder().encode(transcript)
        guard bytes.count <= 8 * 1024 * 1024 else { throw DocumentError.tooLarge }
        var m = try load(id)
        guard let index = m.recordingItems.firstIndex(where: { $0.id == recordingID }) else { throw DocumentError.invalidManifest }
        let path = "assets/transcripts/\(recordingID).json"
        let destination = directory(id).appendingPathComponent(path)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: destination, options: .atomic)
        do {
            var items = m.recordingItems
            items[index].transcriptFile = path
            m.recordings = items; m.formatVersion = max(6, m.formatVersion); m.generation = UUID(); m.modifiedAt = Date()
            try commit(m)
            return items[index]
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }
    func transcript(recording recordingID: UUID, notebook id: UUID) throws -> RecordingTranscript {
        let m = try load(id)
        guard let recording = m.recordingItems.first(where: { $0.id == recordingID }),
              let path = recording.transcriptFile else { throw DocumentError.missingAsset("transcript") }
        let transcript = try JSONDecoder().decode(RecordingTranscript.self, from: Data(contentsOf: directory(id).appendingPathComponent(path)))
        try transcript.validate()
        return transcript
    }
    func markNotesAdded(recording recordingID: UUID, notebook id: UUID) throws {
        var m = try load(id)
        guard let index = m.recordingItems.firstIndex(where: { $0.id == recordingID }),
              m.recordingItems[index].transcriptFile != nil else { throw DocumentError.invalidManifest }
        var items = m.recordingItems
        items[index].notesAddedAt = Date()
        m.recordings = items; m.generation = UUID(); m.modifiedAt = Date()
        try commit(m)
    }
    func deleteRecording(_ recordingID: UUID, notebook id: UUID) throws {
        var m = try load(id)
        guard let recording = m.recordingItems.first(where: { $0.id == recordingID }) else { return }
        m.recordings = m.recordingItems.filter { $0.id != recordingID }
        m.generation = UUID(); m.modifiedAt = Date()
        try commit(m)
        try? fm.removeItem(at: directory(id).appendingPathComponent(recording.audioFile))
        if let path = recording.transcriptFile { try? fm.removeItem(at: directory(id).appendingPathComponent(path)) }
    }
    func saveDrawing(_ bytes: Data, notebook: UUID, page: UUID) throws -> NotebookManifest {
        var m = try load(notebook)
        guard let i = m.pages.firstIndex(where: { $0.id == page }) else { throw DocumentError.invalidManifest }
        let previous = m.pages[i].drawingFile
        if let previous, (try? Data(contentsOf: directory(notebook).appendingPathComponent(previous))) == bytes { return m }
        let path = "strokes/\(page)-\(UUID()).drawing"
        try bytes.write(to: directory(notebook).appendingPathComponent(path), options: .atomic)
        m.pages[i].drawingFile = path; m.generation = UUID(); m.modifiedAt = Date()
        try commit(m)
        if let previous { try? fm.removeItem(at: directory(notebook).appendingPathComponent(previous)) }
        return m
    }
    func drawing(notebook: UUID, page: NotebookPage) throws -> Data? {
        // A lazily displayed page may hold a manifest predating another page's save.
        let latest = try load(notebook)
        guard let current = latest.pages.first(where: { $0.id == page.id }) else { throw DocumentError.invalidManifest }
        guard let path = current.drawingFile else { return nil }
        return try Data(contentsOf: directory(notebook).appendingPathComponent(path))
    }
    /// Commit image metadata against the latest manifest, preserving any intervening ink save.
    /// Image bytes are immutable and retained after removal so an undo can restore their reference.
    func saveImages(_ images: [NotebookImage], assets: [String: Data] = [:], notebook: UUID, page: UUID) throws -> NotebookManifest {
        var m = try load(notebook)
        guard let index = m.pages.firstIndex(where: { $0.id == page }) else { throw DocumentError.invalidManifest }
        m.pages[index].imageItems = images
        m.formatVersion = max(2, m.formatVersion)
        try m.validate()
        let referenced = Set(images.map(\.assetPath))
        let dir = directory(notebook)
        // Validate the entire operation before writing any bytes.
        for (path, bytes) in assets {
            try NotebookManifest.validateImagePath(path)
            guard referenced.contains(path) else { throw DocumentError.invalidManifest }
            guard bytes.count <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
            let destination = dir.appendingPathComponent(path)
            if fm.fileExists(atPath: destination.path) {
                let existing = try imageData(notebook: notebook,
                    image: NotebookImage(assetPath: path, x: 0, y: 0, width: 1, height: 1))
                guard existing == bytes else { throw DocumentError.invalidManifest }
            }
        }
        for image in images where assets[image.assetPath] == nil {
            _ = try imageData(notebook: notebook, image: image)
        }
        for (path, bytes) in assets {
            let destination = dir.appendingPathComponent(path)
            if !fm.fileExists(atPath: destination.path) {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: destination, options: .atomic)
            }
        }
        m.generation = UUID(); m.modifiedAt = Date()
        try commit(m)
        return m
    }

    func imageData(notebook: UUID, image: NotebookImage) throws -> Data {
        try NotebookManifest.validateImagePath(image.assetPath)
        let url = directory(notebook).appendingPathComponent(image.assetPath)
        guard fm.fileExists(atPath: url.path) else { throw DocumentError.missingAsset(image.assetPath) }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw DocumentError.invalidManifest }
        guard let size = values.fileSize, size <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
        return bytes
    }

    func addPage(_ id: UUID, template: PaperTemplate) throws -> NotebookManifest {
        var m = try load(id); m.pages.append(NotebookPage(template: template)); m.generation = UUID(); m.modifiedAt = Date(); try commit(m); return m
    }
    func checkpoint(_ id: UUID) throws -> NotebookManifest {
        var m = try load(id); m.generation = UUID(); m.modifiedAt = Date(); try commit(m); return m
    }
    func rename(_ id: UUID, title: String, folder: String?) throws {
        if let folder, try folderAppearances().contains(where: { $0.name == folder && $0.isDeleted }) { throw DocumentError.folderInTrash(folder) }
        var m = try load(id); m.title = title; m.folder = folder; m.generation = UUID(); m.modifiedAt = Date(); try commit(m)
    }
    func trashNotebook(_ id: UUID, group: UUID? = nil) throws {
        var m = try load(id)
        guard !m.isTrashed else { return }
        m.trashedAt = Date(); m.trashGroup = group; m.formatVersion = max(5, m.formatVersion)
        m.generation = UUID(); m.modifiedAt = Date(); try commit(m)
    }
    func restoreNotebook(_ id: UUID) throws {
        var m = try load(id)
        guard m.isTrashed else { return }
        m.trashedAt = nil; m.trashGroup = nil; m.generation = UUID(); m.modifiedAt = Date()
        try commit(m)
        if let folder = m.folder, let style = try folderAppearances().first(where: { $0.name == folder && $0.isDeleted }) {
            try setFolderTrash(style, deleted: false, group: nil)
        }
    }
    func trashFolder(_ name: String) throws {
        let name = try WorkspaceFolder.name(name)
        let style = try folderAppearances().first { $0.name == name } ?? FolderAppearance(name: name)
        guard !style.isDeleted else { return }
        let group = UUID()
        for item in try list() where item.manifest.folder == name && !item.manifest.isTrashed { try trashNotebook(item.id, group: group) }
        try setFolderTrash(style, deleted: true, group: group)
    }
    func restoreFolder(_ name: String) throws {
        guard let style = try folderAppearances().first(where: { $0.name == name && $0.isDeleted }) else { return }
        if let group = style.trashGroup {
            for item in try list() where item.manifest.isTrashed && item.manifest.trashGroup == group { try restoreNotebook(item.id) }
        }
        try setFolderTrash(style, deleted: false, group: nil)
    }
    private func setFolderTrash(_ style: FolderAppearance, deleted: Bool, group: UUID?) throws {
        let time = max(Date(), style.modifiedAt.addingTimeInterval(0.001))
        try mergeFolderAppearances([FolderAppearance(name: style.name, color: style.color, modifiedAt: time, revision: UUID(), isDeleted: deleted, trashGroup: group)])
    }
    func exportData(_ id: UUID) throws -> Data {
        let m = try load(id)
        var assets: [String: Data] = [:]
        let dir = directory(id)
        // Include optional image assets as well as referenced strokes and source PDF.
        // This enumerator returns relative names directly. Absolute enumerated URLs
        // can use different /var aliases from the document URL on physical devices.
        if let enumerator = fm.enumerator(atPath: dir.path) {
            for case let relative as String in enumerator {
                try NotebookManifest.validatePath(relative)
                let url = dir.appendingPathComponent(relative)
                if relative != "manifest.json", (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                    assets[relative] = try Data(contentsOf: url)
                }
            }
        }
        return try NotebookArchive(manifest: m, assets: assets).encoded()
    }
    func importArchive(_ bytes: Data, asCopy: Bool = true) throws -> NotebookManifest {
        var archive = try NotebookArchive.decode(bytes)
        if asCopy { archive.manifest.id = UUID(); archive.manifest.generation = UUID(); archive.manifest.title += " (imported)" }
        let m = archive.manifest
        let staging = root.appendingPathComponent("import-\(UUID())")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for (path, data) in archive.assets {
            let url = staging.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        try JSONEncoder().encode(m).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        let target = directory(m.id)
        if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: staging) }
        else { try fm.moveItem(at: staging, to: target) }
        try index(m); return m
    }
    func attachPDF(_ data: Data, to id: UUID, pages: [NotebookPage]) throws -> NotebookManifest {
        var m = try load(id); let path = "assets/source.pdf"
        let url = directory(id).appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        m.sourcePDF = path; m.pages = pages; m.generation = UUID(); try commit(m); return m
    }
    func pdfData(_ id: UUID) throws -> Data? {
        let m = try load(id); guard let path = m.sourcePDF else { return nil }
        return try Data(contentsOf: directory(id).appendingPathComponent(path))
    }
    func setSync(_ id: UUID, base: UUID?, remote: String?, version: String?, state: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE notebooks SET base=?,remoteID=?,remoteVersion=?,state=? WHERE id=?", arguments: [base?.uuidString, remote, version, state, id.uuidString])
        }
    }
    func pruneSearchRows(_ id: UUID) throws {
        let m = try load(id)
        let valid = Set(m.isTextDocument ? ["text"] : m.pages.map { $0.id.uuidString })
        try db.write { db in
            let keys = try String.fetchAll(db, sql: "SELECT page FROM pageSearch WHERE notebook=?", arguments: [id.uuidString])
            for key in keys where !valid.contains(key) {
                try db.execute(sql: "DELETE FROM pageSearch WHERE notebook=? AND page=?", arguments: [id.uuidString, key])
            }
        }
    }
    func cachedRecognition(_ id: UUID, page: UUID?, fingerprint: String) throws -> String? {
        try db.read { db in
            try String.fetchOne(db, sql: "SELECT recognized FROM pageSearch WHERE notebook=? AND page=? AND fingerprint=?", arguments: [id.uuidString, page?.uuidString ?? "text", fingerprint])
        }
    }
    /// Reject results from an OCR job whose page changed while recognition was running.
    @discardableResult func cacheRecognition(_ text: String, notebook id: UUID, page pageID: UUID?, fingerprint: String) throws -> Bool {
        let m = try load(id)
        let page = pageID.flatMap { id in m.pages.first { $0.id == id } }
        guard pageID == nil ? m.isTextDocument : page != nil,
              NoteSearch.fingerprint(m, page: page) == fingerprint else { return false }
        let combined = text + "\n" + (page?.searchTerms ?? "")
        try db.write { db in
            try db.execute(sql: "INSERT INTO pageSearch(notebook,page,fingerprint,recognized,searchText) VALUES (?,?,?,?,?) ON CONFLICT(notebook,page) DO UPDATE SET fingerprint=excluded.fingerprint,recognized=excluded.recognized,searchText=excluded.searchText",
                arguments: [id.uuidString, pageID?.uuidString ?? "text", fingerprint, text, NoteSearch.normalized(combined)])
        }
        return true
    }
    func search(_ query: String) throws -> [NoteSearchHit] {
        let tokens = NoteSearch.tokens(query)
        guard !tokens.isEmpty else { return [] }
        let conditions = tokens.map { _ in "instr(searchText, ?) > 0" }.joined(separator: " AND ")
        let rows = try db.read { db in try Row.fetchAll(db, sql: "SELECT * FROM pageSearch WHERE " + conditions + " LIMIT 2000", arguments: StatementArguments(tokens)) }
        var hits: [NoteSearchHit] = []
        var manifests: [UUID: NotebookManifest] = [:]
        for row in rows {
            let rawID: String = row["notebook"], rawPage: String = row["page"], fingerprint: String = row["fingerprint"]
            guard let id = UUID(uuidString: rawID) else { continue }
            let m: NotebookManifest
            if let cached = manifests[id] { m = cached }
            else { guard let loaded = try? load(id) else { continue }; m = loaded; manifests[id] = loaded }
            let pageID = UUID(uuidString: rawPage)
            let index = pageID.flatMap { target in m.pages.firstIndex { $0.id == target } }
            let page = index.map { m.pages[$0] }
            guard pageID == nil ? m.isTextDocument : page != nil,
                  NoteSearch.fingerprint(m, page: page) == fingerprint else { continue }
            let text: String = row["recognized"]
            let preview = NoteSearch.excerpt(text + "\n" + (page?.searchTerms ?? ""), query: query)
            hits.append(NoteSearchHit(notebookID: id, pageID: pageID, pageNumber: index.map { $0 + 1 }, text: String(preview.prefix(240))))
            if hits.count == 200 { break }
        }
        return hits
    }
    func saveSearchTerms(_ text: String, notebook id: UUID, page pageID: UUID) throws -> NotebookManifest {
        var m = try load(id)
        guard let index = m.pages.firstIndex(where: { $0.id == pageID }), text.utf8.count <= 64 * 1024 else { throw DocumentError.invalidManifest }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        m.pages[index].searchTerms = trimmed.isEmpty ? nil : trimmed
        m.formatVersion = max(4, m.formatVersion); m.generation = UUID(); m.modifiedAt = Date()
        try commit(m); return m
    }
    func storageBytes() throws -> Int64 {
        var total: Int64 = 0
        if let files = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in files { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }
    func thumbnailData(_ id: UUID, page: UUID) throws -> Data? {
        let url = root.appendingPathComponent("Thumbnails/\(id)-\(page).png")
        guard fm.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }
    func thumbnail(_ id: UUID, page: UUID, data: Data) throws {
        let dir = root.appendingPathComponent("Thumbnails")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent("\(id)-\(page).png"), options: .atomic)
    }
}
