import Foundation

public enum WorkspaceFolder {
    public static func name(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= 120, !result.contains("/"), !result.contains("\0") else { throw DocumentError.invalidManifest }
        return result
    }
    /// Additive union: concurrent folder creation never removes another device's folder.
    /// Deletion state is merged separately through FolderAppearance.
    public static func merge(_ local: [String], _ remote: [String]) throws -> [String] {
        try Set((local + remote).map { try name($0) }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

public enum FolderColor: String, CaseIterable, Codable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, gray
}

public struct FolderAppearance: Codable, Equatable, Sendable {
    public var name: String
    public var color: FolderColor
    public var modifiedAt: Date
    public var revision: UUID
    public var deleted: Bool?
    public var trashGroup: UUID?
    public var isDeleted: Bool { deleted == true }
    public init(name: String, color: FolderColor = .blue, modifiedAt: Date = Date(timeIntervalSinceReferenceDate: 0),
                revision: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, isDeleted: Bool = false, trashGroup: UUID? = nil) {
        self.name = name; self.color = color; self.modifiedAt = modifiedAt; self.revision = revision; self.deleted = isDeleted ? true : nil; self.trashGroup = trashGroup
    }
    public func newer(than other: Self) -> Bool {
        modifiedAt == other.modifiedAt ? revision.uuidString > other.revision.uuidString : modifiedAt > other.modifiedAt
    }
    public static func merged(_ values: [Self]) throws -> [Self] {
        var result: [String: Self] = [:]
        for var value in values {
            value.name = try WorkspaceFolder.name(value.name)
            guard value.modifiedAt.timeIntervalSinceReferenceDate.isFinite else { throw DocumentError.invalidManifest }
            if let current = result[value.name], !value.newer(than: current) { continue }
            result[value.name] = value
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
