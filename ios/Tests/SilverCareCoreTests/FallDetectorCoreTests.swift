import XCTest
@testable import SilverCareCore

final class FallDetectorCoreTests: XCTestCase {
    func testMotionSampleComputesImpactMetrics() {
        let sensor = FallDetectorCore.motionSample(
            gravity: SIMD3<Double>(0, 0, 29),
            rotation: SIMD3<Double>(180, 220, 0),
            time: 1234
        )

        XCTAssertEqual(sensor.time, 1234)
        XCTAssertEqual(Int(sensor.accelerationMagnitude.rounded()), 29)
        XCTAssertTrue(FallDetectorCore.hasFallImpact(sensor))
    }

    func testStablePostureUpdatesBaselineWithoutImpact() {
        let sensor = FallDetectorCore.motionSample(
            gravity: SIMD3<Double>(0, 0, 9.81),
            rotation: SIMD3<Double>(0, 0, 0),
            time: 100
        )

        let baseline = FallDetectorCore.nextBaselineGravity(current: nil, sensor: sensor, impactActive: false)

        XCTAssertEqual(baseline, SIMD3<Double>(0, 0, 9.81))
        XCTAssertFalse(FallDetectorCore.hasFallImpact(sensor))
    }

    func testVisualEvidenceRequiresAbruptFrameChanges() {
        let weak = FallDetectorCore.visualEvidence(
            samples: (0..<8).map { VisualFrameSample(time: Double($0) * 250, diff: 0, brightness: 0.38) },
            now: 4500,
            window: 5000
        )
        XCTAssertFalse(FallDetectorCore.isVisualEvidenceStrong(weak))

        let strong = FallDetectorCore.visualEvidence(
            samples: [
                VisualFrameSample(time: 0, diff: 0, brightness: 0.1),
                VisualFrameSample(time: 250, diff: 0.01, brightness: 0.1),
                VisualFrameSample(time: 500, diff: 0.22, brightness: 0.9),
                VisualFrameSample(time: 750, diff: 0.24, brightness: 0.1),
                VisualFrameSample(time: 1000, diff: 0.2, brightness: 0.9),
                VisualFrameSample(time: 1250, diff: 0.01, brightness: 0.9)
            ],
            now: 4500,
            window: 5000
        )
        XCTAssertTrue(FallDetectorCore.isVisualEvidenceStrong(strong))
    }

    func testFallConfirmationRequiresSensorAndVisualEvidence() {
        let strongVisual = VisualEvidence(sampleCount: 7, maxDiff: 0.22, spikeCount: 3, brightnessRange: 0.44)
        let weakVisual = VisualEvidence(sampleCount: 7, maxDiff: 0.01, spikeCount: 0, brightnessRange: 0.02)

        XCTAssertFalse(FallDetectorCore.shouldConfirmFall(
            sensor: (maxAcceleration: 27, maxDeviation: 17, maxRotation: 250),
            visual: weakVisual
        ))
        XCTAssertFalse(FallDetectorCore.shouldConfirmFall(
            sensor: (maxAcceleration: 11, maxDeviation: 1, maxRotation: 8),
            visual: strongVisual
        ))
        XCTAssertTrue(FallDetectorCore.shouldConfirmFall(
            sensor: (maxAcceleration: 27, maxDeviation: 17, maxRotation: 250),
            visual: strongVisual
        ))
    }

    func testRecoveryRequiresPostureNearBaselineAndLowMovement() {
        let baseline = SIMD3<Double>(0, 0, 9.81)
        let recovered = FallDetectorCore.motionSample(
            gravity: SIMD3<Double>(0.2, 0.1, 9.7),
            rotation: SIMD3<Double>(1, 2, 1)
        )
        let fallen = FallDetectorCore.motionSample(
            gravity: SIMD3<Double>(9.81, 0, 0),
            rotation: SIMD3<Double>(1, 2, 1)
        )

        XCTAssertLessThan(FallDetectorCore.angleBetween(baseline, recovered.gravity), 5)
        XCTAssertTrue(FallDetectorCore.isRecoveredFromFall(
            baselineGravity: baseline,
            currentGravity: recovered.gravity,
            sensor: recovered
        ))
        XCTAssertFalse(FallDetectorCore.isRecoveredFromFall(
            baselineGravity: baseline,
            currentGravity: fallen.gravity,
            sensor: fallen
        ))
    }
}
