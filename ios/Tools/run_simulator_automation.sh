#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
DEVICE_NAME="${SIMULATOR_DEVICE_NAME:-SilverCare Test iPhone 15}"
DEVICE_TYPE="${SIMULATOR_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-15}"
DERIVED_DATA="$IOS_DIR/build/DerivedData-SimulatorAutomation"
BUILD_ROOT="$IOS_DIR/build/simulator-automation"
SCREENSHOT_PATH="$BUILD_ROOT/silvercare-home.png"
BENCHMARK_REPORT_DIR="$BUILD_ROOT/local-benchmark-reports"
APP_BUNDLE_ID="com.silvercare.aiassistant.ios"
LOCAL_BENCHMARK_TESTS="${SILVERCARE_IOS_LOCAL_BENCHMARK_TESTS:-status}"
PREPARE_SIMULATOR_LOCAL_ASR="${SILVERCARE_PREPARE_SIMULATOR_LOCAL_ASR:-0}"
VOSK_MODEL_DIR="vosk-model-small-cn-0.22"
VOSK_MODEL_ZIP_URL="https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip"
VOSK_MODEL_ZIP_BYTES="43898754"
SIMULATOR_ASR_CACHE_ROOT="$BUILD_ROOT/local-asr-model-cache"
BENCHMARK_AUDIO_SOURCE="$ROOT_DIR/public_benchmark_silvercare/dataset/audio/find_door.wav"
BENCHMARK_IMAGE_SOURCE="$ROOT_DIR/public_benchmark_silvercare/dataset/images/user_corridor_hallway.jpg"
BENCHMARK_DETECTOR_SOURCE="$ROOT_DIR/app/src/main/assets/offline/damo-yolo.mnn"

log() {
  printf '\n==> %s\n' "$1"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  fi
}

latest_ios_runtime() {
  xcrun simctl list runtimes --json | /usr/bin/python3 -c '
import json
import re
import sys

payload = json.load(sys.stdin)
runtimes = [
    runtime
    for runtime in payload.get("runtimes", [])
    if runtime.get("platform") == "iOS" and runtime.get("isAvailable")
]
if not runtimes:
    raise SystemExit("No available iOS simulator runtime found")

def version_tuple(runtime):
    version = runtime.get("version") or re.sub(r"[^0-9.]", "", runtime.get("name", ""))
    return tuple(int(part) for part in version.split(".") if part.isdigit())

print(max(runtimes, key=version_tuple)["identifier"])
'
}

simulator_udid() {
  local runtime_id="$1"
  xcrun simctl list devices --json | /usr/bin/python3 -c '
import json
import sys

runtime_id, device_name = sys.argv[1:3]
payload = json.load(sys.stdin)
for device in payload.get("devices", {}).get(runtime_id, []):
    if device.get("name") == device_name and device.get("isAvailable"):
        print(device["udid"])
        break
' "$runtime_id" "$DEVICE_NAME"
}

simulator_asr_model_cache_ready() {
  local model_root="$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR"
  test -r "$model_root/am/final.mdl" \
    && test -r "$model_root/conf/model.conf" \
    && test -r "$model_root/graph/HCLr.fst" \
    && test -r "$model_root/graph/Gr.fst" \
    && test -r "$model_root/ivector/final.ie"
}

prepare_simulator_local_asr_cache() {
  if [[ "$PREPARE_SIMULATOR_LOCAL_ASR" != "1" ]]; then
    return
  fi
  require_tool curl
  require_tool afconvert

  mkdir -p "$SIMULATOR_ASR_CACHE_ROOT"
  if simulator_asr_model_cache_ready; then
    log "Using cached simulator Vosk ASR model"
    return
  fi

  local zip="$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip"
  local zip_size="0"
  if [[ -f "$zip" ]]; then
    zip_size="$(/usr/bin/python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$zip")"
  fi
  if [[ "$zip_size" != "$VOSK_MODEL_ZIP_BYTES" ]]; then
    log "Downloading simulator Vosk ASR model"
    rm -f "$zip" "$zip.part"
    curl --fail --location --retry 3 --retry-delay 2 \
      --output "$zip.part" \
      "$VOSK_MODEL_ZIP_URL"
    mv "$zip.part" "$zip"
  fi

  log "Extracting simulator Vosk ASR model"
  /usr/bin/python3 - "$zip" "$SIMULATOR_ASR_CACHE_ROOT" "$VOSK_MODEL_DIR" <<'PY'
import os
import pathlib
import shutil
import sys
import zipfile

zip_path = pathlib.Path(sys.argv[1])
cache_root = pathlib.Path(sys.argv[2])
model_dir = sys.argv[3]
tmp_root = cache_root / f"{model_dir}.tmp"
final_root = cache_root / model_dir
prefix = f"{model_dir}/"

shutil.rmtree(tmp_root, ignore_errors=True)
tmp_root.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(zip_path) as archive:
    for info in archive.infolist():
        name = info.filename.replace("\\", "/")
        if not name.startswith(prefix):
            continue
        rel = name[len(prefix):]
        if not rel:
            continue
        destination = (tmp_root / rel).resolve()
        tmp_resolved = tmp_root.resolve()
        if destination != tmp_resolved and tmp_resolved not in destination.parents:
            raise SystemExit(f"Unsafe zip path: {info.filename}")
        if info.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info) as source, open(destination, "wb") as target:
            shutil.copyfileobj(source, target)

shutil.rmtree(final_root, ignore_errors=True)
tmp_root.rename(final_root)
PY
  if ! simulator_asr_model_cache_ready; then
    printf 'Simulator Vosk ASR model cache is incomplete under %s\n' "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR" >&2
    exit 1
  fi
}

seed_simulator_local_asr_fixture() {
  if [[ "$PREPARE_SIMULATOR_LOCAL_ASR" != "1" ]]; then
    return
  fi
  prepare_simulator_local_asr_cache
  test -r "$BENCHMARK_AUDIO_SOURCE"
  test -r "$BENCHMARK_IMAGE_SOURCE"

  local app_data_path="$1"
  local model_root="$app_data_path/Library/Application Support/SilverCare/multimodal_care_models"
  local asr_root="$app_data_path/Library/Application Support/SilverCare/multimodal_care_models/asr"
  local manual_dir="$app_data_path/Documents/manual_test"
  mkdir -p "$model_root" "$asr_root" "$manual_dir"
  rm -rf "$asr_root/$VOSK_MODEL_DIR"
  /usr/bin/ditto "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR" "$asr_root/$VOSK_MODEL_DIR"
  cp "$BENCHMARK_DETECTOR_SOURCE" "$model_root/damo-yolo.mnn"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$BENCHMARK_AUDIO_SOURCE" "$manual_dir/real_voice.wav"
  cp "$BENCHMARK_IMAGE_SOURCE" "$manual_dir/real_scene.jpg"
  test -r "$asr_root/$VOSK_MODEL_DIR/conf/model.conf"
  test -s "$model_root/damo-yolo.mnn"
  test -s "$manual_dir/real_voice.wav"
  test -s "$manual_dir/real_scene.jpg"
  log "Seeded simulator Vosk ASR model, DAMO-YOLO detector, and manual benchmark fixtures"
}

require_tool xcodebuild
require_tool xcrun
require_tool node
require_tool npm
require_tool sips
require_tool xcodegen

mkdir -p "$BUILD_ROOT"
rm -rf "$DERIVED_DATA"

RUNTIME_ID="${SIMULATOR_RUNTIME:-$(latest_ios_runtime)}"
UDID="$(simulator_udid "$RUNTIME_ID")"
if [[ -z "$UDID" ]]; then
  log "Creating simulator: $DEVICE_NAME"
  UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
fi

log "Booting simulator: $DEVICE_NAME ($UDID)"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

log "Regenerating Xcode project"
(cd "$IOS_DIR" && xcodegen generate)

log "Running JavaScript checks and bridge validation"
(cd "$ROOT_DIR" && npm run check:js)

log "Running JavaScript unit tests"
(cd "$ROOT_DIR" && npm run test:js)

log "Running Swift Package core tests"
(cd "$IOS_DIR" && swift test --jobs "${SWIFT_TEST_JOBS:-1}")
rm -rf "$IOS_DIR/.build"

log "Resetting simulator app state"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl privacy "$UDID" reset all "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl privacy "$UDID" grant microphone "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl privacy "$UDID" grant motion "$APP_BUNDLE_ID" >/dev/null 2>&1 || true

if [[ "${SILVERCARE_SKIP_XCODE_TESTS:-0}" == "1" || "${SILVERCARE_RUN_XCODE_TESTS:-1}" == "0" ]]; then
  log "Skipping Xcode test action (set SILVERCARE_SKIP_XCODE_TESTS=0 to enable)"
elif [[ "${SILVERCARE_RUN_FULL_XCODE_TESTS:-0}" == "1" || "${SILVERCARE_RUN_XCUITESTS:-0}" == "1" ]]; then
  log "Running full Xcode test action on simulator"
  xcodebuild \
    -project "$IOS_DIR/SilverCareiOS.xcodeproj" \
    -scheme SilverCareiOS \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    test
else
  log "Running simulator-safe Xcode unit and UI tests"
  xcodebuild \
    -project "$IOS_DIR/SilverCareiOS.xcodeproj" \
    -scheme SilverCareiOS \
    -destination "id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    test \
    -only-testing:SilverCareiOSTests \
    -only-testing:SilverCareiOSUITests/SilverCareiOSUITests
fi

log "Building simulator app bundle"
xcodebuild \
  -project "$IOS_DIR/SilverCareiOS.xcodeproj" \
  -scheme SilverCareiOS \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  build

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name 'SilverCareiOS.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  printf 'Could not locate SilverCareiOS.app under %s\n' "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" >&2
  exit 1
fi

log "Validating bundled web assets"
test -f "$APP_PATH/assets/index.html"
test -f "$APP_PATH/assets/static/js/main.js"
test -f "$APP_PATH/assets/offline/damo-yolo.mnn"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist")"
if [[ "$BUNDLE_ID" != "$APP_BUNDLE_ID" ]]; then
  printf 'Unexpected bundle id: %s\n' "$BUNDLE_ID" >&2
  exit 1
fi
SILVERCARE_IOS_APP_PATH="$APP_PATH" node "$ROOT_DIR/tools/check-ios-native-runtime.mjs"

log "Installing and launching simulator app"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"
APP_DATA_PATH="$(xcrun simctl get_app_container "$UDID" "$APP_BUNDLE_ID" data)"
seed_simulator_local_asr_fixture "$APP_DATA_PATH"
if [[ -n "${DASHSCOPE_API_KEY:-}" ]]; then
  SIMCTL_CHILD_DASHSCOPE_API_KEY="$DASHSCOPE_API_KEY" \
  SIMCTL_CHILD_SILVERCARE_IOS_FORCE_DASHSCOPE_RUNTIME=1 \
  SIMCTL_CHILD_SILVERCARE_IOS_LOCAL_BENCHMARK_TESTS="$LOCAL_BENCHMARK_TESTS" \
    xcrun simctl launch --terminate-running-process "$UDID" "$APP_BUNDLE_ID" --silvercare-simulator-automation --silvercare-run-local-benchmarks
else
  SIMCTL_CHILD_SILVERCARE_IOS_FORCE_DASHSCOPE_RUNTIME=1 \
  SIMCTL_CHILD_SILVERCARE_IOS_LOCAL_BENCHMARK_TESTS="$LOCAL_BENCHMARK_TESTS" \
    xcrun simctl launch --terminate-running-process "$UDID" "$APP_BUNDLE_ID" --silvercare-simulator-automation --silvercare-run-local-benchmarks
fi

log "Verifying simulator local benchmark reports"
REPORT_SOURCE_DIR="$APP_DATA_PATH/Documents/benchmarks"
rm -rf "$BENCHMARK_REPORT_DIR"
mkdir -p "$BENCHMARK_REPORT_DIR"
for _ in {1..30}; do
  if [[ -f "$REPORT_SOURCE_DIR/latest-scenario.json" ]]; then
    break
  fi
  sleep 1
done
for test_name in ${LOCAL_BENCHMARK_TESTS//,/ }; do
  report="$REPORT_SOURCE_DIR/latest-${test_name}.json"
  if [[ ! -s "$report" ]]; then
    printf 'Missing simulator local benchmark report: %s\n' "$report" >&2
    exit 1
  fi
  cp "$report" "$BENCHMARK_REPORT_DIR/latest-${test_name}.json"
done
if [[ "$PREPARE_SIMULATOR_LOCAL_ASR" == "1" ]]; then
  SILVERCARE_IOS_REQUIRE_ASR_BENCHMARK=1 \
  SILVERCARE_IOS_REQUIRE_SCENARIO_FIXTURES=1 \
  SILVERCARE_IOS_REQUIRE_SCENARIO_ASR=1 \
    node "$ROOT_DIR/tools/check-ios-benchmark-reports.mjs" "$BENCHMARK_REPORT_DIR" "$LOCAL_BENCHMARK_TESTS"
else
  node "$ROOT_DIR/tools/check-ios-benchmark-reports.mjs" "$BENCHMARK_REPORT_DIR" "$LOCAL_BENCHMARK_TESTS"
fi
node - "$BENCHMARK_REPORT_DIR/latest-status.json" "$([[ -n "${DASHSCOPE_API_KEY:-}" ]] && printf 1 || printf 0)" <<'NODE'
const fs = require('node:fs');
const [reportPath, requireDashScopeKeyRaw] = process.argv.slice(2);
const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
const requireDashScopeKey = requireDashScopeKeyRaw === '1';
const speech = report.native_speech || {};
const tts = report.native_tts || {};
const errors = [];
if (speech.asr_runtime_mode !== 'dashscope') {
  errors.push(`native_speech.asr_runtime_mode=${JSON.stringify(speech.asr_runtime_mode)}`);
}
if (tts.tts_runtime_mode !== 'dashscope') {
  errors.push(`native_tts.tts_runtime_mode=${JSON.stringify(tts.tts_runtime_mode)}`);
}
if (requireDashScopeKey && tts.dashscope_available !== true) {
  errors.push('native_tts.dashscope_available is not true');
}
if (errors.length) {
  throw new Error(`Simulator smoke expected DashScope runtime modes: ${errors.join(', ')}`);
}
console.log(`Checked default simulator runtime modes in ${reportPath}: ASR/TTS dashscope`);
NODE
sleep 2

log "Capturing simulator screenshot"
xcrun simctl io "$UDID" screenshot "$SCREENSHOT_PATH"
test -s "$SCREENSHOT_PATH"
SCREENSHOT_WIDTH="$(sips -g pixelWidth "$SCREENSHOT_PATH" | awk '/pixelWidth/ {print $2}')"
SCREENSHOT_HEIGHT="$(sips -g pixelHeight "$SCREENSHOT_PATH" | awk '/pixelHeight/ {print $2}')"
if [[ "${SCREENSHOT_WIDTH:-0}" -lt 300 || "${SCREENSHOT_HEIGHT:-0}" -lt 600 ]]; then
  printf 'Simulator screenshot looks invalid: %sx%s\n' "$SCREENSHOT_WIDTH" "$SCREENSHOT_HEIGHT" >&2
  exit 1
fi

log "Checking recent app logs"
LOG_PATH="$BUILD_ROOT/simulator-recent.log"
xcrun simctl spawn "$UDID" log show --last 60s --predicate 'process == "SilverCareiOS"' > "$LOG_PATH" || true
if grep -E '银龄智护资源未找到|Fatal error|uncaught exception|Could not locate index' "$LOG_PATH" >/dev/null 2>&1; then
  if grep -E '银龄智护资源未找到|Fatal error|uncaught exception|Could not locate index' "$LOG_PATH" \
      | grep -Ev 'XCTAutomationSupport|Elements matching predicate|no match found for transformer|with results:' >/dev/null 2>&1; then
    printf 'Recent simulator logs contain a failure marker. See %s\n' "$LOG_PATH" >&2
    exit 1
  fi
fi

if [[ "${SILVERCARE_VERIFY_DEVICE_BUILD:-0}" == "1" ]]; then
  log "Verifying generic iOS compile without signing"
  rm -rf "$DERIVED_DATA-device-nosign"
  xcodebuild \
    -project "$IOS_DIR/SilverCareiOS.xcodeproj" \
    -scheme SilverCareiOS \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA-device-nosign" \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

printf '\nSimulator automation completed successfully.\n'
printf 'Simulator: %s (%s)\n' "$DEVICE_NAME" "$UDID"
printf 'Screenshot: %s\n' "$SCREENSHOT_PATH"
