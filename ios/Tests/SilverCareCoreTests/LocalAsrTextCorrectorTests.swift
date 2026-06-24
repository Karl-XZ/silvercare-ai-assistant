import XCTest
@testable import SilverCareCore

final class LocalAsrTextCorrectorTests: XCTestCase {
    func testFastCorrectHandlesCommonSilverCarePhrases() {
        XCTAssertEqual(LocalAsrTextCorrector.fastCorrect("帮我找到我的晚"), "帮我找到我的碗")
        XCTAssertEqual(LocalAsrTextCorrector.fastCorrect("关闭影导"), "关闭引导")
        XCTAssertEqual(LocalAsrTextCorrector.fastCorrect("找一下手几"), "找一下手机")
    }

    func testCorrectedTextParsesModelJsonAndFallsBackWhenInvalid() {
        XCTAssertEqual(
            LocalAsrTextCorrector.correctedText(
                rawModelResponse: #"{"corrected_text":"帮我找到我的碗","changed":true}"#,
                fallbackTranscript: "帮我找到我的晚"
            ),
            "帮我找到我的碗"
        )
        XCTAssertEqual(
            LocalAsrTextCorrector.correctedText(
                rawModelResponse: "not json",
                fallbackTranscript: "帮我找到我的晚"
            ),
            "帮我找到我的晚"
        )
    }

    func testVoskTranscriptParserMatchesAndroidChineseSpacingRules() {
        XCTAssertEqual(
            LocalVoskTranscriptParser.parseTranscript(#"{"text":"帮 我 找 门"}"#),
            "帮我找门"
        )
        XCTAssertEqual(
            LocalVoskTranscriptParser.parseTranscript(#"{"text":"turn left 找 门"}"#),
            "turn left 找门"
        )
        XCTAssertEqual(LocalVoskTranscriptParser.parseTranscript(#"{"partial":"找 门"}"#), "")
        XCTAssertEqual(LocalVoskTranscriptParser.parseTranscript("not-json"), "")
    }
}
