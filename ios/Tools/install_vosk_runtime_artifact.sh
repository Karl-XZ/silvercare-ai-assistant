#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
VENDOR_DIR="$IOS_DIR/Native/Vendor"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SIMULATOR_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
MIN_IOS_VERSION="${SILVERCARE_IOS_MIN_VERSION:-15.0}"

usage() {
  cat >&2 <<'EOF'
Usage:
  ios/Tools/install_vosk_runtime_artifact.sh /path/to/vosk.framework
  ios/Tools/install_vosk_runtime_artifact.sh /path/to/libvosk.framework
  ios/Tools/install_vosk_runtime_artifact.sh /path/to/libvosk.xcframework
  ios/Tools/install_vosk_runtime_artifact.sh /path/to/libvosk.dylib
  ios/Tools/install_vosk_runtime_artifact.sh /path/to/libvosk.a

The official Vosk iOS demo expects an externally supplied Vosk-API library.
Dynamic frameworks, xcframeworks, and dylibs are copied into ios/Native/Vendor.
Static libvosk.a archives and static libvosk.xcframework bundles are converted
into ios/Native/Vendor/libvosk.xcframework with dynamic libvosk.dylib slices
when the archive contains the required iOS objects.
EOF
}

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 2
fi

SOURCE="$1"
if [[ ! -e "$SOURCE" ]]; then
  printf 'Vosk artifact does not exist: %s\n' "$SOURCE" >&2
  exit 1
fi

mkdir -p "$VENDOR_DIR"

copy_artifact() {
  local source="$1"
  local destination="$VENDOR_DIR/$(basename "$source")"
  rm -rf "$destination"
  if [[ -d "$source" ]]; then
    /usr/bin/ditto "$source" "$destination"
  else
    cp "$source" "$destination"
  fi
  printf 'Installed %s\n' "$destination"
}

verify_required_symbols() {
  local binary="$1"
  local missing=0
  for symbol in \
    vosk_model_new \
    vosk_model_free \
    vosk_recognizer_new \
    vosk_recognizer_free \
    vosk_recognizer_set_words \
    vosk_recognizer_accept_waveform \
    vosk_recognizer_final_result; do
    if ! /usr/bin/nm -gU "$binary" 2>/dev/null | rg -q "_?$symbol\\b"; then
      printf 'Missing required Vosk symbol in %s: %s\n' "$binary" "$symbol" >&2
      missing=1
    fi
  done
  if [[ "$missing" != "0" ]]; then
    exit 1
  fi
}

write_bridge_source() {
  local output="$1"
  cat > "$output" <<'EOF'
extern "C" {
void *vosk_model_new(const char *model_path);
void vosk_model_free(void *model);
void *vosk_recognizer_new(void *model, float sample_rate);
void vosk_recognizer_free(void *recognizer);
void vosk_recognizer_set_words(void *recognizer, int words);
int vosk_recognizer_accept_waveform(void *recognizer, const char *data, int length);
const char *vosk_recognizer_final_result(void *recognizer);
void vosk_set_log_level(int level);
void *silvercare_vosk_required_symbols[] = {
    (void *)&vosk_model_new,
    (void *)&vosk_model_free,
    (void *)&vosk_recognizer_new,
    (void *)&vosk_recognizer_free,
    (void *)&vosk_recognizer_set_words,
    (void *)&vosk_recognizer_accept_waveform,
    (void *)&vosk_recognizer_final_result,
    (void *)&vosk_set_log_level,
};
const char *silvercare_vosk_runtime_kind(void) { return "vosk-ios-static-bridge"; }
}
EOF
}

write_minimal_header() {
  local output="$1"
  cat > "$output" <<'EOF'
#ifndef VOSK_API_H
#define VOSK_API_H
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VoskModel VoskModel;
typedef struct VoskRecognizer VoskRecognizer;
VoskModel *vosk_model_new(const char *model_path);
void vosk_model_free(VoskModel *model);
VoskRecognizer *vosk_recognizer_new(VoskModel *model, float sample_rate);
void vosk_recognizer_free(VoskRecognizer *recognizer);
void vosk_recognizer_set_words(VoskRecognizer *recognizer, int words);
int vosk_recognizer_accept_waveform(VoskRecognizer *recognizer, const char *data, int length);
const char *vosk_recognizer_final_result(VoskRecognizer *recognizer);
void vosk_set_log_level(int level);
#ifdef __cplusplus
}
#endif
#endif
EOF
}

prepare_headers() {
  local source="$1"
  local destination="$2"
  mkdir -p "$destination"
  local header=""
  if [[ -f "$(dirname "$source")/vosk_api.h" ]]; then
    header="$(dirname "$source")/vosk_api.h"
  else
    header="$(find "$source" "$(dirname "$source")" -maxdepth 4 -name 'vosk_api.h' -print -quit 2>/dev/null || true)"
  fi
  if [[ -n "$header" && -f "$header" ]]; then
    cp "$header" "$destination/vosk_api.h"
  else
    write_minimal_header "$destination/vosk_api.h"
  fi
}

build_dynamic_dylib_from_archive() {
  local source="$1"
  local output="$2"
  local target="$3"
  local sdk="$4"
  local bridge_source="$5"
  local arch="${target%%-*}"
  if ! /usr/bin/lipo -archs "$source" 2>/dev/null | tr ' ' '\n' | rg -qx "$arch"; then
    printf 'Static archive does not contain required %s slice: %s\n' "$arch" "$source" >&2
    exit 1
  fi
  rm -f "$output"
  xcrun clang++ \
    -target "$target" \
    -isysroot "$sdk" \
    -dynamiclib \
    -install_name '@rpath/libvosk.dylib' \
    "$bridge_source" \
    "$source" \
    -framework Foundation \
    -framework Accelerate \
    -lz \
    -lc++ \
    -o "$output" || {
      cat >&2 <<EOF
Failed to convert static Vosk archive into a dynamic dylib.

The selective linker bridge references only the Vosk C API required by the app.
If this still fails, the supplied libvosk.a is missing runtime dependencies
needed for iOS linking. Ask Alpha Cephei for a complete iOS
framework/dylib/xcframework, or provide the dependent static archives.
EOF
      rm -f "$output"
      exit 1
    }
  verify_required_symbols "$output"
}

create_dynamic_xcframework() {
  local source="$1"
  local temp_dir
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/silvercare-vosk.XXXXXX")"
  trap 'rm -rf "$temp_dir"' RETURN

  local bridge_source="$temp_dir/silvercare_vosk_link_bridge.cpp"
  local headers="$temp_dir/Headers"
  write_bridge_source "$bridge_source"
  prepare_headers "$source" "$headers"

  local create_args=()
  if [[ -f "$source" ]]; then
    local device_dylib="$temp_dir/ios-arm64/libvosk.dylib"
    mkdir -p "$(dirname "$device_dylib")"
    build_dynamic_dylib_from_archive \
      "$source" \
      "$device_dylib" \
      "arm64-apple-ios${MIN_IOS_VERSION}" \
      "$SDK_PATH" \
      "$bridge_source"
    create_args+=(-library "$device_dylib" -headers "$headers")
  else
    local device_archive=""
    local simulator_archive=""
    while IFS= read -r archive; do
      local slice_name
      slice_name="$(basename "$(dirname "$archive")")"
      if [[ "$slice_name" == *simulator* ]]; then
        simulator_archive="$archive"
      elif [[ -z "$device_archive" ]]; then
        device_archive="$archive"
      fi
    done < <(find "$source" -mindepth 2 -maxdepth 3 -name 'libvosk.a' -print | sort)

    if [[ -n "$device_archive" ]]; then
      local device_dylib="$temp_dir/ios-arm64/libvosk.dylib"
      mkdir -p "$(dirname "$device_dylib")"
      build_dynamic_dylib_from_archive \
        "$device_archive" \
        "$device_dylib" \
        "arm64-apple-ios${MIN_IOS_VERSION}" \
        "$SDK_PATH" \
        "$bridge_source"
      create_args+=(-library "$device_dylib" -headers "$headers")
    fi

    if [[ -n "$simulator_archive" ]]; then
      local simulator_dylib="$temp_dir/ios-arm64-simulator/libvosk.dylib"
      mkdir -p "$(dirname "$simulator_dylib")"
      build_dynamic_dylib_from_archive \
        "$simulator_archive" \
        "$simulator_dylib" \
        "arm64-apple-ios${MIN_IOS_VERSION}-simulator" \
        "$SIMULATOR_SDK_PATH" \
        "$bridge_source"
      create_args+=(-library "$simulator_dylib" -headers "$headers")
    fi
  fi

  if [[ "${#create_args[@]}" == "0" ]]; then
    printf 'No usable static libvosk.a slice found in %s\n' "$source" >&2
    exit 1
  fi

  local output="$VENDOR_DIR/libvosk.xcframework"
  rm -rf "$output"
  xcodebuild -create-xcframework "${create_args[@]}" -output "$output" >/dev/null
  while IFS= read -r binary; do
    verify_required_symbols "$binary"
  done < <(find "$output" -name 'libvosk.dylib' -print | sort)
  printf 'Installed %s\n' "$output"
}

case "$SOURCE" in
  *.xcframework)
    if find "$SOURCE" -mindepth 2 -maxdepth 3 -name 'libvosk.a' -print -quit | rg -q .; then
      create_dynamic_xcframework "$SOURCE"
    else
      copy_artifact "$SOURCE"
    fi
    ;;
  *.framework|*.dylib)
    copy_artifact "$SOURCE"
    ;;
  *.a)
    create_dynamic_xcframework "$SOURCE"
    ;;
  *)
    printf 'Unsupported Vosk artifact type: %s\n' "$SOURCE" >&2
    usage
    exit 2
    ;;
esac

printf '\nNext verification:\n'
printf '  npm run check:js\n'
printf '  SILVERCARE_REQUIRE_IOS_NATIVE_RUNTIME=1 node tools/check-ios-native-runtime.mjs\n'
