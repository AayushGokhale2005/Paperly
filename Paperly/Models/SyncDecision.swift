import Foundation

public enum SyncDecision: Equatable, Sendable {
    case unchanged, upload, download, conflict
    public static func resolve(local: UUID, base: UUID?, remote: UUID?) -> Self {
        guard let remote else { return base == nil ? .upload : .conflict }
        if remote == local { return .unchanged }
        guard let base else { return .conflict }
        if local == base { return .download }
        if remote == base { return .upload }
        return .conflict
    }
}

public struct RemoteSnapshot: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String?
    public var version: String?
    public var appProperties: [String: String]?
    public var notebookID: UUID? { appProperties?["notebookID"].flatMap(UUID.init(uuidString:)) }
    public var generation: UUID? { appProperties?["generation"].flatMap(UUID.init(uuidString:)) }
    public var parent: UUID? { appProperties?["parent"].flatMap(UUID.init(uuidString:)) }
    public var ancestors: [UUID] {
        let merged = (appProperties ?? [:]).keys.compactMap { key -> UUID? in
            guard key.hasPrefix("ancestor_") else { return nil }
            return UUID(uuidString: String(key.dropFirst("ancestor_".count)))
        }
        return [parent].compactMap { $0 } + merged
    }
    public static func heads(_ snapshots: [Self]) -> [Self] {
        let ancestors = Set(snapshots.flatMap(\.ancestors))
        var seen: Set<UUID> = []
        return snapshots.sorted { $0.id < $1.id }.filter {
            guard let generation = $0.generation, !ancestors.contains(generation) else { return false }
            return seen.insert(generation).inserted
        }
    }
}
