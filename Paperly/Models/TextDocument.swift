import Foundation

public enum TextBlockKind: String, Codable, CaseIterable, Sendable {
    case paragraph, heading1, heading2, bullet, numbered, checklist, quote, code
    public var title: String {
        switch self {
        case .paragraph: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .bullet: "Bulleted list"
        case .numbered: "Numbered list"
        case .checklist: "To-do list"
        case .quote: "Quote"
        case .code: "Code"
        }
    }
    public var symbol: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1, .heading2: "textformat.size"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .checklist: "checklist"
        case .quote: "quote.opening"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
    public var continuesOnReturn: Bool { [.bullet, .numbered, .checklist].contains(self) }
}

public struct TextBlock: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: TextBlockKind
    public var text: String
    public var checked: Bool
    public init(id: UUID = UUID(), kind: TextBlockKind = .paragraph, text: String = "", checked: Bool = false) {
        self.id = id; self.kind = kind; self.text = text; self.checked = checked
    }
}

/// Platform-independent blocks carried inside the same portable .paperly format as ink notebooks.
public struct TextDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var blocks: [TextBlock]
    public init(blocks: [TextBlock] = [TextBlock()]) { self.blocks = blocks }
    public func validate() throws {
        guard version == 1, !blocks.isEmpty, blocks.count <= 50_000,
              Set(blocks.map(\.id)).count == blocks.count,
              blocks.allSatisfy({ $0.text.utf8.count <= 2 * 1024 * 1024 }) else { throw DocumentError.invalidManifest }
    }
    public func encoded() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 32 * 1024 * 1024 else { throw DocumentError.tooLarge }
        return data
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32 * 1024 * 1024 else { throw DocumentError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate(); return value
    }
    public func markdown(title: String) -> String {
        var number = 0
        let lines = blocks.map { block -> String in
            if block.kind == .numbered { number += 1 } else { number = 0 }
            switch block.kind {
            case .paragraph: return block.text
            case .heading1: return "## " + block.text
            case .heading2: return "### " + block.text
            case .bullet: return "- " + block.text.replacingOccurrences(of: "\n", with: "\n  ")
            case .numbered: return "\(number). " + block.text.replacingOccurrences(of: "\n", with: "\n   ")
            case .checklist: return "- [\(block.checked ? "x" : " ")] " + block.text
            case .quote: return "> " + block.text.replacingOccurrences(of: "\n", with: "\n> ")
            case .code:
                // Choose a fence longer than any backtick run in the content.
                let longest = block.text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
                let fence = String(repeating: "`", count: max(3, longest + 1))
                return fence + "\n" + block.text + "\n" + fence
            }
        }
        return "# " + title + "\n\n" + lines.joined(separator: "\n\n") + "\n"
    }
}
