#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns a static string such as "mnn-tts-ios-arm64+bert-vits2".
const char *silvercare_mnn_tts_runtime_kind(void);

// Returns 1 only after a real-device voice-quality pass. The iOS app will not
// use local MNN TTS as a main speaking route while this returns 0.
int32_t silvercare_mnn_tts_voice_quality_passed(void);

// Synthesizes text to a WAV file and returns the generated file path as UTF-8.
// The runtime owns MNN TTS setup and may use cache_dir for temporary files.
// The returned string must be released with silvercare_mnn_tts_free_string when
// that release function is exported by the runtime.
char *silvercare_mnn_tts_synthesize_wav(
    const char *model_dir,
    const char *cache_dir,
    const char *text,
    const char *language
);

void silvercare_mnn_tts_free_string(char *value);

#ifdef __cplusplus
}
#endif
