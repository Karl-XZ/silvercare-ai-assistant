import XCTest
@testable import SilverCareCore

final class MemoryStoreTests: XCTestCase {
    func testAddLocationIncludesLocationInSummary() {
        let store = SilverCareMemoryStore()

        store.addLocation("家门口", description: "白色门，旁边有鞋柜")

        XCTAssertTrue(store.locationSummary().contains("家门口"))
        XCTAssertTrue(store.locationSummary().contains("鞋柜"))
    }

    func testLogObjectDeduplicatesImmediateRepeatedObject() {
        let store = SilverCareMemoryStore()

        store.logObject("杯子", locationTag: "桌面", scene: "木桌上有杯子")
        store.logObject("杯子", locationTag: "桌面", scene: "木桌上有杯子")

        let history = store.historyContext()
        XCTAssertTrue(history.contains("杯子"))
        XCTAssertEqual(history.split(separator: "\n").count, 1)
    }

    func testFindObjectLocationUsesNewestMatchingHistoryEntry() {
        let store = SilverCareMemoryStore()

        store.logObject("药盒", locationTag: "床头柜", scene: "药盒在台灯旁边")
        store.logObject("拐杖", locationTag: "玄关", scene: "拐杖靠在鞋柜左侧")

        XCTAssertEqual(store.findObjectLocation("我的拐杖在哪里"), "拐杖在玄关，拐杖靠在鞋柜左侧")
    }
}
