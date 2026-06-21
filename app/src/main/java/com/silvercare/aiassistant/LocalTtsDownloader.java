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
import java.util.Locale;

final class LocalTtsDownloader {
    static final String MODEL_NAME = "bert-vits2-MNN";
    private static final String MNN_TTS_HF_BASE =
        "https://huggingface.co/taobao-mnn/bert-vits2-MNN/resolve/main/";
    private static final long MIN_FREE_SPACE_BUFFER = 512L * 1024L * 1024L;
    private static final int CONNECT_TIMEOUT_MS = 30_000;
    private static final int READ_TIMEOUT_MS = 60_000;
    private static final int BUFFER_SIZE = 1024 * 256;
    private static final long PROGRESS_STEP_BYTES = 8L * 1024L * 1024L;

    static final DownloadFile[] MNN_TTS_FILES = new DownloadFile[] {
        file("config.json", 172L),
        file("tokenizer.txt", 156_256L),
        file("tts_generator_w_bert_chenxi_0310_int8.mnn", 50_457_744L),
        file("common/mnn_models/chinese_bert.mnn", 595_296L),
        file("common/mnn_models/chinese_bert.mnn.weight", 367_494_936L),
        file("common/mnn_models/english_bert.mnn", 416_016L),
        file("common/mnn_models/english_bert.mnn.weight", 929_559_392L),
        file("common/text_processing_jsons/char_state.bin", 949_364L),
        file("common/text_processing_jsons/cn_bert_token.bin", 341_956L),
        file("common/text_processing_jsons/default_tone_words.json", 6_249L),
        file("common/text_processing_jsons/en_bert_token.json", 3_011_214L),
        file("common/text_processing_jsons/eng_dict.bin", 13_716_655L),
        file("common/text_processing_jsons/hotwords_cn.bin", 5_081L),
        file("common/text_processing_jsons/hotwords_cn.json", 14_232L),
        file("common/text_processing_jsons/phrases_dict.bin", 2_834_832L),
        file("common/text_processing_jsons/pinyin_dict.bin", 1_117_037L),
        file("common/text_processing_jsons/pinyin_to_symbol_map.bin", 5_809L),
        file("common/text_processing_jsons/prob_emit.bin", 1_701_802L),
        file("common/text_processing_jsons/prob_start.bin", 5_292L),
        file("common/text_processing_jsons/prob_trans.bin", 112_039L),
        file("common/text_processing_jsons/tokenizer.txt", 156_256L),
        file("common/text_processing_jsons/word_freq.bin", 10_251_325L),
        file("common/text_processing_jsons/word_tag.bin", 9_111_009L)
    };

    interface ProgressListener {
        void onProgress(String message, long downloadedBytes, long totalBytes);
    }

    static final class DownloadResult {
        final File modelRoot;
        final File modelDir;
        final long totalBytes;

        DownloadResult(File modelRoot, File modelDir, long totalBytes) {
            this.modelRoot = modelRoot;
            this.modelDir = modelDir;
            this.totalBytes = totalBytes;
        }
    }

    static final class DownloadFile {
        final String relativePath;
        final long expectedBytes;
        final String url;

        DownloadFile(String relativePath, long expectedBytes, String url) {
            this.relativePath = relativePath;
            this.expectedBytes = expectedBytes;
            this.url = url;
        }
    }

    private static DownloadFile file(String name, long expectedBytes) {
        return new DownloadFile(name, expectedBytes, MNN_TTS_HF_BASE + name);
    }

    DownloadResult ensureMnnTtsBundle(Context context, ProgressListener listener) throws Exception {
        File root = LocalTtsModelManager.ttsRoot(context);
        if (!root.isDirectory() && !root.mkdirs()) {
            throw new IllegalStateException("无法创建本地 TTS 模型目录：" + root.getAbsolutePath());
        }
        File modelDir = new File(root, LocalTtsModelManager.MNN_TTS_DIR);
        if (!modelDir.isDirectory() && !modelDir.mkdirs()) {
            throw new IllegalStateException("无法创建本地 MNN TTS 模型目录：" + modelDir.getAbsolutePath());
        }

        long total = expectedTotalBytes();
        long missing = missingBytes(modelDir);
        if (missing <= 0L) {
            notify(listener, "本地 MNN TTS 模型已存在", total, total);
            return new DownloadResult(root, modelDir, total);
        }

        ensureFreeSpace(root, missing, total);
        Progress progress = new Progress(total);
        for (DownloadFile item : MNN_TTS_FILES) {
            downloadFile(modelDir, item, progress, listener);
        }

        LocalTtsModelStatus status = new LocalTtsModelManager().inspect(root, true, "download-check");
        if (!status.modelReady) {
            throw new IllegalStateException(status.shortText());
        }
        notify(listener, "本地 MNN TTS 模型下载完成", total, total);
        return new DownloadResult(root, modelDir, total);
    }

    static long expectedTotalBytes() {
        long total = 0L;
        for (DownloadFile item : MNN_TTS_FILES) total += item.expectedBytes;
        return total;
    }

    private static long missingBytes(File modelDir) {
        long missing = 0L;
        for (DownloadFile item : MNN_TTS_FILES) {
            if (!isComplete(new File(modelDir, item.relativePath), item.expectedBytes)) {
                missing += item.expectedBytes;
            }
        }
        return missing;
    }

    private static void ensureFreeSpace(File root, long missingBytes, long totalBytes) {
        StatFs stat = new StatFs(root.getAbsolutePath());
        long available = stat.getAvailableBytes();
        long required = missingBytes + MIN_FREE_SPACE_BUFFER;
        if (available < required) {
            throw new IllegalStateException(
                "存储空间不足。本地 TTS 模型总大小约 " + humanBytes(totalBytes)
                    + "，当前还需要 " + humanBytes(missingBytes)
                    + "，请至少保留 " + humanBytes(required) + " 可用空间。"
            );
        }
    }

    private static void downloadFile(
        File modelDir,
        DownloadFile item,
        Progress progress,
        ProgressListener listener
    ) throws Exception {
        File target = new File(modelDir, item.relativePath);
        File parent = target.getParentFile();
        if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
            throw new IllegalStateException("无法创建目录：" + parent.getAbsolutePath());
        }
        if (isComplete(target, item.expectedBytes)) {
            progress.add(item.expectedBytes);
            notify(listener, "已存在：" + item.relativePath, progress.done, progress.total);
            return;
        }

        File part = new File(target.getAbsolutePath() + ".part");
        if (target.isFile() && target.length() > 0L) target.delete();
        if (part.isFile() && part.length() > item.expectedBytes) part.delete();

        long existing = part.isFile() ? part.length() : 0L;
        long countedExisting = Math.min(existing, item.expectedBytes);
        if (countedExisting > 0L) {
            progress.add(countedExisting);
        }

        notify(listener, "正在下载：" + item.relativePath, progress.done, progress.total);
        HttpURLConnection connection = (HttpURLConnection) new URL(item.url).openConnection();
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

    static String humanBytes(long bytes) {
        double value = bytes;
        String[] units = new String[] { "B", "KB", "MB", "GB" };
        int unit = 0;
        while (value >= 1024.0 && unit < units.length - 1) {
            value /= 1024.0;
            unit += 1;
        }
        return String.format(Locale.US, "%.1f%s", value, units[unit]);
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
