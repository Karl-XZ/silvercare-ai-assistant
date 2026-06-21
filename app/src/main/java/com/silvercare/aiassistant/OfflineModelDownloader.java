package com.silvercare.aiassistant;

import android.content.Context;
import android.os.StatFs;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

final class OfflineModelDownloader {
    static final String AUTO_MODEL_DIR_NAME = "multimodal_care_models";
    static final String QWEN4B_DIR = "Qwen3-4B-Instruct-2507-MNN";
    static final String BUNDLED_DETECTOR_ASSET = "offline/damo-yolo.mnn";
    static final String BUNDLED_DETECTOR_FILE = "damo-yolo.mnn";
    static final long BUNDLED_DETECTOR_BYTES = 34_058_720L;

    private static final String QWEN4B_HF_BASE =
        "https://huggingface.co/taobao-mnn/Qwen3-4B-Instruct-2507-MNN/resolve/main/";
    private static final long MIN_FREE_SPACE_BUFFER = 512L * 1024L * 1024L;
    private static final int CONNECT_TIMEOUT_MS = 30_000;
    private static final int READ_TIMEOUT_MS = 60_000;
    private static final int BUFFER_SIZE = 1024 * 256;
    private static final long PROGRESS_STEP_BYTES = 8L * 1024L * 1024L;

    static final DownloadFile[] QWEN4B_FILES = new DownloadFile[] {
        file(QWEN4B_DIR, QWEN4B_HF_BASE, "config.json", 403L),
        file(QWEN4B_DIR, QWEN4B_HF_BASE, "llm.mnn", 592_336L),
        file(QWEN4B_DIR, QWEN4B_HF_BASE, "llm.mnn.json", 1_243_600L),
        file(QWEN4B_DIR, QWEN4B_HF_BASE, "llm.mnn.weight", 2_709_972_658L),
        file(QWEN4B_DIR, QWEN4B_HF_BASE, "llm_config.json", 4_803L),
        file(QWEN4B_DIR, QWEN4B_HF_BASE, "tokenizer.txt", 3_193_555L)
    };

    interface ProgressListener {
        void onProgress(String message, long downloadedBytes, long totalBytes);
    }

    static final class DownloadResult {
        final File modelDir;
        final long totalBytes;

        DownloadResult(File modelDir, long totalBytes) {
            this.modelDir = modelDir;
            this.totalBytes = totalBytes;
        }
    }

    static final class DownloadFile {
        final String relativePath;
        final long expectedBytes;
        final String[] urls;

        DownloadFile(String relativePath, long expectedBytes, String[] urls) {
            this.relativePath = relativePath;
            this.expectedBytes = expectedBytes;
            this.urls = urls;
        }
    }

    private static DownloadFile file(String dir, String baseUrl, String name, long expectedBytes) {
        String relativePath = dir + "/" + name;
        return new DownloadFile(relativePath, expectedBytes, new String[] { baseUrl + name });
    }

    static File automaticModelDir(Context context) {
        File external = context.getExternalFilesDir(null);
        File base = external == null ? context.getFilesDir() : external;
        return new File(base, AUTO_MODEL_DIR_NAME);
    }

    DownloadResult ensureQwen4BBundle(Context context, ProgressListener listener) throws Exception {
        File root = automaticModelDir(context);
        if (!root.isDirectory() && !root.mkdirs()) {
            throw new IllegalStateException("无法创建离线模型目录：" + root.getAbsolutePath());
        }

        long total = expectedTotalBytes();
        ensureFreeSpace(root, missingBytes(root), total);

        Progress progress = new Progress(total);
        copyBundledDetector(context, root, progress, listener);
        for (DownloadFile item : QWEN4B_FILES) {
            downloadFile(root, item, progress, listener);
        }

        notify(listener, "离线模型下载完成", total, total);
        return new DownloadResult(root, total);
    }

    static long expectedTotalBytes() {
        long total = BUNDLED_DETECTOR_BYTES;
        for (DownloadFile item : QWEN4B_FILES) total += item.expectedBytes;
        return total;
    }

    private static long missingBytes(File root) {
        long missing = isComplete(new File(root, BUNDLED_DETECTOR_FILE), BUNDLED_DETECTOR_BYTES)
            ? 0L
            : BUNDLED_DETECTOR_BYTES;
        for (DownloadFile item : QWEN4B_FILES) {
            if (!isComplete(new File(root, item.relativePath), item.expectedBytes)) {
                missing += item.expectedBytes;
            }
        }
        return missing;
    }

    private static void ensureFreeSpace(File root, long missingBytes, long totalBytes) {
        if (missingBytes <= 0L) return;
        StatFs stat = new StatFs(root.getAbsolutePath());
        long available = stat.getAvailableBytes();
        long required = missingBytes + MIN_FREE_SPACE_BUFFER;
        if (available < required) {
            throw new IllegalStateException(
                "存储空间不足。离线模型总大小约 " + humanBytes(totalBytes)
                    + "，当前还需要 " + humanBytes(missingBytes)
                    + "，请至少保留 " + humanBytes(required) + " 可用空间。"
            );
        }
    }

    private static void copyBundledDetector(
        Context context,
        File root,
        Progress progress,
        ProgressListener listener
    ) throws Exception {
        File target = new File(root, BUNDLED_DETECTOR_FILE);
        if (isComplete(target, BUNDLED_DETECTOR_BYTES)) {
            progress.add(BUNDLED_DETECTOR_BYTES);
            notify(listener, "DAMO-YOLO 检测模型已就绪", progress.done, progress.total);
            return;
        }

        File part = new File(root, BUNDLED_DETECTOR_FILE + ".part");
        notify(listener, "正在准备 DAMO-YOLO 检测模型", progress.done, progress.total);
        try (
            InputStream input = new BufferedInputStream(context.getAssets().open(BUNDLED_DETECTOR_ASSET));
            FileOutputStream file = new FileOutputStream(part, false);
            BufferedOutputStream output = new BufferedOutputStream(file, BUFFER_SIZE)
        ) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int read;
            long copied = 0L;
            long lastProgress = 0L;
            while ((read = input.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
                copied += read;
                progress.add(read);
                if (copied - lastProgress >= PROGRESS_STEP_BYTES) {
                    lastProgress = copied;
                    notify(listener, "正在复制 DAMO-YOLO 检测模型", progress.done, progress.total);
                }
            }
        }

        replaceFile(part, target);
        if (!isComplete(target, BUNDLED_DETECTOR_BYTES)) {
            throw new IllegalStateException("DAMO-YOLO 检测模型复制不完整。");
        }
        notify(listener, "DAMO-YOLO 检测模型已就绪", progress.done, progress.total);
    }

    private static void downloadFile(
        File root,
        DownloadFile item,
        Progress progress,
        ProgressListener listener
    ) throws Exception {
        File target = new File(root, item.relativePath);
        if (isComplete(target, item.expectedBytes)) {
            progress.add(item.expectedBytes);
            notify(listener, "已存在：" + item.relativePath, progress.done, progress.total);
            return;
        }
        File parent = target.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IllegalStateException("无法创建目录：" + parent.getAbsolutePath());
        }

        Exception lastError = null;
        for (String url : item.urls) {
            try {
                streamUrl(url, target, item, progress, listener);
                return;
            } catch (Exception error) {
                lastError = error;
            }
        }
        throw lastError == null ? new IllegalStateException("下载失败：" + item.relativePath) : lastError;
    }

    private static void streamUrl(
        String url,
        File target,
        DownloadFile item,
        Progress progress,
        ProgressListener listener
    ) throws Exception {
        File part = new File(target.getAbsolutePath() + ".part");
        if (target.isFile() && target.length() > 0L) target.delete();
        if (part.isFile() && part.length() > item.expectedBytes) part.delete();

        long existing = part.isFile() ? part.length() : 0L;
        long countedExisting = Math.min(existing, item.expectedBytes);
        if (countedExisting > 0L) {
            progress.add(countedExisting);
        }

        notify(listener, "正在下载：" + item.relativePath, progress.done, progress.total);
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setInstanceFollowRedirects(true);
        connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
        connection.setReadTimeout(READ_TIMEOUT_MS);
        connection.setRequestProperty("Accept-Encoding", "identity");
        connection.setRequestProperty("User-Agent", "MultimodalCareAndroid/1.0");
        if (existing > 0L) {
            connection.setRequestProperty("Range", "bytes=" + existing + "-");
        }

        int code = connection.getResponseCode();
        boolean append = existing > 0L && code == HttpURLConnection.HTTP_PARTIAL;
        if (existing > 0L && code == HttpURLConnection.HTTP_OK) {
            progress.subtract(countedExisting);
            existing = 0L;
            append = false;
        }
        if (code == 416 && isComplete(part, item.expectedBytes)) {
            replaceFile(part, target);
            notify(listener, "下载完成：" + item.relativePath, progress.done, progress.total);
            return;
        }
        if (code < 200 || code >= 300) {
            throw new IllegalStateException("HTTP " + code + "：" + item.relativePath);
        }

        try (
            InputStream input = new BufferedInputStream(connection.getInputStream());
            FileOutputStream file = new FileOutputStream(part, append);
            BufferedOutputStream output = new BufferedOutputStream(file, BUFFER_SIZE)
        ) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int read;
            long sinceProgress = 0L;
            while ((read = input.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
                progress.add(read);
                sinceProgress += read;
                if (sinceProgress >= PROGRESS_STEP_BYTES) {
                    sinceProgress = 0L;
                    notify(listener, "正在下载：" + item.relativePath, progress.done, progress.total);
                }
            }
        } finally {
            connection.disconnect();
        }

        if (!isComplete(part, item.expectedBytes)) {
            throw new IllegalStateException(
                "下载不完整：" + item.relativePath + "，已下载 "
                    + humanBytes(part.length()) + " / " + humanBytes(item.expectedBytes)
            );
        }
        replaceFile(part, target);
        notify(listener, "下载完成：" + item.relativePath, progress.done, progress.total);
    }

    private static boolean isComplete(File file, long expectedBytes) {
        return file.isFile() && file.length() == expectedBytes;
    }

    private static void replaceFile(File source, File target) {
        if (target.exists() && !target.delete()) {
            throw new IllegalStateException("无法替换文件：" + target.getAbsolutePath());
        }
        if (!source.renameTo(target)) {
            throw new IllegalStateException("无法写入文件：" + target.getAbsolutePath());
        }
    }

    private static void notify(ProgressListener listener, String message, long done, long total) {
        if (listener != null) listener.onProgress(message, done, total);
    }

    private static String humanBytes(long bytes) {
        double value = bytes;
        String[] units = new String[] { "B", "KB", "MB", "GB" };
        int unit = 0;
        while (value >= 1024.0 && unit < units.length - 1) {
            value /= 1024.0;
            unit += 1;
        }
        return String.format(java.util.Locale.US, "%.1f%s", value, units[unit]);
    }

    private static final class Progress {
        final long total;
        long done;

        Progress(long total) {
            this.total = total;
        }

        void add(long bytes) {
            done = Math.min(total, done + Math.max(0L, bytes));
        }

        void subtract(long bytes) {
            done = Math.max(0L, done - Math.max(0L, bytes));
        }
    }
}
