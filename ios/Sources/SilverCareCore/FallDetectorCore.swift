import Foundation

public struct FallDetectorDefaults: Equatable {
    public var impactAccelerationThreshold: Double
    public var impactDeviationThreshold: Double
    public var rotationThreshold: Double
    public var visualDiffStrong: Double
    public var visualBrightnessRangeStrong: Double
    public var visualSpikeCountStrong: Int
    public var minimumVisualSamples: Int

    public init(
        impactAccelerationThreshold: Double = 27,
        impactDeviationThreshold: Double = 17,
        rotationThreshold: Double = 260,
        visualDiffStrong: Double = 0.20,
        visualBrightnessRangeStrong: Double = 0.40,
        visualSpikeCountStrong: Int = 3,
        minimumVisualSamples: Int = 6
    ) {
        self.impactAccelerationThreshold = impactAccelerationThreshold
        self.impactDeviationThreshold = impactDeviationThreshold
        self.rotationThreshold = rotationThreshold
        self.visualDiffStrong = visualDiffStrong
        self.visualBrightnessRangeStrong = visualBrightnessRangeStrong
        self.visualSpikeCountStrong = visualSpikeCountStrong
        self.minimumVisualSamples = minimumVisualSamples
    }
}

public struct MotionSensorSample: Equatable {
    public var time: TimeInterval
    public var gravity: SIMD3<Double>
    public var accelerationMagnitude: Double
    public var accelerationDeviation: Double
    public var rotationMagnitude: Double

    public init(
        time: TimeInterval = 0,
        gravity: SIMD3<Double>,
        accelerationMagnitude: Double,
        accelerationDeviation: Double,
        rotationMagnitude: Double
    ) {
        self.time = time
        self.gravity = gravity
        self.accelerationMagnitude = accelerationMagnitude
        self.accelerationDeviation = accelerationDeviation
        self.rotationMagnitude = rotationMagnitude
    }
}

public struct VisualFrameSample: Equatable {
    public var time: TimeInterval
    public var diff: Double
    public var brightness: Double

    public init(time: TimeInterval, diff: Double, brightness: Double) {
        self.time = time
        self.diff = diff
        self.brightness = brightness
    }
}

public struct VisualEvidence: Equatable {
    public var sampleCount: Int
    public var maxDiff: Double
    public var spikeCount: Int
    public var brightnessRange: Double

    public init(sampleCount: Int, maxDiff: Double, spikeCount: Int, brightnessRange: Double) {
        self.sampleCount = sampleCount
        self.maxDiff = maxDiff
        self.spikeCount = spikeCount
        self.brightnessRange = brightnessRange
    }
}

public enum FallDetectorCore {
    public static func motionSample(
        gravity: SIMD3<Double>,
        rotation: SIMD3<Double>,
        time: TimeInterval = 0
    ) -> MotionSensorSample {
        let accelerationMagnitude = vectorLength(gravity)
        let accelerationDeviation = abs(accelerationMagnitude - 9.81)
        let rotationMagnitude = vectorLength(rotation)
        return MotionSensorSample(
            time: time,
            gravity: gravity,
            accelerationMagnitude: accelerationMagnitude,
            accelerationDeviation: accelerationDeviation,
            rotationMagnitude: rotationMagnitude
        )
    }

    public static func hasFallImpact(
        _ sample: MotionSensorSample,
        defaults: FallDetectorDefaults = FallDetectorDefaults()
    ) -> Bool {
        sample.accelerationMagnitude >= defaults.impactAccelerationThreshold
            || sample.accelerationDeviation >= defaults.impactDeviationThreshold
            || sample.rotationMagnitude >= defaults.rotationThreshold
    }

    public static func nextBaselineGravity(
        current: SIMD3<Double>?,
        sensor: MotionSensorSample,
        impactActive: Bool
    ) -> SIMD3<Double>? {
        guard !impactActive else { return current }
        guard sensor.accelerationDeviation < 1.2, sensor.rotationMagnitude < 12 else {
            return current
        }
        guard let current else { return sensor.gravity }
        return current * 0.88 + sensor.gravity * 0.12
    }

    public static func visualEvidence(
        samples: [VisualFrameSample],
        now: TimeInterval,
        window: TimeInterval
    ) -> VisualEvidence {
        let recent = samples.filter { now - $0.time <= window }
        guard !recent.isEmpty else {
            return VisualEvidence(sampleCount: 0, maxDiff: 0, spikeCount: 0, brightnessRange: 0)
        }
        let diffs = recent.map(\.diff)
        let brightness = recent.map(\.brightness)
        return VisualEvidence(
            sampleCount: recent.count,
            maxDiff: diffs.max() ?? 0,
            spikeCount: diffs.filter { $0 >= 0.12 }.count,
            brightnessRange: (brightness.max() ?? 0) - (brightness.min() ?? 0)
        )
    }

    public static func isVisualEvidenceStrong(
        _ evidence: VisualEvidence,
        defaults: FallDetectorDefaults = FallDetectorDefaults()
    ) -> Bool {
        evidence.sampleCount >= defaults.minimumVisualSamples
            && evidence.maxDiff >= defaults.visualDiffStrong
            && (
                evidence.spikeCount >= defaults.visualSpikeCountStrong
                || evidence.brightnessRange >= defaults.visualBrightnessRangeStrong
            )
    }

    public static func shouldConfirmFall(
        sensor: (maxAcceleration: Double, maxDeviation: Double, maxRotation: Double),
        visual: VisualEvidence,
        defaults: FallDetectorDefaults = FallDetectorDefaults()
    ) -> Bool {
        let sensorStrong = sensor.maxAcceleration >= defaults.impactAccelerationThreshold
            || sensor.maxDeviation >= defaults.impactDeviationThreshold
            || sensor.maxRotation >= defaults.rotationThreshold
        return sensorStrong && isVisualEvidenceStrong(visual, defaults: defaults)
    }

    public static func isRecoveredFromFall(
        baselineGravity: SIMD3<Double>,
        currentGravity: SIMD3<Double>,
        sensor: MotionSensorSample
    ) -> Bool {
        angleBetween(baselineGravity, currentGravity) < 12
            && sensor.accelerationDeviation < 2.2
            && sensor.rotationMagnitude < 20
    }

    public static func angleBetween(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let denominator = max(0.0001, vectorLength(lhs) * vectorLength(rhs))
        let dotProduct = lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
        let cosine = min(1, max(-1, dotProduct / denominator))
        return acos(cosine) * 180 / .pi
    }

    private static func vectorLength(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }
}
