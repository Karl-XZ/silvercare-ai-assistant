import XCTest
@testable import SilverCareCore

final class MnnLlmTuningProfileTests: XCTestCase {
    func testDefaultsToAutoForUnknownValue() {
        XCTAssertEqual(SilverCareMnnLlmTuningProfile.from("missing"), .auto)
        XCTAssertEqual(SilverCareMnnLlmTuningProfile.from(nil), .auto)
    }

    func testEmitsNativeConfigOnlyWhenSme2IsSupported() {
        XCTAssertEqual(
            SilverCareMnnLlmTuningProfile.auto.nativeConfigJSON(supportsSme2: true),
            #"{"jinja":{"context":{"enable_thinking":false}},"cpu_sme2_neon_division_ratio":41,"cpu_sme_core_num":2}"#
        )
        XCTAssertEqual(
            SilverCareMnnLlmTuningProfile.auto.nativeConfigJSON(supportsSme2: false),
            #"{"jinja":{"context":{"enable_thinking":false}}}"#
        )
        XCTAssertEqual(
            SilverCareMnnLlmTuningProfile.mnnDefault.nativeConfigJSON(supportsSme2: true),
            #"{"jinja":{"context":{"enable_thinking":false}}}"#
        )
    }

    func testMenuTextExplainsAutomaticFallback() {
        XCTAssertTrue(SilverCareMnnLlmTuningProfile.performance.menuText(supportsSme2: false).contains("自动回退"))
        XCTAssertTrue(SilverCareMnnLlmTuningProfile.performance.menuText(supportsSme2: true).contains("49"))
    }
}
