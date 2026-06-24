# iOS Native Runtime Artifacts

This directory is the source-of-truth handoff point for iOS native runtime
artifacts that make the Swift migration equivalent to the Android native stack.

## Required MNN runtime

Android ships JNI libraries under `app/src/main/jniLibs/arm64-v8a/` and calls
them through `MnnNativeBridge`. The iOS app expects an equivalent runtime to
export the C ABI documented in `SilverCareMNNRuntimeABI.h`.

The official Alibaba MNN 3.5.0 iOS `arm64` static framework is vendored under:

```text
ios/Native/Vendor/MNN-3.5.0-ios/MNN-iOS-CPU-GPU/Static/MNN.framework
```

That framework is the core dependency for building `SilverCareMNNRuntime`, but
it does not export the SilverCare C ABI by itself.

The current device wrapper is built by:

```sh
ios/Tools/build_mnn_runtime_wrapper.sh
```

It produces:

```text
ios/Native/Vendor/SilverCareMNNRuntime.xcframework/ios-arm64/libsilvercare_mnn_runtime.dylib
```

This artifact is an iPhoneOS `arm64` runtime and is embedded into device builds.
It does not contain an iOS simulator slice.

Accepted checked-in or vendored locations:

```text
ios/Native/SilverCareMNNRuntime.framework/SilverCareMNNRuntime
ios/Native/libsilvercare_mnn_runtime.framework/libsilvercare_mnn_runtime
ios/Native/SilverCareMNNRuntime.xcframework
ios/Native/libsilvercare_mnn_runtime.a
ios/Native/libsilvercare_mnn_runtime.dylib
ios/Native/Vendor/SilverCareMNNRuntime.framework/SilverCareMNNRuntime
ios/Native/Vendor/libsilvercare_mnn_runtime.framework/libsilvercare_mnn_runtime
ios/Native/Vendor/SilverCareMNNRuntime.xcframework
ios/Native/Vendor/libsilvercare_mnn_runtime.a
ios/Native/Vendor/libsilvercare_mnn_runtime.dylib
```

Dynamic `.framework`, `.xcframework`, and `.dylib` artifacts are embedded into
the app bundle by `ios/Tools/embed_native_runtime_artifacts.sh`. A static `.a`
can satisfy symbol inspection only after it is linked into the app executable;
the embed script cannot load a static archive at runtime.

Required exported symbols:

```text
silvercare_mnn_runtime_kind
silvercare_mnn_text_json
silvercare_mnn_vision_json_from_chw or silvercare_mnn_vision_json
```

`silvercare_mnn_supports_sme2` and `silvercare_mnn_free_string` are optional but
recommended.

## Required MNN TTS runtime

Android includes the experimental MNN TTS bridge through
`MnnTtsRuntimeBridge.kt` and the `mnn_tts` framework sources. The iOS app has an
equivalent dynamic boundary documented in `SilverCareMNNTTSRuntimeABI.h`.

The current device wrapper is built by:

```sh
ios/Tools/build_mnn_tts_runtime_wrapper.sh
```

It produces:

```text
ios/Native/Vendor/SilverCareMNNTTSRuntime.xcframework/ios-arm64/libsilvercare_mnn_tts_runtime.dylib
```

This artifact compiles the vendored MNN TTS BertVITS2 source against the vendored
Alibaba MNN 3.5.0 iOS core, exports the SilverCare TTS C ABI, and is embedded
into device builds. It does not contain an iOS simulator slice, and
`silvercare_mnn_tts_voice_quality_passed` must keep returning `0` until a real
device voice-quality pass succeeds.

Accepted checked-in or vendored locations:

```text
ios/Native/SilverCareMNNTTSRuntime.framework/SilverCareMNNTTSRuntime
ios/Native/libsilvercare_mnn_tts_runtime.framework/libsilvercare_mnn_tts_runtime
ios/Native/SilverCareMNNTTSRuntime.xcframework
ios/Native/libsilvercare_mnn_tts_runtime.xcframework
ios/Native/libsilvercare_mnn_tts_runtime.a
ios/Native/libsilvercare_mnn_tts_runtime.dylib
ios/Native/libmnn_tts.framework/libmnn_tts
ios/Native/libmnn_tts.xcframework
ios/Native/libmnn_tts.a
ios/Native/libmnn_tts.dylib
ios/Native/Vendor/SilverCareMNNTTSRuntime.framework/SilverCareMNNTTSRuntime
ios/Native/Vendor/libsilvercare_mnn_tts_runtime.framework/libsilvercare_mnn_tts_runtime
ios/Native/Vendor/SilverCareMNNTTSRuntime.xcframework
ios/Native/Vendor/libsilvercare_mnn_tts_runtime.xcframework
ios/Native/Vendor/libsilvercare_mnn_tts_runtime.a
ios/Native/Vendor/libsilvercare_mnn_tts_runtime.dylib
ios/Native/Vendor/libmnn_tts.framework/libmnn_tts
ios/Native/Vendor/libmnn_tts.xcframework
ios/Native/Vendor/libmnn_tts.a
ios/Native/Vendor/libmnn_tts.dylib
```

Dynamic `.framework`, `.xcframework`, and `.dylib` artifacts are embedded into
the app bundle by `ios/Tools/embed_native_runtime_artifacts.sh`. A static `.a`
can satisfy symbol inspection only after it is linked into the app executable;
the embed script cannot load a static archive at runtime.

The app bundle must ultimately contain one of:

```text
SilverCareiOS.app/Frameworks/SilverCareMNNTTSRuntime.framework/SilverCareMNNTTSRuntime
SilverCareiOS.app/Frameworks/libsilvercare_mnn_tts_runtime.framework/libsilvercare_mnn_tts_runtime
SilverCareiOS.app/Frameworks/libsilvercare_mnn_tts_runtime.dylib
SilverCareiOS.app/Frameworks/libmnn_tts.framework/libmnn_tts
SilverCareiOS.app/Frameworks/libmnn_tts.dylib
SilverCareiOS.app/libsilvercare_mnn_tts_runtime.dylib
SilverCareiOS.app/libmnn_tts.dylib
```

Required exported symbols:

```text
silvercare_mnn_tts_runtime_kind
silvercare_mnn_tts_voice_quality_passed
silvercare_mnn_tts_synthesize_wav
```

`silvercare_mnn_tts_free_string` is optional but recommended. The runtime must
return `1` from `silvercare_mnn_tts_voice_quality_passed` only after real-device
audibility and intelligibility validation; the iOS app keeps local MNN TTS out
of the main speaking path until that flag is true.

## Required Vosk runtime

The iOS local ASR path downloads and validates the Android-compatible
`vosk-model-small-cn-0.22` model layout. `ios/Native/Vendor/libvosk.xcframework`
now provides embeddable dynamic Vosk C API binaries for iPhoneOS `arm64` and
iOS simulator `arm64`.

Upstream status checked on 2026-06-24:

- The official Vosk installation page lists iOS support but says the iOS build
  is available on request from Alpha Cephei:
  https://alphacephei.com/vosk/install
- The upstream iOS demo README says the demo requires a Vosk-API library build
  and points to Alpha Cephei for details:
  https://github.com/alphacep/vosk-api/blob/master/ios/README
- The upstream iOS demo project links `libvosk.a` and ships `vosk_api.h`, so
  static archives are a legitimate upstream handoff format.

To replace or refresh the Vosk iOS artifact, install it with:

```sh
ios/Tools/install_vosk_runtime_artifact.sh /path/to/libvosk.xcframework
```

The script copies dynamic frameworks/xcframeworks/dylibs into
`ios/Native/Vendor`. For a complete static `libvosk.a` or static
`libvosk.xcframework`, it selectively links the Vosk C API symbols used by the
app into a dynamic `libvosk.xcframework` so the existing dynamic loader and Xcode
embed phase can use it. If a static archive is linked directly into the app
executable instead, `LocalVoskASRRuntime` also probes the main process image via
`dlopen(nil)`.

Current generated artifact:

```text
ios/Native/Vendor/libvosk.xcframework/ios-arm64/libvosk.dylib
ios/Native/Vendor/libvosk.xcframework/ios-arm64-simulator/libvosk.dylib
```

For production distribution, verify artifact provenance and license terms with
the Vosk supplier before release.

Accepted checked-in or vendored locations:

```text
ios/Native/vosk.framework/vosk
ios/Native/libvosk.framework/libvosk
ios/Native/libvosk.dylib
ios/Native/libvosk.a
ios/Native/Vendor/vosk.framework/vosk
ios/Native/Vendor/libvosk.framework/libvosk
ios/Native/Vendor/libvosk.dylib
ios/Native/Vendor/libvosk.a
ios/Native/Vendor/vosk.xcframework
ios/Native/Vendor/libvosk.xcframework
```

Dynamic `.framework`, `.xcframework`, and `.dylib` artifacts are embedded into
the app bundle by `ios/Tools/embed_native_runtime_artifacts.sh`.

The app bundle must ultimately contain one of:

```text
SilverCareiOS.app/Frameworks/vosk.framework/vosk
SilverCareiOS.app/Frameworks/libvosk.framework/libvosk
SilverCareiOS.app/Frameworks/libvosk.dylib
SilverCareiOS.app/libvosk.dylib
```

Required exported symbols:

```text
vosk_model_new
vosk_model_free
vosk_recognizer_new
vosk_recognizer_free
vosk_recognizer_set_words
vosk_recognizer_accept_waveform
vosk_recognizer_final_result
```

## Verification

Default source-contract check:

```sh
npm run check:js
```

Strict runtime check for final parity:

```sh
SILVERCARE_REQUIRE_IOS_NATIVE_RUNTIME=1 node tools/check-ios-native-runtime.mjs
```

After building an app bundle, verify bundled symbols too:

```sh
SILVERCARE_IOS_APP_PATH=/path/to/SilverCareiOS.app \
  node tools/check-ios-native-runtime.mjs
```

For a device smoke build, the app bundle itself must contain loadable iOS
device-platform runtime binaries; source-tree artifacts are not enough:

```sh
SILVERCARE_IOS_APP_PATH=/path/to/SilverCareiOS.app \
  SILVERCARE_REQUIRE_IOS_APP_BUNDLE_RUNTIME=1 \
  SILVERCARE_IOS_REQUIRE_APP_BUNDLE_PLATFORM=IOS \
  node tools/check-ios-native-runtime.mjs
```

`npm run test:ios:device` runs this strict app-bundle check against an unsigned
generic iPhoneOS build before attempting the signed install/launch path.

Final Android parity requires the strict check to pass and the iOS local
benchmark reports for `asr`, `vision`, `text`, `text_suite`, `text_inquiry`, and
`tts` to return `success: true` on device.

The Xcode target runs `ios/Tools/embed_native_runtime_artifacts.sh` after build.
When any supported runtime artifact is present under `ios/Native` or
`ios/Native/Vendor`, the script copies it into `SilverCareiOS.app/Frameworks`
and signs the artifact/app bundle when Xcode signing is active.
