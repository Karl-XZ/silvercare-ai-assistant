#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
DEVICE_ID="${IOS_DEVICE_ID:-}"
APP_BUNDLE_ID="com.silvercare.aiassistant.ios"
DEVELOPMENT_TEAM_OVERRIDE="${SILVERCARE_IOS_DEVELOPMENT_TEAM:-}"
PROVISIONING_PROFILE_SPECIFIER_OVERRIDE="${SILVERCARE_IOS_PROVISIONING_PROFILE_SPECIFIER:-}"
CODE_SIGN_IDENTITY_OVERRIDE="${SILVERCARE_IOS_CODE_SIGN_IDENTITY:-}"
DERIVED_DATA="$IOS_DIR/build/DerivedData-device"
NOSIGN_DERIVED_DATA="$IOS_DIR/build/DerivedData-device-nosign"
BUILD_ROOT="$IOS_DIR/build/device-smoke"
BENCHMARK_REPORT_DIR="$BUILD_ROOT/benchmarks"
DIAGNOSTIC_REPORT_DIR="$BUILD_ROOT/diagnostics"
LOCAL_BENCHMARK_TESTS="${SILVERCARE_IOS_LOCAL_BENCHMARK_TESTS:-status}"
PREPARE_DEVICE_LOCAL_ASR="${SILVERCARE_PREPARE_DEVICE_LOCAL_ASR:-0}"
VOSK_MODEL_DIR="vosk-model-small-cn-0.22"
VOSK_MODEL_ZIP_URL="https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip"
VOSK_MODEL_ZIP_BYTES="43898754"
DEVICE_ASR_CACHE_ROOT="${SILVERCARE_DEVICE_ASR_CACHE_ROOT:-$BUILD_ROOT/local-asr-model-cache}"
SIMULATOR_ASR_CACHE_ROOT="$IOS_DIR/build/simulator-automation/local-asr-model-cache"
DEVICE_SEED_ROOT="$BUILD_ROOT/device-seed"
BENCHMARK_AUDIO_SOURCE="$ROOT_DIR/public_benchmark_silvercare/dataset/audio/find_door.wav"
BENCHMARK_IMAGE_SOURCE="$ROOT_DIR/public_benchmark_silvercare/dataset/images/user_corridor_hallway.jpg"
BENCHMARK_DETECTOR_SOURCE="$ROOT_DIR/app/src/main/assets/offline/damo-yolo.mnn"
SIGNING_PREFLIGHT="$BUILD_ROOT/signing-preflight.txt"
SUMMARY_PATH="$BUILD_ROOT/summary.json"
LOCK_STATE_PATH="$BUILD_ROOT/device-lock-state.log"
UNSIGNED_APP_PATH=""
UNSIGNED_RUNTIME_PREFLIGHT="not_run"
SIGNED_BUILD_STATUS="not_run"

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

explain_signing_failure() {
  local build_log="$1"
  if grep -q 'No Account for Team' "$build_log"; then
    cat >&2 <<'TEXT'

Device build reached Xcode signing, but this Mac is not logged in to the
project's Apple development team. Open Xcode > Settings > Accounts, add or
refresh the Apple ID for the team shown in the build log, then rerun:

  npm run test:ios:device

If you need to use a different signing team/profile without editing the
project, rerun with:

  SILVERCARE_IOS_DEVELOPMENT_TEAM=<TEAM_ID> npm run test:ios:device

TEXT
  elif grep -q 'No profiles for' "$build_log"; then
    cat >&2 <<'TEXT'

Device build reached Xcode signing, but no matching iOS Development
provisioning profile was available. After Xcode account login is valid,
automatic signing should create it; then rerun:

  npm run test:ios:device

For a manually selected profile:

  SILVERCARE_IOS_PROVISIONING_PROFILE_SPECIFIER="<PROFILE_NAME>" npm run test:ios:device

TEXT
  fi
  if [[ -f "$SIGNING_PREFLIGHT" ]]; then
    printf 'Signing preflight report: %s\n' "$SIGNING_PREFLIGHT" >&2
  fi
}

project_development_team() {
  /usr/bin/python3 - "$IOS_DIR/project.yml" <<'PY'
import re
import sys

path = sys.argv[1]
try:
    text = open(path, "r", encoding="utf-8").read()
except FileNotFoundError:
    raise SystemExit(0)

match = re.search(r"^\s*DEVELOPMENT_TEAM:\s*([A-Za-z0-9]+)\s*$", text, re.MULTILINE)
if match:
    print(match.group(1))
PY
}

write_signing_preflight() {
  local project_team="$1"
  local effective_team="$2"
  {
    printf 'SilverCare iOS device signing preflight\n'
    printf 'generated_at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'device_id: %s\n' "$DEVICE_ID"
    printf 'bundle_id: %s\n' "$APP_BUNDLE_ID"
    printf 'project_team: %s\n' "${project_team:-unknown}"
    printf 'effective_team: %s\n' "${effective_team:-unknown}"
    printf 'development_team_override: %s\n' "${DEVELOPMENT_TEAM_OVERRIDE:-<none>}"
    printf 'profile_specifier_override: %s\n' "${PROVISIONING_PROFILE_SPECIFIER_OVERRIDE:-<none>}"
    printf 'code_sign_identity_override: %s\n' "${CODE_SIGN_IDENTITY_OVERRIDE:-<none>}"
    printf '\n[code signing identities]\n'
    if security find-identity -p codesigning -v; then
      :
    else
      printf 'security find-identity failed\n'
    fi
    printf '\n[provisioning profiles]\n'
  } > "$SIGNING_PREFLIGHT"

  /usr/bin/python3 - "$APP_BUNDLE_ID" "$effective_team" >>"$SIGNING_PREFLIGHT" <<'PY'
import glob
import os
import plistlib
import subprocess
import sys

bundle_id, team_id = sys.argv[1:3]
profile_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")

if not os.path.isdir(profile_dir):
    print(f"profiles_directory: missing ({profile_dir})")
    print("matching_profiles: 0")
    raise SystemExit(0)

paths = sorted(glob.glob(os.path.join(profile_dir, "*.mobileprovision")))
print(f"profiles_directory: {profile_dir}")
print(f"profiles_total: {len(paths)}")

matches = []
for path in paths:
    try:
        result = subprocess.run(
            ["security", "cms", "-D", "-i", path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        profile = plistlib.loads(result.stdout)
    except Exception:
        continue

    entitlements = profile.get("Entitlements", {})
    app_identifier = str(entitlements.get("application-identifier", ""))
    teams = [str(item) for item in profile.get("TeamIdentifier", [])]
    name = str(profile.get("Name", os.path.basename(path)))
    uuid = str(profile.get("UUID", os.path.basename(path)))
    expiration = profile.get("ExpirationDate")
    platform = ",".join(str(item) for item in profile.get("Platform", []))
    profile_bundle = app_identifier.split(".", 1)[1] if "." in app_identifier else app_identifier
    team_ok = not team_id or team_id in teams
    bundle_ok = profile_bundle == bundle_id or profile_bundle == "*"
    if team_ok and bundle_ok:
        matches.append((name, uuid, app_identifier, expiration, platform))

print(f"matching_profiles: {len(matches)}")
for name, uuid, app_identifier, expiration, platform in matches:
    expiry = expiration.isoformat() if hasattr(expiration, "isoformat") else str(expiration or "unknown")
    print(f"- name: {name}")
    print(f"  uuid: {uuid}")
    print(f"  application_identifier: {app_identifier}")
    print(f"  expires: {expiry}")
    print(f"  platform: {platform}")
PY

  printf 'Signing preflight report: %s\n' "$SIGNING_PREFLIGHT"
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

write_summary() {
  local status="$1"
  local reason="${2:-}"
  /usr/bin/python3 - "$SUMMARY_PATH" "$status" "$reason" "$DEVICE_ID" "$APP_BUNDLE_ID" "$SIGNING_PREFLIGHT" "$UNSIGNED_APP_PATH" "$UNSIGNED_RUNTIME_PREFLIGHT" "$SIGNED_BUILD_STATUS" "$BUILD_ROOT" "$BENCHMARK_REPORT_DIR" "$DIAGNOSTIC_REPORT_DIR" <<'PY'
import datetime
import json
import os
import sys

(
    summary_path,
    status,
    reason,
    device_id,
    bundle_id,
    signing_preflight,
    unsigned_app_path,
    unsigned_runtime_preflight,
    signed_build_status,
    build_root,
    benchmark_dir,
    diagnostic_dir,
) = sys.argv[1:13]

payload = {
    "generated_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": status,
    "reason": reason,
    "device_id": device_id,
    "bundle_id": bundle_id,
    "unsigned_iphoneos_app_path": unsigned_app_path,
    "unsigned_runtime_preflight": unsigned_runtime_preflight,
    "signed_build_status": signed_build_status,
    "signing_preflight_path": signing_preflight,
    "signing_preflight_exists": os.path.exists(signing_preflight),
    "build_root": build_root,
    "benchmark_report_dir": benchmark_dir,
    "diagnostic_report_dir": diagnostic_dir,
}

os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

verify_unsigned_iphoneos_bundle() {
  if [[ "${SILVERCARE_SKIP_IOS_NOSIGN_PREFLIGHT:-0}" == "1" ]]; then
    log "Skipping unsigned iPhoneOS app-bundle runtime preflight"
    UNSIGNED_RUNTIME_PREFLIGHT="skipped"
    return
  fi

  log "Verifying unsigned iPhoneOS app bundle and native runtime slices"
  rm -rf "$NOSIGN_DERIVED_DATA"
  xcodebuild \
    -project "$IOS_DIR/SilverCareiOS.xcodeproj" \
    -scheme SilverCareiOS \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$NOSIGN_DERIVED_DATA" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build

  local unsigned_app_path
  unsigned_app_path="$(find "$NOSIGN_DERIVED_DATA/Build/Products/Debug-iphoneos" -maxdepth 1 -name 'SilverCareiOS.app' -print -quit)"
  if [[ -z "$unsigned_app_path" ]]; then
    printf 'Could not locate unsigned SilverCareiOS.app under %s\n' "$NOSIGN_DERIVED_DATA/Build/Products/Debug-iphoneos" >&2
    UNSIGNED_RUNTIME_PREFLIGHT="failed"
    write_summary "failed" "missing_unsigned_iphoneos_app"
    exit 1
  fi
  UNSIGNED_APP_PATH="$unsigned_app_path"

  SILVERCARE_IOS_APP_PATH="$unsigned_app_path" \
    SILVERCARE_REQUIRE_IOS_APP_BUNDLE_RUNTIME=1 \
    SILVERCARE_IOS_REQUIRE_APP_BUNDLE_PLATFORM=IOS \
    node "$ROOT_DIR/tools/check-ios-native-runtime.mjs"
  UNSIGNED_RUNTIME_PREFLIGHT="passed"
}

asr_model_cache_ready_at() {
  local cache_root="$1"
  local model_root="$cache_root/$VOSK_MODEL_DIR"
  test -r "$model_root/am/final.mdl" \
    && test -r "$model_root/conf/model.conf" \
    && test -r "$model_root/graph/HCLr.fst" \
    && test -r "$model_root/graph/Gr.fst" \
    && test -r "$model_root/ivector/final.ie"
}

prepare_device_local_asr_cache() {
  if [[ "$PREPARE_DEVICE_LOCAL_ASR" != "1" ]]; then
    return
  fi
  require_tool curl
  require_tool afconvert

  if asr_model_cache_ready_at "$DEVICE_ASR_CACHE_ROOT"; then
    if [[ ! -f "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip" && -f "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip" ]]; then
      cp "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip" "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip"
    fi
    log "Using cached device Vosk ASR model"
    return
  fi

  if asr_model_cache_ready_at "$SIMULATOR_ASR_CACHE_ROOT"; then
    log "Reusing simulator Vosk ASR model cache for device smoke"
    mkdir -p "$DEVICE_ASR_CACHE_ROOT"
    rm -rf "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR"
    /usr/bin/ditto "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR" "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR"
    if [[ -f "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip" ]]; then
      cp "$SIMULATOR_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip" "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip"
    fi
    return
  fi

  mkdir -p "$DEVICE_ASR_CACHE_ROOT"
  local zip="$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR.zip"
  local zip_size="0"
  if [[ -f "$zip" ]]; then
    zip_size="$(/usr/bin/python3 -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$zip")"
  fi
  if [[ "$zip_size" != "$VOSK_MODEL_ZIP_BYTES" ]]; then
    log "Downloading device Vosk ASR model"
    rm -f "$zip" "$zip.part"
    curl --fail --location --retry 3 --retry-delay 2 \
      --output "$zip.part" \
      "$VOSK_MODEL_ZIP_URL"
    mv "$zip.part" "$zip"
  fi

  log "Extracting device Vosk ASR model"
  /usr/bin/python3 - "$zip" "$DEVICE_ASR_CACHE_ROOT" "$VOSK_MODEL_DIR" <<'PY'
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

  if ! asr_model_cache_ready_at "$DEVICE_ASR_CACHE_ROOT"; then
    printf 'Device Vosk ASR model cache is incomplete under %s\n' "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR" >&2
    exit 1
  fi
}

seed_device_local_benchmark_fixtures() {
  if [[ "$PREPARE_DEVICE_LOCAL_ASR" != "1" ]]; then
    return
  fi

  prepare_device_local_asr_cache
  test -r "$BENCHMARK_AUDIO_SOURCE"
  test -r "$BENCHMARK_IMAGE_SOURCE"
  test -r "$BENCHMARK_DETECTOR_SOURCE"

  local seed_root="$DEVICE_SEED_ROOT/silvercare_seed"
  local seed_model_root="$seed_root/models"
  local seed_asr_root="$seed_model_root/asr"
  local manual_seed_dir="$DEVICE_SEED_ROOT/manual_test"
  rm -rf "$DEVICE_SEED_ROOT"
  mkdir -p "$seed_asr_root" "$manual_seed_dir"
  /usr/bin/ditto "$DEVICE_ASR_CACHE_ROOT/$VOSK_MODEL_DIR" "$seed_asr_root/$VOSK_MODEL_DIR"
  cp "$BENCHMARK_DETECTOR_SOURCE" "$seed_model_root/damo-yolo.mnn"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$BENCHMARK_AUDIO_SOURCE" "$manual_seed_dir/real_voice.wav"
  cp "$BENCHMARK_IMAGE_SOURCE" "$manual_seed_dir/real_scene.jpg"
  test -s "$seed_asr_root/$VOSK_MODEL_DIR/am/final.mdl"
  test -s "$seed_asr_root/$VOSK_MODEL_DIR/conf/model.conf"
  test -s "$seed_model_root/damo-yolo.mnn"
  test -s "$manual_seed_dir/real_voice.wav"
  test -s "$manual_seed_dir/real_scene.jpg"

  log "Seeding iPhone Vosk ASR model, detector, and manual benchmark fixtures"
  xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --source "$seed_root" \
    --destination "Documents/silvercare_seed" \
    --remove-existing-content true \
    --timeout 300 \
    --json-output "$BUILD_ROOT/copy-to-model-seed.json" \
    --log-output "$BUILD_ROOT/copy-to-model-seed.log"

  xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --source "$manual_seed_dir" \
    --destination "Documents/manual_test" \
    --remove-existing-content true \
    --timeout 300 \
    --json-output "$BUILD_ROOT/copy-to-manual-fixtures.json" \
    --log-output "$BUILD_ROOT/copy-to-manual-fixtures.log"

  xcrun devicectl device info files \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --subdirectory "Documents/silvercare_seed" \
    --json-output "$BUILD_ROOT/model-seed-files.json" \
    --log-output "$BUILD_ROOT/model-seed-files.log" >/dev/null || true

  xcrun devicectl device info files \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --subdirectory "Documents/manual_test" \
    --json-output "$BUILD_ROOT/manual-fixture-files.json" \
    --log-output "$BUILD_ROOT/manual-fixture-files.log" >/dev/null || true
}

json_value() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import json
import sys

path, key = sys.argv[1:3]
try:
    with open(path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except FileNotFoundError:
    raise SystemExit(0)

value = payload
for part in key.split("."):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break
if value is not None:
    print(value)
PY
}

redact_dashscope_key_in_file() {
  local file="$1"
  if [[ -z "${DASHSCOPE_API_KEY:-}" || ! -f "$file" ]]; then
    return
  fi
  /usr/bin/python3 - "$file" <<'PY'
import os
import pathlib
import sys

key = os.environ.get("DASHSCOPE_API_KEY", "")
if not key:
    raise SystemExit(0)

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="ignore")
redacted = text.replace(key, "[REDACTED_DASHSCOPE_API_KEY]")
if redacted != text:
    path.write_text(redacted, encoding="utf-8")
PY
}

assert_default_cloud_runtime_report() {
  if [[ "$PREPARE_DEVICE_LOCAL_ASR" == "1" ]]; then
    return
  fi

  local require_dashscope_key="0"
  if [[ -n "${DASHSCOPE_API_KEY:-}" ]]; then
    require_dashscope_key="1"
  fi

  /usr/bin/python3 - "$DEVICE_BENCHMARK_REPORT_DIR/latest-status.json" "$require_dashscope_key" <<'PY'
import json
import sys

path = sys.argv[1]
require_dashscope_key = sys.argv[2] == "1"
with open(path, "r", encoding="utf-8") as handle:
    report = json.load(handle)

speech = report.get("native_speech") or {}
tts = report.get("native_tts") or {}
errors = []
if speech.get("asr_runtime_mode") != "dashscope":
    errors.append(f"native_speech.asr_runtime_mode={speech.get('asr_runtime_mode')!r}")
if tts.get("tts_runtime_mode") != "dashscope":
    errors.append(f"native_tts.tts_runtime_mode={tts.get('tts_runtime_mode')!r}")
if require_dashscope_key and tts.get("dashscope_available") is not True:
    errors.append("native_tts.dashscope_available is not true")
if errors:
    raise SystemExit("Device smoke expected DashScope runtime modes: " + ", ".join(errors))
print(f"Checked default device smoke runtime modes in {path}: ASR/TTS dashscope")
PY
}

launch_device_smoke_with_retries() {
  local attempts="${SILVERCARE_DEVICE_LAUNCH_ATTEMPTS:-10}"
  local retry_seconds="${SILVERCARE_DEVICE_LAUNCH_RETRY_SECONDS:-6}"
  local attempt

  rm -f "$BUILD_ROOT"/launch-attempt-*.json "$BUILD_ROOT"/launch-attempt-*.log
  : >"$LAUNCH_LOG"

  for ((attempt = 1; attempt <= attempts; attempt += 1)); do
    local attempt_json="$BUILD_ROOT/launch-attempt-$attempt.json"
    local attempt_log="$BUILD_ROOT/launch-attempt-$attempt.log"
    printf 'Launch attempt %s/%s\n' "$attempt" "$attempts" | tee -a "$LAUNCH_LOG"

    if xcrun devicectl device process launch \
      --device "$DEVICE_ID" \
      --terminate-existing \
      --activate \
      "$APP_BUNDLE_ID" \
      --silvercare-simulator-automation \
      --silvercare-run-local-benchmarks \
      --json-output "$attempt_json" \
      --log-output "$attempt_log"; then
      redact_dashscope_key_in_file "$attempt_json"
      cp "$attempt_log" "$LAUNCH_LOG"
      cp "$attempt_json" "$BUILD_ROOT/launch.json"
      redact_dashscope_key_in_file "$BUILD_ROOT/launch.json"
      return 0
    fi

    redact_dashscope_key_in_file "$attempt_json"
    {
      printf '\n[launch attempt %s failed]\n' "$attempt"
      cat "$attempt_log"
    } >>"$LAUNCH_LOG"
    if [[ -f "$attempt_json" ]]; then
      cp "$attempt_json" "$BUILD_ROOT/launch.json"
    fi

    if grep -qi 'locked' "$attempt_log"; then
      local lock_state_log="$BUILD_ROOT/launch-attempt-$attempt-lock-state.log"
      record_device_lock_state "$lock_state_log"
      {
        printf '\n[device lockState after launch attempt %s]\n' "$attempt"
        cat "$lock_state_log"
      } >>"$LAUNCH_LOG"

      if (( attempt < attempts )); then
        if device_lock_state_requires_passcode "$lock_state_log"; then
          printf 'iPhone lockState requires passcode; unlock it and keep the screen awake. Retrying in %ss...\n' "$retry_seconds" >&2
        else
          printf 'CoreDevice launch returned a locked/denied response, but lockState does not require passcode. Retrying in %ss...\n' "$retry_seconds" >&2
        fi
        sleep "$retry_seconds"
        continue
      fi
      if device_lock_state_requires_passcode "$lock_state_log"; then
        return 2
      fi
      return 3
    fi

    return 1
  done

  return 2
}

require_tool xcodebuild
require_tool xcrun
require_tool node
require_tool npm
require_tool xcodegen

if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(detect_device_id)"
fi
if [[ -z "$DEVICE_ID" ]]; then
  printf 'No connected iPhone was found. Connect and unlock an iPhone, then rerun.\n' >&2
  exit 1
fi

mkdir -p "$BUILD_ROOT"
rm -rf "$DERIVED_DATA" "$BENCHMARK_REPORT_DIR" "$DIAGNOSTIC_REPORT_DIR"
mkdir -p "$BENCHMARK_REPORT_DIR" "$DIAGNOSTIC_REPORT_DIR"

log "Using iPhone device: $DEVICE_ID"
xcrun devicectl list devices --filter "identifier == '$DEVICE_ID' OR hardwareProperties.udid == '$DEVICE_ID' OR name CONTAINS '$DEVICE_ID'" \
  --json-output "$BUILD_ROOT/devices.json" \
  --log-output "$BUILD_ROOT/devices.log" >/dev/null 2>&1 || true
record_device_lock_state "$LOCK_STATE_PATH"

log "Regenerating Xcode project"
(cd "$IOS_DIR" && xcodegen generate)

log "Running JavaScript checks and bridge validation"
(cd "$ROOT_DIR" && npm run check:js)

PROJECT_DEVELOPMENT_TEAM="$(project_development_team)"
EFFECTIVE_DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM_OVERRIDE:-$PROJECT_DEVELOPMENT_TEAM}"
log "Recording device signing preflight"
write_signing_preflight "$PROJECT_DEVELOPMENT_TEAM" "$EFFECTIVE_DEVELOPMENT_TEAM"
verify_unsigned_iphoneos_bundle

log "Building app for connected iPhone"
BUILD_LOG="$BUILD_ROOT/xcodebuild-device.log"
build_args=(
  -project "$IOS_DIR/SilverCareiOS.xcodeproj"
  -scheme SilverCareiOS
  -destination "id=$DEVICE_ID"
  -derivedDataPath "$DERIVED_DATA"
  -configuration Debug
  -allowProvisioningUpdates
  build
)
if [[ -n "$DEVELOPMENT_TEAM_OVERRIDE" ]]; then
  build_args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_OVERRIDE")
fi
if [[ -n "$PROVISIONING_PROFILE_SPECIFIER_OVERRIDE" ]]; then
  build_args+=(PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_SPECIFIER_OVERRIDE")
fi
if [[ -n "$CODE_SIGN_IDENTITY_OVERRIDE" ]]; then
  build_args+=(CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY_OVERRIDE")
fi
if ! xcodebuild "${build_args[@]}" >"$BUILD_LOG" 2>&1; then
  SIGNED_BUILD_STATUS="failed"
  tail -n 80 "$BUILD_LOG" >&2
  if grep -Eq 'No Account for Team|No profiles for' "$BUILD_LOG"; then
    write_summary "blocked_by_signing" "missing_xcode_account_or_provisioning_profile"
  else
    write_summary "failed" "signed_device_build_failed"
  fi
  explain_signing_failure "$BUILD_LOG"
  exit 1
fi
SIGNED_BUILD_STATUS="passed"

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Debug-iphoneos" -maxdepth 1 -name 'SilverCareiOS.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  printf 'Could not locate SilverCareiOS.app under %s\n' "$DERIVED_DATA/Build/Products/Debug-iphoneos" >&2
  exit 1
fi
SILVERCARE_IOS_APP_PATH="$APP_PATH" \
  SILVERCARE_REQUIRE_IOS_APP_BUNDLE_RUNTIME=1 \
  SILVERCARE_IOS_REQUIRE_APP_BUNDLE_PLATFORM=IOS \
  node "$ROOT_DIR/tools/check-ios-native-runtime.mjs"

log "Installing app on iPhone"
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH" \
  --json-output "$BUILD_ROOT/install.json" \
  --log-output "$BUILD_ROOT/install.log"

seed_device_local_benchmark_fixtures

log "Launching app on iPhone with device smoke"
export DEVICECTL_CHILD_SILVERCARE_IOS_LOCAL_BENCHMARK_TESTS="$LOCAL_BENCHMARK_TESTS"
export DEVICECTL_CHILD_SILVERCARE_IOS_FORCE_DASHSCOPE_RUNTIME=1
if [[ "$PREPARE_DEVICE_LOCAL_ASR" == "1" ]]; then
  export DEVICECTL_CHILD_SILVERCARE_IOS_MODEL_ROOT="silvercare_seed/models"
  export DEVICECTL_CHILD_SILVERCARE_IOS_MODEL_SEED_DIR="silvercare_seed"
fi
if [[ -n "${DASHSCOPE_API_KEY:-}" ]]; then
  export DEVICECTL_CHILD_DASHSCOPE_API_KEY="$DASHSCOPE_API_KEY"
fi
LAUNCH_LOG="$BUILD_ROOT/launch.log"
launch_status=0
launch_device_smoke_with_retries || launch_status=$?
if [[ "$launch_status" != "0" ]]; then
  redact_dashscope_key_in_file "$BUILD_ROOT/launch.json"
  if [[ "$launch_status" == "2" ]]; then
    write_summary "blocked_by_locked_device" "iphone_locked_during_launch"
    printf '\nThe app installed successfully, but the iPhone stayed locked while devicectl tried to launch it. Unlock the iPhone, keep the screen awake, then rerun:\n\n  npm run test:ios:device\n\n' >&2
  elif [[ "$launch_status" == "3" ]] || grep -qi 'locked' "$LAUNCH_LOG"; then
    write_summary "failed" "device_launch_service_denied_while_lock_state_unlocked"
    printf '\nThe app installed successfully, but CoreDevice rejected launch with a locked/denied response even though devicectl lockState did not report passcodeRequired=true. Replug the iPhone or restart Xcode/CoreDevice services, then rerun:\n\n  npm run test:ios:device\n\nLock-state evidence: %s\n\n' "$LOCK_STATE_PATH" >&2
  else
    write_summary "failed" "device_launch_failed"
  fi
  exit 1
fi
redact_dashscope_key_in_file "$BUILD_ROOT/launch.json"

PID="$(json_value "$BUILD_ROOT/launch.json" 'info.process.processIdentifier')"
if [[ -n "$PID" ]]; then
  printf 'Launched process pid: %s\n' "$PID"
fi

log "Waiting for device benchmark reports"
sleep "${SILVERCARE_DEVICE_SMOKE_WAIT_SECONDS:-25}"

log "Listing app benchmark files"
xcrun devicectl device info files \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --subdirectory Documents/benchmarks \
  --json-output "$BUILD_ROOT/benchmark-files.json" \
  --log-output "$BUILD_ROOT/benchmark-files.log" || true

log "Copying app benchmark and diagnostic artifacts"
xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --source Documents/benchmarks \
  --destination "$BENCHMARK_REPORT_DIR" \
  --remove-existing-content true \
  --json-output "$BUILD_ROOT/copy-benchmarks.json" \
  --log-output "$BUILD_ROOT/copy-benchmarks.log" || true

DEVICE_BENCHMARK_REPORT_DIR="$BENCHMARK_REPORT_DIR"
if [[ ! -f "$DEVICE_BENCHMARK_REPORT_DIR/latest-status.json" && -f "$BENCHMARK_REPORT_DIR/benchmarks/latest-status.json" ]]; then
  DEVICE_BENCHMARK_REPORT_DIR="$BENCHMARK_REPORT_DIR/benchmarks"
fi
if [[ "$PREPARE_DEVICE_LOCAL_ASR" == "1" ]]; then
  SILVERCARE_IOS_REQUIRE_ASR_BENCHMARK=1 \
  SILVERCARE_IOS_REQUIRE_SCENARIO_FIXTURES=1 \
  SILVERCARE_IOS_REQUIRE_SCENARIO_ASR=1 \
    node "$ROOT_DIR/tools/check-ios-benchmark-reports.mjs" "$DEVICE_BENCHMARK_REPORT_DIR" "$LOCAL_BENCHMARK_TESTS"
else
  node "$ROOT_DIR/tools/check-ios-benchmark-reports.mjs" "$DEVICE_BENCHMARK_REPORT_DIR" "$LOCAL_BENCHMARK_TESTS"
fi
assert_default_cloud_runtime_report

xcrun devicectl device copy from \
  --device "$DEVICE_ID" \
  --domain-type appDataContainer \
  --domain-identifier "$APP_BUNDLE_ID" \
  --source Documents/diagnostics \
  --destination "$DIAGNOSTIC_REPORT_DIR" \
  --remove-existing-content true \
  --json-output "$BUILD_ROOT/copy-diagnostics.json" \
  --log-output "$BUILD_ROOT/copy-diagnostics.log" || true

log "Checking installed app entry"
xcrun devicectl device info apps \
  --device "$DEVICE_ID" \
  --bundle-id "$APP_BUNDLE_ID" \
  --json-output "$BUILD_ROOT/apps.json" \
  --log-output "$BUILD_ROOT/apps.log"

write_summary "passed" ""
printf '\nDevice smoke completed.\n'
printf 'Device: %s\n' "$DEVICE_ID"
printf 'Artifacts: %s\n' "$BUILD_ROOT"
printf 'Benchmarks: %s\n' "$BENCHMARK_REPORT_DIR"
printf 'Diagnostics: %s\n' "$DIAGNOSTIC_REPORT_DIR"
