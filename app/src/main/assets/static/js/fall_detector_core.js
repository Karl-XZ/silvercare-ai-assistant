export const FALL_DEFAULTS = {
    sampleIntervalMs: 250,
    bufferWindowMs: 4500,
    sampleWidth: 72,
    sampleHeight: 54,
    probeDelayMs: 900,
    cooldownMs: 24000,
    countdownSeconds: 10,
    impactDeviation: 17,
    impactMagnitude: 27,
    rotationImpact: 260,
    visualDiffSpike: 0.15,
    visualDiffStrong: 0.22,
    brightnessRangeStrong: 0.45,
    recoveryAngle: 25,
    recoveryDeviation: 4,
    recoveryRotation: 35,
    recoveryHoldMs: 1800
};

export function readSensorFromMotion(event, time = Date.now()) {
    const gravity = event.accelerationIncludingGravity || {};
    const x = Number(gravity.x);
    const y = Number(gravity.y);
    const z = Number(gravity.z);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) return null;

    const rotation = event.rotationRate || {};
    const alpha = Number(rotation.alpha) || 0;
    const beta = Number(rotation.beta) || 0;
    const gamma = Number(rotation.gamma) || 0;
    const accMagnitude = Math.sqrt(x * x + y * y + z * z);
    const rotationMagnitude = Math.sqrt(alpha * alpha + beta * beta + gamma * gamma);

    return {
        time,
        gravity: { x, y, z },
        accMagnitude,
        accDeviation: Math.abs(accMagnitude - 9.81),
        rotationMagnitude
    };
}

export function hasFallImpact(sensor, config = FALL_DEFAULTS) {
    return sensor.accDeviation >= config.impactDeviation
        || sensor.accMagnitude >= config.impactMagnitude
        || sensor.rotationMagnitude >= config.rotationImpact;
}

export function nextBaselineGravity(previous, sensor, alertActive = false) {
    if (sensor.accDeviation > 2.8 || sensor.rotationMagnitude > 45 || alertActive) return previous;
    if (!previous) return { ...sensor.gravity };

    const keep = 0.92;
    const add = 1 - keep;
    return {
        x: previous.x * keep + sensor.gravity.x * add,
        y: previous.y * keep + sensor.gravity.y * add,
        z: previous.z * keep + sensor.gravity.z * add
    };
}

export function computeVisualEvidence(samples, windowMs, now = Date.now(), config = FALL_DEFAULTS) {
    const cutoff = now - windowMs;
    const activeSamples = samples.filter((sample) => sample.time >= cutoff);
    let maxDiff = 0;
    let spikeCount = 0;
    let minBrightness = 1;
    let maxBrightness = 0;

    activeSamples.forEach((sample) => {
        maxDiff = Math.max(maxDiff, sample.diff);
        if (sample.diff >= config.visualDiffSpike) spikeCount += 1;
        minBrightness = Math.min(minBrightness, sample.brightness);
        maxBrightness = Math.max(maxBrightness, sample.brightness);
    });

    return {
        sampleCount: activeSamples.length,
        maxDiff: Number(maxDiff.toFixed(3)),
        spikeCount,
        brightnessRange: Number(Math.max(0, maxBrightness - minBrightness).toFixed(3))
    };
}

export function isVisualEvidenceStrong(visual, config = FALL_DEFAULTS) {
    return visual.sampleCount >= 5
        && (
            visual.maxDiff >= config.visualDiffStrong
            || visual.spikeCount >= 2
            || visual.brightnessRange >= config.brightnessRangeStrong
        );
}

export function shouldConfirmFall(sensorEvidence, visualEvidence, config = FALL_DEFAULTS) {
    const sensorStrong = !!sensorEvidence && (
        sensorEvidence.maxDeviation >= config.impactDeviation
        || sensorEvidence.maxAcc >= config.impactMagnitude
        || sensorEvidence.maxRotation >= config.rotationImpact
    );
    return sensorStrong && isVisualEvidenceStrong(visualEvidence, config);
}

export function angleBetween(a, b) {
    const dot = a.x * b.x + a.y * b.y + a.z * b.z;
    const am = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    const bm = Math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z);
    if (!am || !bm) return 180;
    const cos = Math.max(-1, Math.min(1, dot / (am * bm)));
    return Math.acos(cos) * 180 / Math.PI;
}

export function isRecoveredFromFall(baseline, currentGravity, sensor, config = FALL_DEFAULTS) {
    if (!baseline || !currentGravity || !sensor) return false;
    const angle = angleBetween(baseline, currentGravity);
    return angle <= config.recoveryAngle
        && sensor.accDeviation <= config.recoveryDeviation
        && sensor.rotationMagnitude <= config.recoveryRotation;
}
