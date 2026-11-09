import XCTest
@testable import ExperienceCore

final class PostDraftTests: XCTestCase {
    func testWhitespaceOnlyIsRejected() {
        let draft = PostDraft(text: "   ", authorRecordName: "_abc")
        XCTAssertThrowsError(try draft.makePost()) { error in
            XCTAssertEqual(error as? FeedError, .missingPhoto)
        }
    }

    func testPhotoWithoutCaptionIsRejected() {
        let draft = PostDraft(text: "  ", imageData: Data([0x01]), authorRecordName: "  _user  ")
        XCTAssertThrowsError(try draft.makePost()) { error in
            XCTAssertEqual(error as? FeedError, .missingCaption)
        }
    }

    func testCaptionIsTrimmed() throws {
        let post = try PostDraft(text: "  Hello  ", imageData: Data([0x01]), authorRecordName: " _user ").makePost()
        XCTAssertEqual(post.text, "Hello")
        XCTAssertEqual(post.authorRecordName, "_user")
    }
}
