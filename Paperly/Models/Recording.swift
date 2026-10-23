import Foundation

public struct NotebookRecording: Codable, Identifiable, Equatable, Sendable {
    public static let maximumBytes = 256 * 1024 * 1024
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var duration: Double
    public var audioFile: String
    public var transcriptFile: String?
    public var notesAddedAt: Date?
    public init(id: UUID = UUID(), title: String, duration: Double, audioFile: String, createdAt: Date = Date()) {
        self.id = id; self.title = title; self.duration = duration; self.audioFile = audioFile; self.createdAt = createdAt
    }
    public func validate() throws {
        guard duration.isFinite, duration >= 0, duration <= 86_400, !title.isEmpty, title.utf8.count <= 2048,
              createdAt.timeIntervalSinceReferenceDate.isFinite else { throw DocumentError.invalidManifest }
        try Self.validateAsset(audioFile, directory: "audio", extensions: ["caf", "m4a", "wav", "mp3", "aiff", "aif", "flac"])
        if let transcriptFile { try Self.validateAsset(transcriptFile, directory: "transcripts", extensions: ["json"]) }
        if let notesAddedAt { guard notesAddedAt.timeIntervalSinceReferenceDate.isFinite, transcriptFile != nil else { throw DocumentError.invalidManifest } }
    }
    public static func validateAsset(_ path: String, directory: String, extensions: Set<String>) throws {
        try NotebookManifest.validatePath(path)
        let pieces = path.split(separator: "/")
        let url = URL(fileURLWithPath: path)
        guard pieces.count == 3, pieces[0] == "assets", pieces[1] == Substring(directory),
              extensions.contains(url.pathExtension.lowercased()), UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { throw DocumentError.unsafePath }
    }
}

public struct RecordingTranscript: Codable, Equatable, Sendable {
    public struct Segment: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
        public init(start: Double, end: Double, text: String) { self.start = start; self.end = end; self.text = text }
    }
    public var version = 1
    public var text: String
    public var segments: [Segment]
    public init(text: String, segments: [Segment] = []) { self.text = text; self.segments = segments }
    public func validate() throws {
        guard version == 1, text.utf8.count <= 2 * 1024 * 1024, segments.count <= 100_000,
              segments.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && $0.text.utf8.count <= 64 * 1024 }) else { throw DocumentError.invalidManifest }
    }
}

/// Word-boundary chunks keep long meetings within the local language model's context.
public enum TranscriptChunks {
    public static func split(_ text: String, maximumBytes: Int = 3000) -> [String] {
        let budget = max(256, maximumBytes)
        var chunks: [String] = [], current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if !current.isEmpty && current.utf8.count + word.utf8.count + 1 > budget { chunks.append(current); current = "" }
            // Extremely long tokens are split at Character boundaries, preserving Unicode.
            if word.utf8.count > budget {
                for character in word {
                    if !current.isEmpty && current.utf8.count + String(character).utf8.count > budget { chunks.append(current); current = "" }
                    current.append(character)
                }
            } else { if !current.isEmpty { current += " " }; current += word }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// Converts the constrained Markdown returned by the on-device language model into
/// Paperly's native blocks. Unknown Markdown remains readable paragraph text.
public enum GeneratedNoteBlocks {
    public static func parse(_ markdown: String) -> [TextBlock] {
        var blocks: [TextBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: String?

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(TextBlock(text: text)) }
            paragraph.removeAll()
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let activeFence = fence {
                if line.hasPrefix(activeFence) {
                    blocks.append(TextBlock(kind: .code, text: code.joined(separator: "\n")))
                    code.removeAll(); fence = nil
                } else {
                    code.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("```") {
                flushParagraph()
                fence = "```"
            } else if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(TextBlock(kind: .heading2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(TextBlock(kind: .heading1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                flushParagraph()
                let checked = !line.hasPrefix("- [ ] ")
                blocks.append(TextBlock(kind: .checklist, text: String(line.dropFirst(6)), checked: checked))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                blocks.append(TextBlock(kind: .bullet, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                flushParagraph()
                blocks.append(TextBlock(kind: .quote, text: String(line.dropFirst(2))))
            } else if let markerEnd = numberedMarkerEnd(in: line) {
                flushParagraph()
                blocks.append(TextBlock(kind: .numbered, text: String(line[markerEnd...])))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        if fence != nil, !code.isEmpty { blocks.append(TextBlock(kind: .code, text: code.joined(separator: "\n"))) }
        return blocks
    }

    private static func numberedMarkerEnd(in line: String) -> String.Index? {
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber { index = line.index(after: index) }
        guard index > line.startIndex, index < line.endIndex, line[index] == "." else { return nil }
        let space = line.index(after: index)
        guard space < line.endIndex, line[space] == " " else { return nil }
        return line.index(after: space)
    }
}
