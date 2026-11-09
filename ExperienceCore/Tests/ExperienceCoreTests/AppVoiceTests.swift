import XCTest
@testable import ExperienceCore

final class AppVoiceTests: XCTestCase {
    func testSeedIsJenSpeakingForTheApp() {
        let message = AppVoice.seededMessage()
        XCTAssertEqual(message.id, AppVoice.messageID)
        XCTAssertEqual(message.authorName, "Jen")
        XCTAssertEqual(message.authorRecordName, AppVoice.recordName)
        XCTAssertFalse(message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNil(message.imageData)
    }
}
