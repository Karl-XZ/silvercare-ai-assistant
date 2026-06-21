package com.silvercare.aiassistant;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Base64;

import org.json.JSONObject;

final class MnnNativeBridge implements MnnRuntimeBridge {
    private static final int VISION_INPUT_SIZE = 640;

    private final boolean available;
    private final String runtimeKind;

    MnnNativeBridge() {
        boolean loaded;
        String kind;
        try {
            System.loadLibrary("silvercare_mnn_runtime");
            kind = nativeRuntimeKind();
            loaded = kind.startsWith("mnn-");
        } catch (UnsatisfiedLinkError error) {
            kind = "unavailable";
            loaded = false;
        }
        runtimeKind = kind;
        available = loaded;
    }

    @Override
    public boolean isAvailable() {
        return available;
    }

    @Override
    public boolean supportsSme2() {
        if (!available) return false;
        try {
            return nativeSupportsSme2();
        } catch (UnsatisfiedLinkError error) {
            return false;
        }
    }

    @Override
    public String runtimeSummary() {
        if (!available) return "MNN Native Runtime 未加载";
        return runtimeKind + (supportsSme2() ? " · SME2 可用" : " · 未检测到 SME2");
    }

    @Override
    public String visionJson(String modelDir, String prompt, String imageDataUrl, String role) throws Exception {
        ensureAvailable();
        long started = DiagnosticLogger.start();
        DiagnosticLogger.event("native_vision_start", new JSONObject()
            .put("role", role)
            .put("prompt_chars", prompt == null ? 0 : prompt.length())
            .put("image_chars", imageDataUrl == null ? 0 : imageDataUrl.length()));
        VisionInput input = VisionInput.from(imageDataUrl);
        try {
            String output = nativeVisionJson(
                modelDir,
                prompt,
                input.chwRgb,
                input.imageWidth,
                input.imageHeight,
                role
            );
            DiagnosticLogger.event("native_vision_end", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("image_width", input.imageWidth)
                .put("image_height", input.imageHeight)
                .put("output_chars", output == null ? 0 : output.length())
                .put("output", DiagnosticLogger.excerpt(output)));
            return output;
        } catch (UnsatisfiedLinkError error) {
            DiagnosticLogger.event("native_vision_error", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("error", error.getMessage()));
            throw new IllegalStateException("端侧 DAMO-YOLO 视觉检测接口未实现。", error);
        }
    }

    @Override
    public String textJson(String modelDir, String prompt, String role, String tuningConfigJson) throws Exception {
        return textJson(modelDir, prompt, role, tuningConfigJson, 0);
    }

    @Override
    public String textJson(
        String modelDir,
        String prompt,
        String role,
        String tuningConfigJson,
        int maxNewTokens
    ) throws Exception {
        return textJson(modelDir, prompt, role, tuningConfigJson, maxNewTokens, null);
    }

    @Override
    public String textJson(
        String modelDir,
        String prompt,
        String role,
        String tuningConfigJson,
        int maxNewTokens,
        String endWith
    ) throws Exception {
        ensureAvailable();
        long started = DiagnosticLogger.start();
        DiagnosticLogger.event("native_text_start", new JSONObject()
            .put("role", role)
            .put("max_new_tokens", maxNewTokens)
            .put("end_with", endWith == null ? "" : endWith)
            .put("prompt_chars", prompt == null ? 0 : prompt.length())
            .put("tuning", tuningConfigJson == null ? "" : tuningConfigJson));
        try {
            String output = nativeTextJson(modelDir, prompt, role, tuningConfigJson, maxNewTokens, endWith);
            DiagnosticLogger.event("native_text_end", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("max_new_tokens", maxNewTokens)
                .put("end_with", endWith == null ? "" : endWith)
                .put("output_chars", output == null ? 0 : output.length())
                .put("output", DiagnosticLogger.excerpt(output)));
            return output;
        } catch (UnsatisfiedLinkError error) {
            DiagnosticLogger.event("native_text_error", new JSONObject()
                .put("role", role)
                .put("elapsed_ms", DiagnosticLogger.elapsed(started))
                .put("error", error.getMessage()));
            throw new IllegalStateException("端侧 Qwen 文本推理接口未实现。", error);
        }
    }

    @Override
    public String transcribe(String modelDir, String audioDataUrl) throws Exception {
        ensureAvailable();
        try {
            return nativeTranscribe(modelDir, audioDataUrl);
        } catch (UnsatisfiedLinkError error) {
            throw new IllegalStateException("端侧语音转文字接口未实现。当前离线 Qwen 文本模型需要先由系统 ASR 或其他本地 ASR 生成文本。", error);
        }
    }

    private void ensureAvailable() {
        if (!available) {
            throw new IllegalStateException("未加载 silvercare_mnn_runtime。请先集成 MNN native 推理库。");
        }
    }

    private static final class VisionInput {
        final float[] chwRgb;
        final int imageWidth;
        final int imageHeight;

        private VisionInput(float[] chwRgb, int imageWidth, int imageHeight) {
            this.chwRgb = chwRgb;
            this.imageWidth = imageWidth;
            this.imageHeight = imageHeight;
        }

        static VisionInput from(String imageDataUrl) {
            byte[] bytes = decodeImageBytes(imageDataUrl);
            Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
            if (bitmap == null) {
                throw new IllegalArgumentException("无法解码摄像头图像。");
            }

            int width = bitmap.getWidth();
            int height = bitmap.getHeight();
            Bitmap scaled = Bitmap.createScaledBitmap(bitmap, VISION_INPUT_SIZE, VISION_INPUT_SIZE, true);
            int[] pixels = new int[VISION_INPUT_SIZE * VISION_INPUT_SIZE];
            scaled.getPixels(pixels, 0, VISION_INPUT_SIZE, 0, 0, VISION_INPUT_SIZE, VISION_INPUT_SIZE);

            float[] chw = new float[3 * VISION_INPUT_SIZE * VISION_INPUT_SIZE];
            int plane = VISION_INPUT_SIZE * VISION_INPUT_SIZE;
            for (int index = 0; index < pixels.length; index += 1) {
                int pixel = pixels[index];
                chw[index] = (pixel >> 16) & 0xff;
                chw[plane + index] = (pixel >> 8) & 0xff;
                chw[(2 * plane) + index] = pixel & 0xff;
            }

            if (scaled != bitmap) scaled.recycle();
            bitmap.recycle();
            return new VisionInput(chw, width, height);
        }

        private static byte[] decodeImageBytes(String imageDataUrl) {
            String value = imageDataUrl == null ? "" : imageDataUrl.trim();
            int comma = value.indexOf(',');
            if (comma >= 0) value = value.substring(comma + 1);
            if (value.isEmpty()) {
                throw new IllegalArgumentException("摄像头图像为空。");
            }
            return Base64.decode(value, Base64.DEFAULT);
        }
    }

    private native String nativeVisionJson(
        String modelDir,
        String prompt,
        float[] chwRgb,
        int imageWidth,
        int imageHeight,
        String role
    );

    private native String nativeTextJson(
        String modelDir,
        String prompt,
        String role,
        String tuningConfigJson,
        int maxNewTokens,
        String endWith
    );

    private native String nativeTranscribe(String modelDir, String audioDataUrl);

    private native String nativeRuntimeKind();

    private native boolean nativeSupportsSme2();
}
