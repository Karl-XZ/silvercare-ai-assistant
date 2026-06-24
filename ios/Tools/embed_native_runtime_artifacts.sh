#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
NATIVE_DIR="$IOS_DIR/Native"
FRAMEWORKS_DIR="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-}"
APP_DIR="${TARGET_BUILD_DIR:-}/${CONTENTS_FOLDER_PATH:-}"

log() {
  printf 'SilverCare native runtime embed: %s\n' "$1"
}

copy_item() {
  local source="$1"
  local destination_dir="$2"
  if [[ ! -e "$source" ]]; then
    return 0
  fi
  mkdir -p "$destination_dir"
  local destination="$destination_dir/$(basename "$source")"
  rm -rf "$destination"
  if [[ -d "$source" ]]; then
    /usr/bin/ditto "$source" "$destination"
  else
    cp "$source" "$destination"
  fi
  log "embedded $(basename "$source")"
}

copy_xcframework_slice() {
  local source="$1"
  local destination_dir="$2"
  if [[ ! -d "$source" ]]; then
    return 0
  fi

  local platform_pattern='ios-arm64'
  local reject_pattern='simulator'
  if [[ "${PLATFORM_NAME:-}" == "iphonesimulator" ]]; then
    platform_pattern='simulator'
    reject_pattern='^$'
  fi

  local slice_dir=''
  while IFS= read -r candidate; do
    local base
    base="$(basename "$candidate")"
    if [[ "$base" == *"$platform_pattern"* && ! "$base" =~ $reject_pattern ]]; then
      slice_dir="$candidate"
      break
    fi
  done < <(find "$source" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ -z "$slice_dir" && "${PLATFORM_NAME:-}" != "iphonesimulator" ]]; then
    while IFS= read -r candidate; do
      local base
      base="$(basename "$candidate")"
      if [[ "$base" == ios-* && "$base" != *simulator* ]]; then
        slice_dir="$candidate"
        break
      fi
    done < <(find "$source" -mindepth 1 -maxdepth 1 -type d | sort)
  fi

  if [[ -z "$slice_dir" ]]; then
    log "no matching ${PLATFORM_NAME:-iOS} slice in $(basename "$source")"
    return 0
  fi

  local copied_slice=0
  while IFS= read -r artifact; do
    copy_item "$artifact" "$destination_dir"
    copied_slice=1
  done < <(find "$slice_dir" -mindepth 1 -maxdepth 2 \( -name '*.framework' -o -name '*.dylib' \) -print | sort)

  if [[ "$copied_slice" == "0" ]]; then
    log "$(basename "$source") slice $(basename "$slice_dir") has no dynamic framework or dylib to embed"
  fi
}

codesign_item() {
  local item="$1"
  if [[ ! -e "$item" ]]; then
    return 0
  fi
  if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
    return 0
  fi
  if [[ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    return 0
  fi
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$item"
}

if [[ -z "$FRAMEWORKS_DIR" || "$FRAMEWORKS_DIR" == "/" ]]; then
  log "skipping because FRAMEWORKS_FOLDER_PATH is unavailable"
  exit 0
fi

copied=0
for base in "$NATIVE_DIR" "$NATIVE_DIR/Vendor"; do
  for item in \
    "SilverCareMNNRuntime.framework" \
    "libsilvercare_mnn_runtime.framework" \
    "SilverCareMNNRuntime.xcframework" \
    "libsilvercare_mnn_runtime.dylib" \
    "SilverCareMNNTTSRuntime.framework" \
    "libsilvercare_mnn_tts_runtime.framework" \
    "SilverCareMNNTTSRuntime.xcframework" \
    "libsilvercare_mnn_tts_runtime.xcframework" \
    "libsilvercare_mnn_tts_runtime.dylib" \
    "libmnn_tts.framework" \
    "libmnn_tts.xcframework" \
    "libmnn_tts.dylib" \
    "vosk.framework" \
    "libvosk.framework" \
    "vosk.xcframework" \
    "libvosk.xcframework" \
    "libvosk.dylib"; do
    source="$base/$item"
    if [[ -e "$source" ]]; then
      if [[ "$source" == *.xcframework ]]; then
        copy_xcframework_slice "$source" "$FRAMEWORKS_DIR"
      else
        copy_item "$source" "$FRAMEWORKS_DIR"
      fi
      copied=1
    fi
  done
done

if [[ "$copied" == "0" ]]; then
  log "no optional iOS MNN/Vosk/TTS artifacts found under ios/Native"
  exit 0
fi

find "$FRAMEWORKS_DIR" -maxdepth 1 \( -name 'SilverCareMNNRuntime.framework' -o -name 'libsilvercare_mnn_runtime.framework' -o -name 'libsilvercare_mnn_runtime.dylib' -o -name 'SilverCareMNNTTSRuntime.framework' -o -name 'libsilvercare_mnn_tts_runtime.framework' -o -name 'libsilvercare_mnn_tts_runtime.dylib' -o -name 'libmnn_tts.framework' -o -name 'libmnn_tts.dylib' -o -name 'vosk.framework' -o -name 'libvosk.framework' -o -name 'libvosk.dylib' \) -print0 |
  while IFS= read -r -d '' artifact; do
    codesign_item "$artifact"
  done

if [[ -n "$APP_DIR" && -d "$APP_DIR" && "${CODE_SIGNING_ALLOWED:-YES}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$APP_DIR"
fi
