#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
DEVICE_ID="${IOS_DEVICE_ID:-}"
DERIVED_DATA="$IOS_DIR/build/DerivedData-device-ui-debug"
BUILD_ROOT="$IOS_DIR/build/device-ui-debug"
RESULT_BUNDLE="$BUILD_ROOT/SilverCareiOSDeviceDebug.xcresult"
TEST_LOG="$BUILD_ROOT/xcodebuild-device-ui-debug.log"
SUMMARY_PATH="$BUILD_ROOT/summary.json"
LOCK_STATE_PATH="$BUILD_ROOT/device-lock-state.log"
DESTINATION_TIMEOUT="${SILVERCARE_DEVICE_UI_DESTINATION_TIMEOUT:-60}"
UNLOCK_GRACE_SECONDS="${SILVERCARE_DEVICE_UI_UNLOCK_GRACE_SECONDS:-120}"
XCODEBUILD_PID=""
LOCKED_NOTICE_PRINTED=0
AUTOMATION_NOTICE_PRINTED=0
LOCKED_FIRST_SEEN_EPOCH=0
AUTOMATION_FIRST_SEEN_EPOCH=0

log() {
  printf '\n==> %s\n' "$1"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required tool: %s\n' "$1" >&2
    exit 1
  fi
}

detect_device_id() {
  xcrun xctrace list devices 2>/dev/null | /usr/bin/python3 -c '
import re
import sys

for line in sys.stdin:
    if "Simulator" in line or "iPhone" not in line:
        continue
    match = re.search(r"\(([0-9A-Fa-f-]{20,})\)\s*$", line.strip())
    if match:
        print(match.group(1))
        break
'
}

write_summary() {
  local status="$1"
  local reason="${2:-}"
  /usr/bin/python3 - "$SUMMARY_PATH" "$status" "$reason" "$DEVICE_ID" "$RESULT_BUNDLE" "$TEST_LOG" <<'PY'
import datetime
import json
import os
import sys

summary_path, status, reason, device_id, result_bundle, test_log = sys.argv[1:7]
payload = {
    "generated_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": status,
    "reason": reason,
    "device_id": device_id,
    "result_bundle_path": result_bundle,
    "result_bundle_exists": os.path.exists(result_bundle),
    "test_log_path": test_log,
    "test_log_exists": os.path.exists(test_log),
}
os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

record_device_lock_state() {
  local output_path="${1:-$LOCK_STATE_PATH}"
  xcrun devicectl device info lockState \
    --device "$DEVICE_ID" \
    >"$output_path" 2>&1 || true
}

device_lock_state_requires_passcode() {
  local input_path="$1"
  [[ -f "$input_path" ]] && grep -Eqi 'passcodeRequired[^[:alnum:]_]*true' "$input_path"
}

mark_interrupted() {
  if [[ -n "${XCODEBUILD_PID:-}" ]] && kill -0 "$XCODEBUILD_PID" >/dev/null 2>&1; then
    kill "$XCODEBUILD_PID" >/dev/null 2>&1 || true
    wait "$XCODEBUILD_PID" >/dev/null 2>&1 || true
  fi
  if [[ -f "$TEST_LOG" ]] && grep -Eqi 'Unlock .* to Continue|device is locked|Timed out while enabling automation mode' "$TEST_LOG"; then
    classify_device_ui_failure
    exit 130
  fi
  write_summary "interrupted" "device_ui_debug_interrupted"
  printf '\nDevice UI debug tests were interrupted.\n' >&2
  exit 130
}

classify_device_ui_failure() {
  tail -n 120 "$TEST_LOG" >&2 || true
  if grep -Eqi 'Unlock .* to Continue|device is locked|locked' "$TEST_LOG"; then
    record_device_lock_state "$LOCK_STATE_PATH"
    if device_lock_state_requires_passcode "$LOCK_STATE_PATH"; then
      write_summary "blocked_by_locked_device" "iphone_locked_during_device_ui_tests"
      printf '\nThe device UI tests could not launch because devicectl reports passcodeRequired=true. Unlock the iPhone, keep the screen awake, then rerun:\n\n  npm run test:ios:device-ui\n\n' >&2
    else
      write_summary "blocked_by_device_automation" "xcode_ui_automation_locked_response_while_lock_state_unlocked"
      printf '\nThe device UI tests hit an Xcode/CoreDevice locked-or-automation response, but devicectl lockState does not report passcodeRequired=true. Confirm any trust/automation prompt, replug the iPhone or restart Xcode/CoreDevice services, then rerun:\n\n  npm run test:ios:device-ui\n\nLock-state evidence: %s\n\n' "$LOCK_STATE_PATH" >&2
    fi
  elif grep -qi 'Timed out while enabling automation mode' "$TEST_LOG"; then
    write_summary "blocked_by_device_automation" "xcode_ui_automation_mode_timeout"
    printf '\nThe device UI tests built and installed the test runner, but Xcode timed out while enabling device UI automation mode. Keep the iPhone unlocked, confirm any trust/automation prompt on the device, then rerun:\n\n  npm run test:ios:device-ui\n\n' >&2
  else
    write_summary "failed" "device_ui_debug_tests_failed"
  fi
}

require_tool xcodebuild
require_tool xcrun
require_tool xcodegen

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(detect_device_id)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  printf 'No connected iPhone was found. Connect and unlock an iPhone, then rerun.\n' >&2
  exit 1
fi

mkdir -p "$BUILD_ROOT"
rm -rf "$DERIVED_DATA" "$RESULT_BUNDLE"
write_summary "running" "device_ui_debug_in_progress"
trap mark_interrupted INT TERM

log "Using iPhone device: $DEVICE_ID"
record_device_lock_state "$LOCK_STATE_PATH"
log "Regenerating Xcode project"
(cd "$IOS_DIR" && xcodegen generate)

log "Running opt-in device UI screenshot tests"
SILVERCARE_RUN_DEVICE_DEBUG_UITESTS=1 \
  xcodebuild \
  -project "$IOS_DIR/SilverCareiOS.xcodeproj" \
  -scheme SilverCareiOS \
  -destination "id=$DEVICE_ID" \
  -destination-timeout "$DESTINATION_TIMEOUT" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -allowProvisioningUpdates \
  test \
  -only-testing:SilverCareiOSUITests/SilverCareiOSDeviceDebugUITests \
  >"$TEST_LOG" 2>&1 &
XCODEBUILD_PID="$!"

while jobs -pr | grep -qx "$XCODEBUILD_PID"; do
  if [[ -f "$TEST_LOG" ]]; then
    if grep -Eqi 'Unlock .* to Continue|device is locked' "$TEST_LOG"; then
      if [[ "$LOCKED_FIRST_SEEN_EPOCH" -eq 0 ]]; then
        LOCKED_FIRST_SEEN_EPOCH="$(date +%s)"
        record_device_lock_state "$LOCK_STATE_PATH"
      fi
      if [[ "$LOCKED_NOTICE_PRINTED" -eq 0 ]]; then
        if device_lock_state_requires_passcode "$LOCK_STATE_PATH"; then
          printf '\nXcode reports the iPhone needs to be unlocked. Unlock it and keep the screen awake; waiting for Xcode to continue or time out.\n' >&2
        else
          printf '\nXcode reported a locked-device prompt, but devicectl lockState does not require passcode. Waiting for automation services to continue or time out.\n' >&2
        fi
        LOCKED_NOTICE_PRINTED=1
      fi
      if (( "$(date +%s)" - LOCKED_FIRST_SEEN_EPOCH >= UNLOCK_GRACE_SECONDS )); then
        kill "$XCODEBUILD_PID" >/dev/null 2>&1 || true
        wait "$XCODEBUILD_PID" >/dev/null 2>&1 || true
        XCODEBUILD_PID=""
        classify_device_ui_failure
        exit 1
      fi
    fi
    if grep -qi 'Timed out while enabling automation mode' "$TEST_LOG"; then
      if [[ "$AUTOMATION_FIRST_SEEN_EPOCH" -eq 0 ]]; then
        AUTOMATION_FIRST_SEEN_EPOCH="$(date +%s)"
      fi
      if [[ "$AUTOMATION_NOTICE_PRINTED" -eq 0 ]]; then
        printf '\nXcode is still enabling device UI automation mode. Confirm any trust or automation prompt on the iPhone; waiting for Xcode to continue or time out.\n' >&2
        AUTOMATION_NOTICE_PRINTED=1
      fi
      if (( "$(date +%s)" - AUTOMATION_FIRST_SEEN_EPOCH >= UNLOCK_GRACE_SECONDS )); then
        kill "$XCODEBUILD_PID" >/dev/null 2>&1 || true
        wait "$XCODEBUILD_PID" >/dev/null 2>&1 || true
        XCODEBUILD_PID=""
        classify_device_ui_failure
        exit 1
      fi
    fi
  fi
  sleep 2
done

if ! wait "$XCODEBUILD_PID"; then
  XCODEBUILD_PID=""
  classify_device_ui_failure
  exit 1
fi
XCODEBUILD_PID=""

trap - INT TERM
write_summary "passed" ""
printf '\nDevice UI debug tests completed.\n'
printf 'Device: %s\n' "$DEVICE_ID"
printf 'Artifacts: %s\n' "$BUILD_ROOT"
printf 'Result bundle: %s\n' "$RESULT_BUNDLE"
