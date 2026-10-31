import XCTest
@testable import ExperienceCore

final class PostDraftTests: XCTestCase {
    func testWhitespaceOnlyIsRejected() {
        let draft = PostDraft(text: "   ", authorRecordName: "_abc")
        XCTAssertThrowsError(try draft.makePost()) { error in
            XCTAssertEqual(error as? FeedError, .emptyPost)
        }
    }

    func testPhotoWithoutCaptionIsAllowed() throws {
        let post = try PostDraft(text: "  ", imageData: Data([0x01]), authorRecordName: "  _user  ").makePost()
        XCTAssertEqual(post.text, "")
        XCTAssertEqual(post.authorName, "")
        XCTAssertEqual(post.authorRecordName, "_user")
        XCTAssertEqual(post.imageData, Data([0x01]))
        XCTAssertFalse(post.pendingUpload)
    }

    func testCaptionIsTrimmed() throws {
        let post = try PostDraft(text: "  Hello  ", authorRecordName: " _user ").makePost()
        XCTAssertEqual(post.text, "Hello")
        XCTAssertEqual(post.authorRecordName, "_user")
    }
}
