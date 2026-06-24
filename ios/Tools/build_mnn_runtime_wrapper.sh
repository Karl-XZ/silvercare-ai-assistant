#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
NATIVE_DIR="$IOS_DIR/Native"
SRC="$NATIVE_DIR/SilverCareMNNRuntime/SilverCareMNNRuntime.mm"
MNN_ROOT="$NATIVE_DIR/Vendor/MNN-3.5.0-ios/MNN-iOS-CPU-GPU/Static"
MNN_FRAMEWORK="$MNN_ROOT/MNN.framework"
BUILD_DIR="$IOS_DIR/build/SilverCareMNNRuntime"
LIB_DIR="$BUILD_DIR/iphoneos"
HEADERS_DIR="$BUILD_DIR/Headers"
OUTPUT="$NATIVE_DIR/Vendor/SilverCareMNNRuntime.xcframework"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"

if [[ ! -f "$MNN_FRAMEWORK/MNN" ]]; then
  printf 'Missing official MNN iOS framework: %s\n' "$MNN_FRAMEWORK" >&2
  exit 1
fi

rm -rf "$BUILD_DIR" "$OUTPUT"
mkdir -p "$LIB_DIR" "$HEADERS_DIR"
cp "$NATIVE_DIR/SilverCareMNNRuntimeABI.h" "$HEADERS_DIR/"

xcrun clang++ \
  -target arm64-apple-ios15.0 \
  -isysroot "$SDK_PATH" \
  -std=c++17 \
  -dynamiclib \
  -install_name '@rpath/libsilvercare_mnn_runtime.dylib' \
  -F "$MNN_ROOT" \
  -I "$MNN_FRAMEWORK/Headers" \
  "$SRC" \
  -framework MNN \
  -framework Foundation \
  -framework UIKit \
  -framework Metal \
  -framework CoreML \
  -framework Accelerate \
  -lz \
  -lc++ \
  -o "$LIB_DIR/libsilvercare_mnn_runtime.dylib"

xcodebuild -create-xcframework \
  -library "$LIB_DIR/libsilvercare_mnn_runtime.dylib" \
  -headers "$HEADERS_DIR" \
  -output "$OUTPUT" >/dev/null

printf 'Built %s\n' "$OUTPUT"
