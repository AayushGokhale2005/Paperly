import Foundation

public enum PaperTemplate: String, Codable, CaseIterable, Sendable {
    case blank, ruled, grid, dot
}

public struct NotebookImage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var assetPath: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var rotation: Double

    public init(id: UUID = UUID(), assetPath: String, x: Double, y: Double,
                width: Double, height: Double, rotation: Double = 0) {
        self.id = id; self.assetPath = assetPath; self.x = x; self.y = y
        self.width = width; self.height = height; self.rotation = rotation
    }
}

public struct NotebookPage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var template: PaperTemplate
    public var drawingFile: String?
    public var pdfPage: Int?
    public var width: Double
    public var height: Double
    /// Optional on disk so v1 manifests decode without a migration pass.
    public var searchTerms: String?
    public var images: [NotebookImage]?
    public var imageItems: [NotebookImage] {
        get { images ?? [] }
        set { images = newValue.isEmpty ? nil : newValue }
    }
    public init(id: UUID = UUID(), template: PaperTemplate = .ruled, drawingFile: String? = nil, pdfPage: Int? = nil, width: Double = 768, height: Double = 1024, images: [NotebookImage] = []) {
        self.id = id; self.template = template; self.drawingFile = drawingFile
        self.pdfPage = pdfPage; self.width = width; self.height = height
        self.images = images.isEmpty ? nil : images
    }
}

public struct NotebookManifest: Codable, Identifiable, Equatable, Sendable {
    public static let currentVersion = 6
    public static let maximumImageBytes = 40 * 1024 * 1024
    public var formatVersion: Int = 2
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var generation: UUID
    public var folder: String?
    public var cover: String
    public var pages: [NotebookPage]
    public var sourcePDF: String?
    public var recordings: [NotebookRecording]?
    public var recordingItems: [NotebookRecording] { recordings ?? [] }
    public var trashedAt: Date?
    public var trashGroup: UUID?
    public var isTrashed: Bool { trashedAt != nil }
    public var textFile: String?
    public var isTextDocument: Bool { textFile != nil }
    public init(id: UUID = UUID(), title: String, template: PaperTemplate = .ruled, cover: String = "blue") {
        self.id = id; self.title = title; self.createdAt = Date(); self.modifiedAt = Date()
        self.generation = UUID(); self.cover = cover; self.pages = [NotebookPage(template: template)]
    }
    public func validate() throws {
        guard (1...Self.currentVersion).contains(formatVersion) else { throw DocumentError.unsupportedVersion(formatVersion) }
        if let trashedAt { guard formatVersion >= 5, trashedAt.timeIntervalSinceReferenceDate.isFinite else { throw DocumentError.invalidManifest } }
        if trashGroup != nil { guard formatVersion >= 5, trashedAt != nil else { throw DocumentError.invalidManifest } }
        if !recordingItems.isEmpty {
            guard formatVersion >= 6, isTextDocument, recordingItems.count <= 100, Set(recordingItems.map(\.id)).count == recordingItems.count else { throw DocumentError.invalidManifest }
            for recording in recordingItems { try recording.validate() }
        }
        if let textFile {
            guard formatVersion >= 3, pages.isEmpty, sourcePDF == nil else { throw DocumentError.invalidManifest }
            try Self.validateTextPath(textFile)
        } else {
            guard !pages.isEmpty else { throw DocumentError.invalidManifest }
        }
        guard pages.count <= 100_000, Set(pages.map(\.id)).count == pages.count else { throw DocumentError.invalidManifest }
        for page in pages {
            if let terms = page.searchTerms {
                guard formatVersion >= 4, terms.utf8.count <= 64 * 1024 else { throw DocumentError.invalidManifest }
            }
            guard page.width.isFinite, page.height.isFinite, page.width > 0, page.height > 0,
                  page.width <= 20_000, page.height <= 20_000,
                  page.pdfPage.map({ $0 >= 0 }) ?? true else { throw DocumentError.invalidManifest }
            if let name = page.drawingFile { try Self.validatePath(name) }
            guard Set(page.imageItems.map(\.id)).count == page.imageItems.count,
                  page.imageItems.isEmpty || formatVersion >= 2 else { throw DocumentError.invalidManifest }
            for image in page.imageItems {
                guard image.x.isFinite, image.y.isFinite, image.rotation.isFinite,
                      image.width.isFinite, image.height.isFinite,
                      image.width >= 1, image.height >= 1,
                      image.width <= 20_000, image.height <= 20_000 else { throw DocumentError.invalidManifest }
                try Self.validateImagePath(image.assetPath)
            }
        }
        if let sourcePDF { try Self.validatePath(sourcePDF) }
    }
    public static func validatePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { throw DocumentError.unsafePath }
    }
    public static func validateTextPath(_ path: String) throws {
        try validatePath(path)
        let parts = path.split(separator: "/")
        guard parts.count == 2, parts[0] == "text", parts[1].hasSuffix(".json"),
              UUID(uuidString: String(parts[1].dropLast(5))) != nil else { throw DocumentError.unsafePath }
    }
    public static func validateImagePath(_ path: String) throws {
        try validatePath(path)
        let components = path.split(separator: "/")
        guard components.count == 3, components[0] == "assets", components[1] == "images",
              components[2].hasSuffix(".png"),
              UUID(uuidString: String(components[2].dropLast(4))) != nil else { throw DocumentError.unsafePath }
    }
}

public enum DocumentError: Error, LocalizedError {
    case unsupportedVersion(Int), invalidManifest, unsafePath, missingAsset(String), tooLarge, imageTooLarge, folderInTrash(String), recordingTooLarge
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): "Notebook format \(v) is unsupported. Update Paperly to open it."
        case .invalidManifest: "The notebook manifest is invalid."
        case .unsafePath: "The notebook contains an unsafe asset path."
        case .missingAsset(let name): "The notebook is missing \(name)."
        case .tooLarge: "This notebook exceeds the 512 MB portable archive limit."
        case .recordingTooLarge: "This recording exceeds the 256 MB audio limit."
        case .imageTooLarge: "This image exceeds the 40 MB image limit."
        case .folderInTrash(let name): "The folder \(name) is in Trash. Restore it first or choose a different name."
        }
    }
}

/// Portable single-file .paperly container; base64 assets retain editable PencilKit data.
/// Used only at import/export/sync boundaries; local editing writes individual page files.
public struct NotebookArchive: Codable, Sendable {
    public var manifest: NotebookManifest
    public var assets: [String: Data]
    public init(manifest: NotebookManifest, assets: [String: Data]) { self.manifest = manifest; self.assets = assets }
    public func validate() throws {
        try manifest.validate()
        for key in assets.keys { try NotebookManifest.validatePath(key) }
        let images = manifest.pages.flatMap(\.imageItems)
        for image in images {
            if let bytes = assets[image.assetPath], bytes.count > NotebookManifest.maximumImageBytes {
                throw DocumentError.imageTooLarge
            }
        }
        let references = manifest.pages.compactMap(\.drawingFile)
            + [manifest.sourcePDF, manifest.textFile].compactMap { $0 } + images.map(\.assetPath)
            + manifest.recordingItems.flatMap { [$0.audioFile, $0.transcriptFile].compactMap { $0 } }
        for path in references where assets[path] == nil { throw DocumentError.missingAsset(path) }
        for recording in manifest.recordingItems {
            if let bytes = assets[recording.audioFile], bytes.count > NotebookRecording.maximumBytes { throw DocumentError.recordingTooLarge }
            if let path = recording.transcriptFile, let bytes = assets[path] {
                guard bytes.count <= 8 * 1024 * 1024 else { throw DocumentError.tooLarge }
                try JSONDecoder().decode(RecordingTranscript.self, from: bytes).validate()
            }
        }
        if let path = manifest.textFile, let data = assets[path] { _ = try TextDocument.decode(data) }
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 512 * 1024 * 1024 else { throw DocumentError.tooLarge }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 512 * 1024 * 1024 else { throw DocumentError.tooLarge }
        let archive = try JSONDecoder().decode(Self.self, from: data); try archive.validate(); return archive
    }
}
