import test from 'node:test';
import assert from 'node:assert/strict';

import {
  FALL_DEFAULTS,
  angleBetween,
  computeVisualEvidence,
  hasFallImpact,
  isRecoveredFromFall,
  isVisualEvidenceStrong,
  nextBaselineGravity,
  readSensorFromMotion,
  shouldConfirmFall
} from '../../main/assets/static/js/fall_detector_core.js';

function grayFrame(value, count = 72 * 54) {
  return new Uint8Array(count).fill(value);
}

function frameDiff(a, b) {
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff += Math.abs(a[i] - b[i]);
  }
  return diff / (a.length * 255);
}

function brightness(frame) {
  let total = 0;
  for (const value of frame) total += value;
  return total / (frame.length * 255);
}

test('readSensorFromMotion computes acceleration and rotation metrics', () => {
  const sensor = readSensorFromMotion({
    accelerationIncludingGravity: { x: 0, y: 0, z: 29 },
    rotationRate: { alpha: 180, beta: 220, gamma: 0 }
  }, 1234);

  assert.equal(sensor.time, 1234);
  assert.equal(Math.round(sensor.accMagnitude), 29);
  assert.equal(hasFallImpact(sensor), true);
});

test('stable posture updates baseline without creating false impact', () => {
  const sensor = readSensorFromMotion({
    accelerationIncludingGravity: { x: 0, y: 0, z: 9.81 },
    rotationRate: { alpha: 0, beta: 0, gamma: 0 }
  }, 100);

  const baseline = nextBaselineGravity(null, sensor, false);

  assert.deepEqual(baseline, { x: 0, y: 0, z: 9.81 });
  assert.equal(hasFallImpact(sensor), false);
});

test('visual evidence stays weak for stable generated frames', () => {
  const frame = grayFrame(96);
  const samples = [];
  for (let i = 0; i < 8; i += 1) {
    samples.push({
      time: i * 250,
      diff: i === 0 ? 0 : frameDiff(frame, frame),
      brightness: brightness(frame)
    });
  }

  const evidence = computeVisualEvidence(samples, 4500, 2000, FALL_DEFAULTS);

  assert.equal(evidence.sampleCount, 8);
  assert.equal(evidence.maxDiff, 0);
  assert.equal(isVisualEvidenceStrong(evidence), false);
});

test('visual evidence becomes strong for abrupt generated frame changes', () => {
  const dark = grayFrame(20);
  const bright = grayFrame(230);
  const samples = [
    { time: 0, diff: 0, brightness: brightness(dark) },
    { time: 250, diff: frameDiff(dark, dark), brightness: brightness(dark) },
    { time: 500, diff: frameDiff(dark, bright), brightness: brightness(bright) },
    { time: 750, diff: frameDiff(bright, dark), brightness: brightness(dark) },
    { time: 1000, diff: frameDiff(dark, bright), brightness: brightness(bright) },
    { time: 1250, diff: frameDiff(bright, bright), brightness: brightness(bright) }
  ];

  const evidence = computeVisualEvidence(samples, 4500, 1500, FALL_DEFAULTS);

  assert.equal(evidence.sampleCount, 6);
  assert.ok(evidence.maxDiff > FALL_DEFAULTS.visualDiffStrong);
  assert.ok(evidence.spikeCount >= 2);
  assert.equal(isVisualEvidenceStrong(evidence), true);
});

test('recovery requires posture near baseline and low movement', () => {
  const baseline = { x: 0, y: 0, z: 9.81 };
  const recoveredSensor = readSensorFromMotion({
    accelerationIncludingGravity: { x: 0.2, y: 0.1, z: 9.7 },
    rotationRate: { alpha: 1, beta: 2, gamma: 1 }
  });
  const fallenSensor = readSensorFromMotion({
    accelerationIncludingGravity: { x: 9.81, y: 0, z: 0 },
    rotationRate: { alpha: 1, beta: 2, gamma: 1 }
  });

  assert.ok(angleBetween(baseline, recoveredSensor.gravity) < 5);
  assert.equal(isRecoveredFromFall(baseline, recoveredSensor.gravity, recoveredSensor), true);
  assert.equal(isRecoveredFromFall(baseline, fallenSensor.gravity, fallenSensor), false);
});

test('fall confirmation requires both sensor impact and visual history change', () => {
  const strongSensor = { maxAcc: 27, maxDeviation: 17, maxRotation: 250 };
  const weakSensor = { maxAcc: 11, maxDeviation: 1, maxRotation: 8 };
  const strongVisual = {
    sampleCount: 7,
    maxDiff: 0.22,
    spikeCount: 3,
    brightnessRange: 0.44
  };
  const weakVisual = {
    sampleCount: 7,
    maxDiff: 0.01,
    spikeCount: 0,
    brightnessRange: 0.02
  };

  assert.equal(shouldConfirmFall(strongSensor, weakVisual), false);
  assert.equal(shouldConfirmFall(weakSensor, strongVisual), false);
  assert.equal(shouldConfirmFall(strongSensor, strongVisual), true);
});
