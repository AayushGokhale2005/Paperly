import Foundation

public enum NoteSearch {
    public static func normalized(_ text: String) -> String {
        var value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let symbols = ["−": "-", "×": "*", "÷": "/", "≤": "<=", "≥": ">=", "≠": "!=", "²": "^2", "³": "^3"]
        for (from, to) in symbols { value = value.replacingOccurrences(of: from, with: to) }
        let names = ["alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "theta": "θ", "lambda": "λ", "pi": "π", "sigma": "σ", "sum": "∑", "integral": "∫", "infinity": "∞", "sqrt": "√"]
        for (from, to) in names { value = value.replacingOccurrences(of: "\\b" + from + "\\b", with: to, options: .regularExpression) }
        return value.precomposedStringWithCanonicalMapping
    }
    public static func tokens(_ query: String) -> [String] {
        normalized(String(query.prefix(256))).split(whereSeparator: \.isWhitespace).prefix(32).map(String.init)
    }
    public static func excerpt(_ text: String, query: String) -> String {
        let needles = tokens(query)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let matching = lines.first { line in
            let normalizedLine = normalized(line)
            return needles.contains { normalizedLine.contains($0) }
        }
        return String((matching ?? text).prefix(240))
    }
    public static func fingerprint(_ manifest: NotebookManifest, page: NotebookPage?) -> String {
        if let page { return "ink-1:\(page.drawingFile ?? "empty"):\(page.width):\(page.height):\(page.searchTerms ?? "")" }
        return "text-1:" + (manifest.textFile ?? "")
    }
}

struct NoteSearchHit: Identifiable, Sendable {
    var notebookID: UUID
    var pageID: UUID?
    var pageNumber: Int?
    var text: String
    var id: String { notebookID.uuidString + ":" + (pageID?.uuidString ?? "text") }
}
