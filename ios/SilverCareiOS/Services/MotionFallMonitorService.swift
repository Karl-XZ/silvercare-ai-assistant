import CoreMotion
import Foundation
import SilverCareCore

struct NativeFallEvidence {
    let maxAcceleration: Double
    let maxDeviation: Double
    let maxRotation: Double
    let startedAt: Date

    var payload: [String: Any] {
        [
            "source": "ios_core_motion",
            "started_at": Int(startedAt.timeIntervalSince1970 * 1000),
            "sensor": [
                "maxAcc": Double(maxAcceleration.rounded(toPlaces: 1)),
                "maxDeviation": Double(maxDeviation.rounded(toPlaces: 1)),
                "maxRotation": Int(maxRotation.rounded())
            ]
        ]
    }
}

final class MotionFallMonitorService {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private let defaults = FallDetectorDefaults(
        impactAccelerationThreshold: 28,
        impactDeviationThreshold: 18,
        rotationThreshold: 280,
        visualDiffStrong: 0.20,
        visualBrightnessRangeStrong: 0.40,
        visualSpikeCountStrong: 3,
        minimumVisualSamples: 6
    )

    private var pendingStartedAt: Date?
    private var pendingMaxAcceleration = 0.0
    private var pendingMaxDeviation = 0.0
    private var pendingMaxRotation = 0.0
    private var lastTriggerAt: Date = .distantPast
    private let cooldown: TimeInterval = 24
    private let probeDelay: TimeInterval = 1.4

    var onConfirmationNeeded: ((NativeFallEvidence) -> Void)?

    var isRunning: Bool {
        motionManager.isDeviceMotionActive
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        queue.name = "silvercare.ios.motion"
        motionManager.deviceMotionUpdateInterval = 0.08
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handle(motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        pendingStartedAt = nil
    }

    private func handle(_ motion: CMDeviceMotion) {
        let gravity = SIMD3<Double>(
            motion.gravity.x * 9.81,
            motion.gravity.y * 9.81,
            motion.gravity.z * 9.81
        )
        let user = SIMD3<Double>(
            motion.userAcceleration.x * 9.81,
            motion.userAcceleration.y * 9.81,
            motion.userAcceleration.z * 9.81
        )
        let accelerationIncludingGravity = gravity + user
        let rotationDegrees = SIMD3<Double>(
            motion.rotationRate.x * 180 / .pi,
            motion.rotationRate.y * 180 / .pi,
            motion.rotationRate.z * 180 / .pi
        )
        let sample = FallDetectorCore.motionSample(
            gravity: accelerationIncludingGravity,
            rotation: rotationDegrees,
            time: Date().timeIntervalSince1970
        )

        guard FallDetectorCore.hasFallImpact(sample, defaults: defaults) else {
            if let started = pendingStartedAt, Date().timeIntervalSince(started) >= probeDelay {
                finishProbe()
            }
            return
        }

        if Date().timeIntervalSince(lastTriggerAt) < cooldown {
            return
        }

        if pendingStartedAt == nil {
            pendingStartedAt = Date()
            pendingMaxAcceleration = 0
            pendingMaxDeviation = 0
            pendingMaxRotation = 0
        }
        pendingMaxAcceleration = max(pendingMaxAcceleration, sample.accelerationMagnitude)
        pendingMaxDeviation = max(pendingMaxDeviation, sample.accelerationDeviation)
        pendingMaxRotation = max(pendingMaxRotation, sample.rotationMagnitude)
    }

    private func finishProbe() {
        guard let started = pendingStartedAt else { return }
        let evidence = NativeFallEvidence(
            maxAcceleration: pendingMaxAcceleration,
            maxDeviation: pendingMaxDeviation,
            maxRotation: pendingMaxRotation,
            startedAt: started
        )
        pendingStartedAt = nil

        let sensorStrong = evidence.maxAcceleration >= defaults.impactAccelerationThreshold
            || evidence.maxDeviation >= defaults.impactDeviationThreshold
            || evidence.maxRotation >= defaults.rotationThreshold
        guard sensorStrong else { return }
        lastTriggerAt = Date()
        DispatchQueue.main.async { [onConfirmationNeeded] in
            onConfirmationNeeded?(evidence)
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
