#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
NATIVE_DIR="$IOS_DIR/Native"
TTS_ROOT="$ROOT_DIR/third_party/mnn/source/MNN/apps/frameworks/mnn_tts"
TTS_SRC="$NATIVE_DIR/SilverCareMNNTTSRuntime/SilverCareMNNTTSRuntime.mm"
MNN_ROOT="$NATIVE_DIR/Vendor/MNN-3.5.0-ios/MNN-iOS-CPU-GPU/Static"
MNN_FRAMEWORK="$MNN_ROOT/MNN.framework"
BUILD_DIR="$IOS_DIR/build/SilverCareMNNTTSRuntime"
OBJ_DIR="$BUILD_DIR/objects"
LIB_DIR="$BUILD_DIR/iphoneos"
HEADERS_DIR="$BUILD_DIR/Headers"
OUTPUT="$NATIVE_DIR/Vendor/SilverCareMNNTTSRuntime.xcframework"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

if [[ ! -f "$MNN_FRAMEWORK/MNN" ]]; then
  printf 'Missing official MNN iOS framework: %s\n' "$MNN_FRAMEWORK" >&2
  exit 1
fi

if [[ ! -d "$TTS_ROOT" ]]; then
  printf 'Missing MNN TTS source tree: %s\n' "$TTS_ROOT" >&2
  exit 1
fi

rm -rf "$BUILD_DIR" "$OUTPUT"
mkdir -p "$OBJ_DIR" "$LIB_DIR" "$HEADERS_DIR"
cp "$NATIVE_DIR/SilverCareMNNTTSRuntimeABI.h" "$HEADERS_DIR/"

COMMON_FLAGS=(
  -target arm64-apple-ios15.0
  -isysroot "$SDK_PATH"
  -std=c++17
  -DMNN_TTS_BUILD_SUPERTONIC=0
  -F "$MNN_ROOT"
  -I "$MNN_FRAMEWORK/Headers"
  -I "$TTS_ROOT/include"
  -I "$TTS_ROOT/include/bertvits2"
  -I "$TTS_ROOT/include/piper"
  -I "$TTS_ROOT/../3rd_party/include"
)

SOURCES=(
  "$TTS_SRC"
  "$TTS_ROOT/src/mnn_tts_config.cpp"
  "$TTS_ROOT/src/mnn_tts_sdk.cpp"
  "$TTS_ROOT/src/mnn_tts_logger.cpp"
  "$TTS_ROOT/src/bertvits2/an_to_cn.cpp"
  "$TTS_ROOT/src/bertvits2/utils.cpp"
  "$TTS_ROOT/src/bertvits2/mnn_bertvits2_tts_impl.cpp"
  "$TTS_ROOT/src/bertvits2/text_preprocessor.cpp"
  "$TTS_ROOT/src/bertvits2/pinyin.cpp"
  "$TTS_ROOT/src/bertvits2/chinese_g2p.cpp"
  "$TTS_ROOT/src/bertvits2/chinese_bert.cpp"
  "$TTS_ROOT/src/bertvits2/english_bert.cpp"
  "$TTS_ROOT/src/bertvits2/english_g2p.cpp"
  "$TTS_ROOT/src/bertvits2/tone_adjuster.cpp"
  "$TTS_ROOT/src/bertvits2/tts_generator.cpp"
  "$TTS_ROOT/src/bertvits2/word_spliter.cpp"
)

OBJECTS=()
for source in "${SOURCES[@]}"; do
  object="$OBJ_DIR/$(basename "$source").o"
  xcrun clang++ "${COMMON_FLAGS[@]}" -c "$source" -o "$object"
  OBJECTS+=("$object")
done

xcrun clang++ \
  -target arm64-apple-ios15.0 \
  -isysroot "$SDK_PATH" \
  -dynamiclib \
  -install_name '@rpath/libsilvercare_mnn_tts_runtime.dylib' \
  -F "$MNN_ROOT" \
  "${OBJECTS[@]}" \
  -framework MNN \
  -framework Foundation \
  -framework UIKit \
  -framework Metal \
  -framework CoreML \
  -framework Accelerate \
  -lz \
  -lc++ \
  -o "$LIB_DIR/libsilvercare_mnn_tts_runtime.dylib"

xcodebuild -create-xcframework \
  -library "$LIB_DIR/libsilvercare_mnn_tts_runtime.dylib" \
  -headers "$HEADERS_DIR" \
  -output "$OUTPUT" >/dev/null

printf 'Built %s\n' "$OUTPUT"
