#include "tts_service.hpp"
#include <memory>
#include <jni.h>
#include <android/log.h>

#define LTC_TTS_LOG(...) __android_log_print(ANDROID_LOG_INFO, "MnnTtsNative", __VA_ARGS__)

namespace TaoAvatar {

TTSService::~TTSService() {
    tts_ = nullptr;
}

bool TTSService::LoadTtsResources(const char *resPath, const char* modelName, const char* cacheDir) {
    MNNITTSLogger::GetInstance().SetLogLevel(PDEBUG);
    MH_DEBUG("TTSService::LoadTtsResources resPath: %s", resPath);
    if (!tts_) {
        LTC_TTS_LOG("LoadTtsResources start path=%s", resPath);
        tts_ = std::make_shared<MNNTTSSDK>(
                std::string(resPath));
        LTC_TTS_LOG("LoadTtsResources finished");
    }
    if (!tts_) {
        MH_ERROR("Failed to create TTSService.");
        return false;
    }
    return true;
}

void WriteToFileForDebug(const std::vector<int16_t> &audio, const std::string &file_name) {
    std::ofstream outFile(file_name, std::ios::binary);
    if (outFile.is_open()) {
        size_t size = audio.size();
        outFile.write(reinterpret_cast<char*>(&size), sizeof(size));
        if (!audio.empty()) {
            outFile.write(reinterpret_cast<const char*>(audio.data()),
                          audio.size() * sizeof(int16_t));
        }
        outFile.close();
    }
}


void TTSService::SetIndex(int index) {
    current_index_ = index;
}

void TTSService::SetSpeakerId(const std::string &speaker_id) {
    if (tts_) {
        tts_->SetSpeakerId(speaker_id);
    }
}

std::vector<int16_t> TTSService::Process(const std::string &text, int id) {
    if (tts_ != nullptr && (!text.empty())) {
        LTC_TTS_LOG("Process start chars=%zu", text.size());
        auto audio = tts_->Process(text);
        LTC_TTS_LOG("Process finished samples=%zu", std::get<1>(audio).size());
#if DEBUG_SAVE_TTS_DATA
        WriteToFileForDebug( std::get<1>(audio),
                "/data/data/com.silvercare.aiassistant/tts_" + std::to_string(id) + ".pcm");
#endif
        return std::get<1>(audio);
    } else {
        MH_ERROR("Failed to process text to speech.");
    }
    return {};
}

TTSService::TTSService(std::string language):language_(std::move(language)) {

}

}
