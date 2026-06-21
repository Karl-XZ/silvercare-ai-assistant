package com.silvercare.aiassistant;

import android.content.Context;
import android.os.StatFs;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

final class LocalAsrDownloader {
    static final long VOSK_CN_ZIP_BYTES = 43_898_754L;
    static final String VOSK_CN_ZIP_URL =
        "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip";

    private static final long MIN_FREE_SPACE_BUFFER = 256L * 1024L * 1024L;
    private static final int CONNECT_TIMEOUT_MS = 30_000;
    private static final int READ_TIMEOUT_MS = 60_000;
    private static final int BUFFER_SIZE = 1024 * 256;
    private static final long PROGRESS_STEP_BYTES = 2L * 1024L * 1024L;

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

    DownloadResult ensureChineseModel(Context context, ProgressListener listener) throws Exception {
        File root = LocalAsrModelManager.asrRoot(context);
        if (!root.isDirectory() && !root.mkdirs()) {
            throw new IllegalStateException("无法创建本地 ASR 模型目录：" + root.getAbsolutePath());
        }

        LocalAsrModelManager manager = new LocalAsrModelManager();
        LocalAsrModelStatus status = manager.inspect(root);
        if (status.ready) {
            notify(listener, "本地 ASR 模型已存在", VOSK_CN_ZIP_BYTES, VOSK_CN_ZIP_BYTES);
            return new DownloadResult(root, status.modelDir, VOSK_CN_ZIP_BYTES);
        }

        ensureFreeSpace(root, VOSK_CN_ZIP_BYTES);

        File zip = new File(root, LocalAsrModelManager.VOSK_CN_MODEL_DIR + ".zip");
        if (!isComplete(zip, VOSK_CN_ZIP_BYTES)) {
            downloadZip(zip, listener);
        } else {
            notify(listener, "本地 ASR 压缩包已存在", VOSK_CN_ZIP_BYTES, VOSK_CN_ZIP_BYTES);
        }

        notify(listener, "正在解压本地 ASR 模型", VOSK_CN_ZIP_BYTES, VOSK_CN_ZIP_BYTES);
        extractModelZip(zip, root);

        status = manager.inspect(root);
        if (!status.ready) {
            throw new IllegalStateException(status.shortText());
        }
        notify(listener, "本地 ASR 模型下载完成", VOSK_CN_ZIP_BYTES, VOSK_CN_ZIP_BYTES);
        return new DownloadResult(root, status.modelDir, VOSK_CN_ZIP_BYTES);
    }

    static long expectedTotalBytes() {
        return VOSK_CN_ZIP_BYTES;
    }

    private static void ensureFreeSpace(File root, long missingBytes) {
        StatFs stat = new StatFs(root.getAbsolutePath());
        long available = stat.getAvailableBytes();
        long required = missingBytes + MIN_FREE_SPACE_BUFFER;
        if (available < required) {
            throw new IllegalStateException(
                "存储空间不足。本地 ASR 模型下载约 " + humanBytes(missingBytes)
                    + "，请至少保留 " + humanBytes(required) + " 可用空间。"
            );
        }
    }

    private static void downloadZip(File target, ProgressListener listener) throws Exception {
        File part = new File(target.getAbsolutePath() + ".part");
        if (target.isFile() && target.length() > 0L) target.delete();
        if (part.isFile() && part.length() > VOSK_CN_ZIP_BYTES) part.delete();

        long existing = part.isFile() ? part.length() : 0L;
        long countedExisting = Math.min(existing, VOSK_CN_ZIP_BYTES);
        notify(listener, "正在下载本地 ASR 模型", countedExisting, VOSK_CN_ZIP_BYTES);

        HttpURLConnection connection = (HttpURLConnection) new URL(VOSK_CN_ZIP_URL).openConnection();
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
            existing = 0L;
            countedExisting = 0L;
            append = false;
        }
        if (code == 416 && isComplete(part, VOSK_CN_ZIP_BYTES)) {
            replaceFile(part, target);
            return;
        }
        if (code < 200 || code >= 300) {
            throw new IllegalStateException("本地 ASR 模型下载失败：HTTP " + code);
        }

        long done = countedExisting;
        long sinceProgress = 0L;
        try (
            InputStream input = new BufferedInputStream(connection.getInputStream());
            FileOutputStream file = new FileOutputStream(part, append);
            BufferedOutputStream output = new BufferedOutputStream(file, BUFFER_SIZE)
        ) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
                done = Math.min(VOSK_CN_ZIP_BYTES, done + read);
                sinceProgress += read;
                if (sinceProgress >= PROGRESS_STEP_BYTES) {
                    sinceProgress = 0L;
                    notify(listener, "正在下载本地 ASR 模型", done, VOSK_CN_ZIP_BYTES);
                }
            }
        } finally {
            connection.disconnect();
        }

        if (!isComplete(part, VOSK_CN_ZIP_BYTES)) {
            throw new IllegalStateException(
                "本地 ASR 模型下载不完整，已下载 "
                    + humanBytes(part.length()) + " / " + humanBytes(VOSK_CN_ZIP_BYTES)
            );
        }
        replaceFile(part, target);
        notify(listener, "本地 ASR 模型下载完成", VOSK_CN_ZIP_BYTES, VOSK_CN_ZIP_BYTES);
    }

    private static void extractModelZip(File zip, File root) throws Exception {
        File modelDir = new File(root, LocalAsrModelManager.VOSK_CN_MODEL_DIR);
        File tempDir = new File(root, LocalAsrModelManager.VOSK_CN_MODEL_DIR + ".tmp");
        safeDeleteRecursively(tempDir, root);
        if (!tempDir.mkdirs()) {
            throw new IllegalStateException("无法创建本地 ASR 解压目录：" + tempDir.getAbsolutePath());
        }

        String prefix = LocalAsrModelManager.VOSK_CN_MODEL_DIR + "/";
        byte[] buffer = new byte[BUFFER_SIZE];
        try (
            ZipInputStream input = new ZipInputStream(new BufferedInputStream(new FileInputStream(zip), BUFFER_SIZE))
        ) {
            ZipEntry entry;
            while ((entry = input.getNextEntry()) != null) {
                String name = entry.getName().replace('\\', '/');
                if (!name.startsWith(prefix)) continue;
                String relative = name.substring(prefix.length());
                if (relative.isEmpty()) continue;

                File out = safeChild(tempDir, relative);
                if (entry.isDirectory()) {
                    if (!out.isDirectory() && !out.mkdirs()) {
                        throw new IllegalStateException("无法创建目录：" + out.getAbsolutePath());
                    }
                    continue;
                }

                File parent = out.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new IllegalStateException("无法创建目录：" + parent.getAbsolutePath());
                }
                try (BufferedOutputStream output = new BufferedOutputStream(new FileOutputStream(out), BUFFER_SIZE)) {
                    int read;
                    while ((read = input.read(buffer)) >= 0) {
                        output.write(buffer, 0, read);
                    }
                }
            }
        }

        safeDeleteRecursively(modelDir, root);
        if (!tempDir.renameTo(modelDir)) {
            throw new IllegalStateException("无法写入本地 ASR 模型：" + modelDir.getAbsolutePath());
        }
    }

    private static File safeChild(File root, String relativePath) throws Exception {
        File target = new File(root, relativePath);
        String rootPath = root.getCanonicalPath() + File.separator;
        String targetPath = target.getCanonicalPath();
        if (!targetPath.startsWith(rootPath)) {
            throw new IllegalStateException("ASR 模型压缩包路径不安全：" + relativePath);
        }
        return target;
    }

    private static void safeDeleteRecursively(File target, File allowedRoot) throws Exception {
        if (target == null || !target.exists()) return;
        String allowedPath = allowedRoot.getCanonicalPath() + File.separator;
        String targetPath = target.getCanonicalPath();
        if (!targetPath.startsWith(allowedPath)) {
            throw new IllegalStateException("拒绝删除模型目录外文件：" + targetPath);
        }
        deleteRecursively(target);
    }

    private static void deleteRecursively(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteRecursively(child);
        }
        if (!file.delete() && file.exists()) {
            throw new IllegalStateException("无法删除旧文件：" + file.getAbsolutePath());
        }
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
}
