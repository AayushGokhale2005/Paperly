import XCTest
@testable import PaperlyCore

final class PagePullTests: XCTestCase {
    func testPullAtLastPageAddsButInteriorPanningDoesNot() {
        XCTAssertNil(PagePullAction.resolve(offset: 300, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 2, pageCount: 3))
        XCTAssertNil(PagePullAction.resolve(offset: 570, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 2, pageCount: 3))
        XCTAssertEqual(PagePullAction.resolve(offset: 580, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 2, pageCount: 3), .add)
        XCTAssertEqual(PagePullAction.resolve(offset: 580, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 0, pageCount: 3), .next)
    }
    func testPreviousPageAndDiagonalGuards() {
        XCTAssertEqual(PagePullAction.resolve(offset: -100, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 1, pageCount: 3), .previous)
        XCTAssertNil(PagePullAction.resolve(offset: -100, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 0, pageCount: 3))
        XCTAssertNil(PagePullAction.resolve(offset: 580, minimum: -12, maximum: 500, crossOverscroll: 80, pageIndex: 2, pageCount: 3))
        XCTAssertNil(PagePullAction.resolve(offset: .nan, minimum: -12, maximum: 500, crossOverscroll: 0, pageIndex: 2, pageCount: 3))
    }
}
