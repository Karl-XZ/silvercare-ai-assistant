#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns a static string such as "mnn-ios-arm64+sme2".
const char *silvercare_mnn_runtime_kind(void);

// Returns 1 when the current device/runtime can use SME2 tuning, otherwise 0.
int32_t silvercare_mnn_supports_sme2(void);

// Preferred iOS vision ABI. `chw_rgb` must contain 3 * 640 * 640 float values
// in RGB CHW order, matching Android's MnnNativeBridge preprocessing.
// The returned UTF-8 JSON string must be released with silvercare_mnn_free_string
// when that release function is exported by the runtime.
char *silvercare_mnn_vision_json_from_chw(
    const char *model_dir,
    const char *prompt,
    const float *chw_rgb,
    int32_t image_width,
    int32_t image_height,
    const char *role
);

// Compatibility fallback for runtimes that want to decode the data URL natively.
char *silvercare_mnn_vision_json(
    const char *model_dir,
    const char *prompt,
    const char *image_data_url,
    const char *role
);

char *silvercare_mnn_text_json(
    const char *model_dir,
    const char *prompt,
    const char *role,
    const char *tuning_config_json,
    int32_t max_new_tokens,
    const char *end_with
);

void silvercare_mnn_free_string(char *value);

#ifdef __cplusplus
}
#endif
