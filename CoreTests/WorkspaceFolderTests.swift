import XCTest
@testable import PaperlyCore

final class WorkspaceFolderTests: XCTestCase {
    func testConcurrentEmptyFolderCreationMergesWithoutLoss() throws {
        let left = ["School", "Projects"], right = ["School", "Journal"]
        let merged = try WorkspaceFolder.merge(left, right)
        XCTAssertEqual(Set(merged), ["School", "Projects", "Journal"])
        XCTAssertEqual(try WorkspaceFolder.merge(merged, right), merged)
        XCTAssertEqual(Set(try WorkspaceFolder.merge(right, left)), Set(merged))
    }
    func testInvalidNamesAreRejectedBeforeMerge() throws {
        XCTAssertEqual(try WorkspaceFolder.name("  Empty folder  "), "Empty folder")
        for name in ["", " ", "a/b", "bad\0name", String(repeating: "a", count: 121)] {
            XCTAssertThrowsError(try WorkspaceFolder.merge(["Safe"], [name]))
        }
    }
}
