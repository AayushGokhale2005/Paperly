import XCTest
@testable import PaperlyCore

final class NoteSearchTests: XCTestCase {
    func testSymbolNamesAndUnicodeNormalizeToSameSearch() {
        for (query, ink) in [("alpha", "α"), ("pi", "π"), ("integral", "∫"), ("infinity", "∞"), ("x^2", "x²"), ("<=", "≤"), ("A-B", "a−b")] {
            XCTAssertEqual(NoteSearch.normalized(query), NoteSearch.normalized(ink))
        }
        XCTAssertEqual(NoteSearch.normalized("RÉSUMÉ"), "resume")
        XCTAssertEqual(NoteSearch.normalized("alphabet"), "alphabet", "Symbol aliases must not replace pieces of words")
        XCTAssertEqual(NoteSearch.tokens("  integral   x² "), ["∫", "x^2"])
    }
    func testExcerptShowsTheMatchingWordOrManualSymbol() {
        XCTAssertEqual(NoteSearch.excerpt("Introduction\nChoose the next milestone\nOther notes", query: "milestone"), "Choose the next milestone")
        XCTAssertEqual(NoteSearch.excerpt("No math here\n∫ customname", query: "integral"), "∫ customname")
    }
    func testColorMergeIsDeterministicAndPreservesOtherFolders() throws {
        let a = FolderAppearance(name: "School", color: .red, modifiedAt: Date(timeIntervalSinceReferenceDate: 10), revision: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = FolderAppearance(name: "School", color: .green, modifiedAt: a.modifiedAt, revision: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let empty = FolderAppearance(name: "Empty folder")
        let left = try FolderAppearance.merged([a, b, empty])
        XCTAssertEqual(left, try FolderAppearance.merged([empty, b, a]))
        XCTAssertEqual(left.first { $0.name == "School" }?.color, .green)
        XCTAssertEqual(left.first { $0.name == "Empty folder" }?.color, .blue)
    }
    func testManualSearchTermsAreVersionedAndPortable() throws {
        var m = NotebookManifest(title: "Math")
        m.pages[0].searchTerms = "∫ alpha"
        XCTAssertThrowsError(try m.validate())
        m.formatVersion = 4
        let restored = try NotebookArchive.decode(NotebookArchive(manifest: m, assets: [:]).encoded())
        XCTAssertEqual(restored.manifest.pages[0].searchTerms, "∫ alpha")
        m.pages[0].searchTerms = String(repeating: "a", count: 64 * 1024 + 1)
        XCTAssertThrowsError(try m.validate())
    }
}
