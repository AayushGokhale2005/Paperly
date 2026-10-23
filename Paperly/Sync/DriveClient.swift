import Foundation

/// Every commit creates an immutable snapshot. No request overwrites an existing notebook.
/// Branches are detected from generation/parent properties across all visible snapshots.
actor DriveClient {
    let account: GoogleAccount
    let stateDirectory: URL
    private let session = URLSession(configuration: .default)
    private let base = "https://www.googleapis.com/drive/v3/files"
    struct Listing: Decodable { var files: [RemoteSnapshot]; var nextPageToken: String? }
    struct UploadState: Codable { var location: URL; var generation: UUID; var byteCount: Int }
    init(account: GoogleAccount, stateDirectory: URL) { self.account = account; self.stateDirectory = stateDirectory }
    private func request(_ url: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let endpoint = URL(string: url) else { throw DriveError.invalidResponse }
        var req = URLRequest(url: endpoint); req.httpMethod = method; req.httpBody = body
        req.setValue("Bearer \(try await account.token())", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DriveError.response((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return (data, http)
    }
    private func list(query: String) async throws -> [RemoteSnapshot] {
        var files: [RemoteSnapshot] = [], next: String?
        repeat {
            var parts = URLComponents(string: base)!
            parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,version,appProperties)"), URLQueryItem(name: "pageSize", value: "1000")]
            if let next { parts.queryItems?.append(URLQueryItem(name: "pageToken", value: next)) }
            let (bytes, _) = try await request(parts.url!.absoluteString)
            let response = try JSONDecoder().decode(Listing.self, from: bytes)
            files += response.files; next = response.nextPageToken
        } while next != nil
        return files
    }
    func folder() async throws -> String {
        let matches = try await list(query: "trashed=false and mimeType='application/vnd.google-apps.folder' and appProperties has { key='paperlyFolder' and value='v1' }")
        if let first = matches.sorted(by: { $0.id < $1.id }).first { return first.id }
        let body = try JSONSerialization.data(withJSONObject: ["name": "Paperly", "mimeType": "application/vnd.google-apps.folder", "appProperties": ["paperlyFolder": "v1"]])
        let (data, _) = try await request(base, method: "POST", body: body)
        return try JSONDecoder().decode(RemoteSnapshot.self, from: data).id
    }
    /// Folder colors use a deterministic last-edited register; notebook contents are unaffected.
    func syncFolderAppearances(_ local: [FolderAppearance], parent: String) async throws -> [FolderAppearance] {
        let files = try await list(query: "trashed=false and mimeType='application/vnd.google-apps.folder' and appProperties has { key='paperlyWorkspaceFolder' and value='1' }")
        let remote: [(RemoteSnapshot, FolderAppearance)] = files.compactMap { file in
            guard let raw = file.name, let name = try? WorkspaceFolder.name(raw) else { return nil }
            let props = file.appProperties ?? [:]
            let time = props["colorModified"].flatMap(Double.init) ?? 0
            guard time.isFinite else { return nil }
            let appearance = FolderAppearance(name: name, color: FolderColor(rawValue: props["folderColor"] ?? "") ?? .blue,
                modifiedAt: Date(timeIntervalSinceReferenceDate: time),
                revision: props["colorRevision"].flatMap(UUID.init(uuidString:)) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, isDeleted: props["folderDeleted"] == "1", trashGroup: props["trashGroup"].flatMap(UUID.init(uuidString:)))
            return (file, appearance)
        }
        let merged = try FolderAppearance.merged(local + remote.map { $0.1 })
        for style in merged {
            let matching = remote.filter { $0.1.name == style.name }
            let props = ["paperlyWorkspaceFolder": "1", "folderColor": style.color.rawValue,
                         "colorModified": String(style.modifiedAt.timeIntervalSinceReferenceDate), "colorRevision": style.revision.uuidString, "folderDeleted": style.isDeleted ? "1" : "0", "trashGroup": style.trashGroup?.uuidString ?? ""]
            if matching.isEmpty {
                let body = try JSONSerialization.data(withJSONObject: ["name": style.name, "parents": [parent],
                    "mimeType": "application/vnd.google-apps.folder", "appProperties": props])
                _ = try await request(base, method: "POST", body: body)
            } else {
                for (file, existing) in matching where style != existing {
                    let body = try JSONSerialization.data(withJSONObject: ["appProperties": (file.appProperties ?? [:]).merging(props) { _, new in new }])
                    _ = try await request(base + "/" + file.id, method: "PATCH", body: body)
                }
            }
        }
        return merged
    }
    func workspaceFolders() async throws -> [String] {
        let files = try await list(query: "trashed=false and mimeType='application/vnd.google-apps.folder' and appProperties has { key='paperlyWorkspaceFolder' and value='1' }")
        return Array(Set(files.compactMap { file in file.name.flatMap { try? WorkspaceFolder.name($0) } }))
    }
    func createWorkspaceFolder(_ name: String, parent: String) async throws {
        let validated = try WorkspaceFolder.name(name)
        let body = try JSONSerialization.data(withJSONObject: ["name": validated, "parents": [parent],
            "mimeType": "application/vnd.google-apps.folder", "appProperties": ["paperlyWorkspaceFolder": "1"]])
        _ = try await request(base, method: "POST", body: body)
    }
    func snapshots() async throws -> [RemoteSnapshot] {
        // Search app-created snapshots across folders, including if a user moves a notebook.
        try await list(query: "trashed=false and appProperties has { key='paperlyFormat' and value='1' }")
    }
    func download(_ id: String) async throws -> Data { try await request(base + "/\(id)?alt=media").0 }
    func upload(data: Data, manifest: NotebookManifest, parent: UUID?, folder: String, ancestors: [UUID] = []) async throws -> RemoteSnapshot {
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let stateURL = stateDirectory.appendingPathComponent(manifest.id.uuidString + ".json")
        var state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(UploadState.self, from: $0) }
        if state?.generation != manifest.generation || state?.byteCount != data.count { state = nil }
        if state == nil {
            var props = ["paperlyFormat": "1", "notebookID": manifest.id.uuidString, "generation": manifest.generation.uuidString]
            props["parent"] = parent?.uuidString
            guard ancestors.count <= 90 else { throw DriveError.invalidResponse }
            for ancestor in ancestors { props["ancestor_" + ancestor.uuidString] = "1" }
            let body = try JSONSerialization.data(withJSONObject: ["name": "\(manifest.title) — \(manifest.generation.uuidString.prefix(8)).paperly", "parents": [folder], "appProperties": props])
            let (_, response) = try await request("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,version,appProperties", method: "POST", body: body)
            guard let location = response.value(forHTTPHeaderField: "Location"), let url = URL(string: location), url.scheme == "https", url.host == "www.googleapis.com" else { throw DriveError.invalidResponse }
            state = UploadState(location: url, generation: manifest.generation, byteCount: data.count)
            try JSONEncoder().encode(state!).write(to: stateURL, options: .atomic)
        }
        guard let state else { throw DriveError.invalidResponse }
        // Query the durable session before sending bytes, allowing resume after relaunch.
        var offset = 0
        var probe = URLRequest(url: state.location); probe.httpMethod = "PUT"
        probe.setValue("Bearer \(try await account.token())", forHTTPHeaderField: "Authorization")
        probe.setValue("bytes */\(data.count)", forHTTPHeaderField: "Content-Range")
        probe.setValue("0", forHTTPHeaderField: "Content-Length")
        let (probeData, probeResponse) = try await session.data(for: probe)
        guard let http = probeResponse as? HTTPURLResponse else { throw DriveError.invalidResponse }
        if (200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: stateURL)
            return try JSONDecoder().decode(RemoteSnapshot.self, from: probeData)
        }
        if http.statusCode == 404 || http.statusCode == 410 {
            try? FileManager.default.removeItem(at: stateURL); throw DriveError.response(http.statusCode)
        }
        guard http.statusCode == 308 else { throw DriveError.response(http.statusCode) }
        if let range = http.value(forHTTPHeaderField: "Range"), let end = range.split(separator: "-").last.flatMap({ Int($0) }) { offset = end + 1 }
        while offset < data.count {
            try Task.checkCancellation()
            let end = min(offset + 1024 * 1024, data.count)
            var req = URLRequest(url: state.location); req.httpMethod = "PUT"
            req.setValue("Bearer \(try await account.token())", forHTTPHeaderField: "Authorization")
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.setValue("bytes \(offset)-\(end - 1)/\(data.count)", forHTTPHeaderField: "Content-Range")
            let (bytes, response) = try await session.upload(for: req, from: data.subdata(in: offset..<end))
            guard let http = response as? HTTPURLResponse else { throw DriveError.invalidResponse }
            if (200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: stateURL)
                return try JSONDecoder().decode(RemoteSnapshot.self, from: bytes)
            }
            guard http.statusCode == 308 else { throw DriveError.response(http.statusCode) }
            guard let range = http.value(forHTTPHeaderField: "Range"), let last = range.split(separator: "-").last.flatMap({ Int($0) }), last + 1 > offset else { throw DriveError.invalidResponse }
            offset = last + 1
        }
        throw DriveError.invalidResponse
    }
}
