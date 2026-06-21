package com.silvercare.aiassistant

import com.silvercare.aiassistant.tts.TtsService
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

internal class MnnTtsRuntimeBridge : LocalTtsRuntimeBridge, Closeable {
    private val lock = Any()
    private var service: TtsService? = null
    private var initializedModelPath: String = ""
    private var initializedLanguage: String = ""
    private var lastError: String = ""

    override fun isAvailable(): Boolean {
        return try {
            Class.forName("com.silvercare.aiassistant.tts.TtsService")
            true
        } catch (throwable: Throwable) {
            lastError = readableThrowable(throwable)
            false
        }
    }

    override fun runtimeSummary(): String {
        return if (isAvailable()) {
            "mnn-tts-native-runtime-ready: mnn_tts + bert-vits2-MNN"
        } else {
            "MNN TTS Native Runtime 不可用${if (lastError.isBlank()) "" else "：$lastError"}"
        }
    }

    override fun synthesizeToWav(
        modelDir: File?,
        cacheDir: File?,
        text: String?,
        language: String?
    ): File {
        require(!text.isNullOrBlank()) { "朗读文本为空。" }
        if (modelDir == null || !modelDir.isDirectory) {
            throw IllegalStateException("本地 MNN TTS 模型目录不存在。")
        }
        if (!File(modelDir, "config.json").isFile) {
            throw IllegalStateException("本地 MNN TTS 模型缺少 config.json。")
        }
        if (!isAvailable()) {
            throw IllegalStateException(runtimeSummary())
        }

        val outputDir = cacheDir ?: modelDir
        if (!outputDir.isDirectory && !outputDir.mkdirs()) {
            throw IllegalStateException("无法创建本地 TTS 缓存目录：${outputDir.absolutePath}")
        }

        synchronized(lock) {
            val normalizedLanguage = normalizeLanguage(language)
            val modelPath = modelDir.absolutePath
            val ttsService = ensureService(modelPath, normalizedLanguage)
            val audio = ttsService.process(text.trim(), 0)
            if (audio.isEmpty()) {
                throw IllegalStateException("本地 MNN TTS 未生成有效音频。")
            }
            val sampleRate = readSampleRate(modelDir)
            val output = File(outputDir, "long-term-care-local-tts-${System.nanoTime()}.wav")
            writeWav(output, audio, sampleRate)
            if (!output.isFile || output.length() <= WAV_HEADER_BYTES) {
                throw IllegalStateException("本地 MNN TTS 未生成有效 WAV 音频。")
            }
            return output
        }
    }

    private fun ensureService(modelPath: String, language: String): TtsService {
        val existing = service
        if (
            existing != null &&
            initializedModelPath == modelPath &&
            initializedLanguage == language
        ) {
            return existing
        }

        close()
        val created = TtsService()
        try {
            created.setLanguage(language)
            val ready = runBlocking {
                created.init(modelPath) && created.waitForInitComplete()
            }
            if (!ready) {
                throw IllegalStateException("MNN TTS 初始化失败。")
            }
            service = created
            initializedModelPath = modelPath
            initializedLanguage = language
            return created
        } catch (throwable: Throwable) {
            runCatching { created.destroy() }
            lastError = readableThrowable(throwable)
            throw IllegalStateException("本地 MNN TTS 初始化失败：$lastError", throwable)
        }
    }

    override fun close() {
        synchronized(lock) {
            service?.let { runCatching { it.destroy() } }
            service = null
            initializedModelPath = ""
            initializedLanguage = ""
        }
    }

    private fun normalizeLanguage(language: String?): String {
        val lower = language?.trim()?.lowercase(Locale.US).orEmpty()
        return if (lower.startsWith("zh") || lower.contains("cn")) "zh" else "en"
    }

    private fun readSampleRate(modelDir: File): Int {
        return try {
            val value = JSONObject(File(modelDir, "config.json").readText()).optInt("sample_rate", 44100)
            if (value > 0) value else 44100
        } catch (_: Throwable) {
            44100
        }
    }

    private fun writeWav(output: File, samples: ShortArray, sampleRate: Int) {
        val dataBytes = samples.size * 2
        FileOutputStream(output).use { stream ->
            stream.write(byteArrayOf('R'.code.toByte(), 'I'.code.toByte(), 'F'.code.toByte(), 'F'.code.toByte()))
            writeIntLe(stream, 36 + dataBytes)
            stream.write(byteArrayOf('W'.code.toByte(), 'A'.code.toByte(), 'V'.code.toByte(), 'E'.code.toByte()))
            stream.write(byteArrayOf('f'.code.toByte(), 'm'.code.toByte(), 't'.code.toByte(), ' '.code.toByte()))
            writeIntLe(stream, 16)
            writeShortLe(stream, 1)
            writeShortLe(stream, 1)
            writeIntLe(stream, sampleRate)
            writeIntLe(stream, sampleRate * 2)
            writeShortLe(stream, 2)
            writeShortLe(stream, 16)
            stream.write(byteArrayOf('d'.code.toByte(), 'a'.code.toByte(), 't'.code.toByte(), 'a'.code.toByte()))
            writeIntLe(stream, dataBytes)
            samples.forEach { writeShortLe(stream, it.toInt()) }
        }
    }

    private fun writeIntLe(stream: FileOutputStream, value: Int) {
        stream.write(value and 0xff)
        stream.write(value shr 8 and 0xff)
        stream.write(value shr 16 and 0xff)
        stream.write(value shr 24 and 0xff)
    }

    private fun writeShortLe(stream: FileOutputStream, value: Int) {
        stream.write(value and 0xff)
        stream.write(value shr 8 and 0xff)
    }

    private fun readableThrowable(throwable: Throwable?): String {
        if (throwable == null) return ""
        val message = throwable.message
        return if (message.isNullOrBlank()) throwable.toString() else message
    }

    private companion object {
        private const val WAV_HEADER_BYTES = 44L
    }
}
