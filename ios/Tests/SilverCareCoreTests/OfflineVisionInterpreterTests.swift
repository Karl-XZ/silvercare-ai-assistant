import XCTest
@testable import SilverCareCore

final class OfflineVisionInterpreterTests: XCTestCase {
    func testFindsRequestedObjectDirectionFromDetectorBoxes() throws {
        let result = try OfflineVisionInterpreter.interpret(
            prompt: "Current task: 正在寻找：狗\n",
            rawJSON: """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"dog","score":0.88,"box":[40,170,230,455]},
                {"class":"bicycle","score":0.77,"box":[260,130,620,410]}
              ]
            }
            """,
            role: "detector"
        )

        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertEqual(json?["target_detected"] as? Bool, true)
        XCTAssertEqual(json?["subject"] as? String, "狗")
        XCTAssertEqual(json?["direction"] as? String, "left")
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("狗在左侧"))
    }

    func testProducesObstacleNavigationFromLargestAheadObject() throws {
        let result = try OfflineVisionInterpreter.interpret(
            prompt: "Current task: 通用导航\n",
            rawJSON: """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"chair","score":0.91,"box":[210,170,430,470]},
                {"class":"cup","score":0.80,"box":[20,220,80,310]}
              ]
            }
            """,
            role: "detector"
        )

        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertEqual(json?["category"] as? String, "hazard")
        XCTAssertEqual(json?["direction"] as? String, "ahead")
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("前方约"))
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("障碍"))
    }

    func testNormalizesBowlSearchFromPhoneticTarget() throws {
        let result = try OfflineVisionInterpreter.interpret(
            prompt: "Current task: 正在寻找：晚\n",
            rawJSON: """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"bowl","score":0.86,"box":[240,210,420,380]}
              ]
            }
            """,
            role: "detector"
        )

        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertEqual(json?["target_detected"] as? Bool, true)
        XCTAssertEqual(json?["subject"] as? String, "碗")
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("碗在"))
    }

    func testLocalizesEnglishDetectorLabelsForDisplay() throws {
        let result = try OfflineVisionInterpreter.interpret(
            prompt: "Current task: 正在寻找：遥控器\n",
            rawJSON: """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"remote","score":0.84,"box":[340,210,470,330]}
              ]
            }
            """,
            role: "detector"
        )

        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertEqual(json?["target_detected"] as? Bool, true)
        XCTAssertEqual(json?["subject"] as? String, "遥控器")
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("遥控器在"))
    }

    func testMissingSearchTargetAsksUserToRotateAndRefresh() throws {
        let result = try OfflineVisionInterpreter.interpret(
            prompt: "Current task: 正在寻找：药盒\n",
            rawJSON: """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"chair","score":0.82,"box":[240,210,420,380]}
              ]
            }
            """,
            role: "detector"
        )

        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertEqual(json?["target_detected"] as? Bool, false)
        XCTAssertEqual(json?["direction"] as? String, "unknown")
        XCTAssertEqual(json?["priority"] as? String, "low")
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("左右缓慢转动手机"))
        XCTAssertTrue((json?["speech"] as? String ?? "").contains("点击刷新"))
    }

    func testMicroPromptReturnsVectorGuidance() throws {
        let result = try OfflineVisionInterpreter.interpret(
            prompt: "You are 多模态长护精确引导模式\nTarget: 杯子\n",
            rawJSON: """
            {
              "image_width": 640,
              "image_height": 480,
              "detections": [
                {"class":"cup","score":0.82,"box":[430,220,520,360]}
              ]
            }
            """,
            role: "detector"
        )

        let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any]
        XCTAssertEqual(json?["action"] as? String, "move")
        XCTAssertGreaterThan(json?["x"] as? Int ?? 0, 0)
        XCTAssertTrue((json?["guidance_speech"] as? String ?? "").contains("向右"))
    }
}
