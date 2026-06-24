#include "../SilverCareMNNTTSRuntimeABI.h"

#include "mnn_tts_sdk.hpp"

#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <unordered_map>

namespace {

std::mutex gSdkMutex;
std::unordered_map<std::string, std::shared_ptr<MNNTTSSDK>> gSdkByModelDir;

std::string stringOrEmpty(const char *value) {
    return value == nullptr ? "" : std::string(value);
}

std::string trimTrailingSlash(std::string path) {
    while (!path.empty() && (path.back() == '/' || path.back() == '\\')) {
        path.pop_back();
    }
    return path;
}

std::string joinPath(const std::string &root, const std::string &child) {
    if (root.empty()) return child;
    if (root.back() == '/' || root.back() == '\\') return root + child;
    return root + "/" + child;
}

bool fileExists(const std::string &path) {
    std::ifstream input(path, std::ios::binary);
    return input.good();
}

bool ensureDirectoryWritable(const std::string &cacheDir) {
    if (cacheDir.empty()) return false;
    std::string probe = joinPath(cacheDir, ".silvercare_mnn_tts_probe");
    {
        std::ofstream out(probe, std::ios::binary);
        if (!out.good()) return false;
        out << "ok";
    }
    std::remove(probe.c_str());
    return true;
}

std::string escapeForJsonString(const std::string &value) {
    std::ostringstream out;
    for (char ch : value) {
        switch (ch) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\b': out << "\\b"; break;
        case '\f': out << "\\f"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (static_cast<unsigned char>(ch) < 0x20) {
                out << "\\u";
                const char *hex = "0123456789abcdef";
                unsigned char valueByte = static_cast<unsigned char>(ch);
                out << "00" << hex[(valueByte >> 4) & 0x0f] << hex[valueByte & 0x0f];
            } else {
                out << ch;
            }
        }
    }
    return out.str();
}

std::string synthParamsJson(const std::string &language) {
    if (language.empty()) return "{}";
    return std::string("{\"language\":\"") + escapeForJsonString(language) + "\"}";
}

std::shared_ptr<MNNTTSSDK> sdkForModelDir(const std::string &modelDir, const std::string &language) {
    std::lock_guard<std::mutex> lock(gSdkMutex);
    const std::string key = modelDir + "|" + language;
    auto existing = gSdkByModelDir.find(key);
    if (existing != gSdkByModelDir.end()) {
        return existing->second;
    }
    auto sdk = std::make_shared<MNNTTSSDK>(modelDir, synthParamsJson(language));
    gSdkByModelDir[key] = sdk;
    return sdk;
}

char *copyCString(const std::string &value) {
    char *buffer = static_cast<char *>(std::malloc(value.size() + 1));
    if (buffer == nullptr) return nullptr;
    std::memcpy(buffer, value.c_str(), value.size() + 1);
    return buffer;
}

std::string makeOutputPath(const std::string &cacheDir) {
    static std::mutex sequenceMutex;
    static unsigned long sequence = 0;
    unsigned long localSequence = 0;
    {
        std::lock_guard<std::mutex> lock(sequenceMutex);
        localSequence = ++sequence;
    }
    const long long stamp = static_cast<long long>(std::time(nullptr));
    return joinPath(cacheDir, "silvercare-mnn-tts-" + std::to_string(stamp) + "-" + std::to_string(localSequence) + ".wav");
}

} // namespace

extern "C" const char *silvercare_mnn_tts_runtime_kind(void) {
    return "mnn-tts-ios-arm64+bert-vits2";
}

extern "C" int32_t silvercare_mnn_tts_voice_quality_passed(void) {
    return 0;
}

extern "C" char *silvercare_mnn_tts_synthesize_wav(
    const char *model_dir,
    const char *cache_dir,
    const char *text,
    const char *language
) {
    try {
        const std::string modelDir = trimTrailingSlash(stringOrEmpty(model_dir));
        const std::string cacheDir = trimTrailingSlash(stringOrEmpty(cache_dir));
        const std::string utterance = stringOrEmpty(text);
        const std::string requestedLanguage = stringOrEmpty(language);
        if (modelDir.empty() || cacheDir.empty() || utterance.empty()) return nullptr;
        if (!fileExists(joinPath(modelDir, "config.json"))) return nullptr;
        if (!ensureDirectoryWritable(cacheDir)) return nullptr;

        auto sdk = sdkForModelDir(modelDir, requestedLanguage);
        auto result = sdk->Process(utterance);
        int sampleRate = std::get<0>(result);
        Audio audio = std::get<1>(result);
        if (sampleRate <= 0 || audio.empty()) return nullptr;

        const std::string outputPath = makeOutputPath(cacheDir);
        sdk->WriteAudioToFile(audio, outputPath);
        if (!fileExists(outputPath)) return nullptr;
        return copyCString(outputPath);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void silvercare_mnn_tts_free_string(char *value) {
    std::free(value);
}
