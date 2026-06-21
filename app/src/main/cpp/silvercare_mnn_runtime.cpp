#include <jni.h>

#include <MNN/Interpreter.hpp>
#include <MNN/MNNForwardType.h>
#include <MNN/Tensor.hpp>
#include <llm/llm.hpp>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#if defined(__ANDROID__) && defined(__aarch64__)
#include <sys/auxv.h>
#if __has_include(<asm/hwcap.h>)
#include <asm/hwcap.h>
#endif
#endif

namespace {

constexpr int kInputSize = 640;
constexpr float kScoreThreshold = 0.25f;
constexpr float kNmsThreshold = 0.70f;
constexpr int kMaxDetections = 30;

const char* kClassNames[] = {
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
    "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
    "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
    "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
    "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
    "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
    "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
    "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
    "toothbrush"
};

const std::vector<std::string> kTextConfigCandidates4B = {
    "Qwen3-4B-Instruct-2507-MNN/config.json",
    "qwen3-4b-instruct-2507-mnn/config.json",
    "qwen-text-4b/config.json",
    "text-4b/config.json"
};

const std::vector<std::string> kTextConfigCandidates15B = {
    "Qwen2.5-1.5B-Instruct-MNN/config.json",
    "qwen2.5-1.5b-instruct-mnn/config.json",
    "qwen2_5-1_5b-instruct-mnn/config.json",
    "qwen-text-1.5b/config.json",
    "text-1.5b/config.json"
};

const std::vector<std::string> kYoloModelCandidates = {
    "damo-yolo.mnn",
    "damo_yolo.mnn",
    "DAMO-YOLO.mnn",
    "yolo.mnn",
    "detector/damo-yolo.mnn",
    "detector/damo_yolo.mnn"
};

struct Detection {
    float x1;
    float y1;
    float x2;
    float y2;
    float score;
    int classId;
};

struct LlmDeleter {
    void operator()(MNN::Transformer::Llm* llm) const {
        if (llm != nullptr) {
            MNN::Transformer::Llm::destroy(llm);
        }
    }
};

std::mutex gLlmMutex;
std::string gLlmConfigPath;
std::string gLlmTuningConfigJson;
std::unique_ptr<MNN::Transformer::Llm, LlmDeleter> gLlm;

std::string toString(JNIEnv* env, jstring value) {
    if (value == nullptr) return "";
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) return "";
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

void throwIllegalState(JNIEnv* env, const std::string& message) {
    jclass cls = env->FindClass("java/lang/IllegalStateException");
    if (cls != nullptr) {
        env->ThrowNew(cls, message.c_str());
    }
}

std::string trimModelDir(const std::string& modelDir) {
    std::string result = modelDir;
    while (!result.empty() && (result.back() == '/' || result.back() == '\\')) {
        result.pop_back();
    }
    return result;
}

std::string trimString(const std::string& value) {
    size_t start = 0;
    while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start]))) {
        start += 1;
    }
    size_t end = value.size();
    while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1]))) {
        end -= 1;
    }
    return value.substr(start, end - start);
}

bool fileExists(const std::string& path) {
    std::ifstream stream(path, std::ios::binary);
    return stream.good();
}

std::string readTextFile(const std::string& path) {
    std::ifstream stream(path);
    if (!stream.good()) return "";
    std::ostringstream out;
    out << stream.rdbuf();
    return out.str();
}

std::string lowerCopy(const std::string& value) {
    std::string result = value;
    std::transform(result.begin(), result.end(), result.begin(), [](unsigned char ch) {
        return static_cast<char>(std::tolower(ch));
    });
    return result;
}

bool containsCpuFeature(const std::string& cpuInfo, const std::string& feature) {
    std::string token;
    std::string lower = lowerCopy(cpuInfo);
    for (char ch : lower) {
        if (std::isalnum(static_cast<unsigned char>(ch)) || ch == '_' || ch == '.') {
            token.push_back(ch);
            continue;
        }
        if (token == feature || token.rfind(feature, 0) == 0) return true;
        token.clear();
    }
    return token == feature || token.rfind(feature, 0) == 0;
}

bool supportsSme2CpuFeature() {
#if defined(__ANDROID__) && defined(__aarch64__) && defined(AT_HWCAP2) && defined(HWCAP2_SME2)
    if ((getauxval(AT_HWCAP2) & HWCAP2_SME2) != 0UL) return true;
#endif
    return containsCpuFeature(readTextFile("/proc/cpuinfo"), "sme2");
}

std::string normalizeTuningConfigJson(const std::string& tuningConfigJson) {
    std::string trimmed = trimString(tuningConfigJson);
    if (trimmed.empty()) return "{}";
    return trimmed;
}

void applyLlmTuningConfig(MNN::Transformer::Llm* llm, const std::string& tuningConfigJson) {
    std::string normalized = normalizeTuningConfigJson(tuningConfigJson);
    if (normalized == "{}") return;
    if (!llm->set_config(normalized)) {
        throw std::runtime_error("Failed to apply MNN LLM tuning config: " + normalized);
    }
}

std::string joinPath(const std::string& root, const std::string& child) {
    if (root.empty()) return child;
    if (root.back() == '/' || root.back() == '\\') return root + child;
    return root + "/" + child;
}

std::string findFirstFile(const std::string& modelDir, const std::vector<std::string>& candidates) {
    std::string root = trimModelDir(modelDir);
    for (const std::string& candidate : candidates) {
        std::string path = joinPath(root, candidate);
        if (fileExists(path)) return path;
    }
    return "";
}

bool isTextModel15B(const std::string& role) {
    std::string lower = lowerCopy(role);
    return lower.find("1.5b") != std::string::npos || lower.find("1_5b") != std::string::npos;
}

std::string textModelLabel(const std::string& role) {
    return isTextModel15B(role) ? "Qwen2.5-1.5B-Instruct-MNN" : "Qwen3-4B-Instruct-2507-MNN";
}

std::string findTextConfig(const std::string& modelDir, const std::string& role) {
    return findFirstFile(modelDir, isTextModel15B(role) ? kTextConfigCandidates15B : kTextConfigCandidates4B);
}

float clampFloat(float value, float minValue, float maxValue) {
    return std::max(minValue, std::min(maxValue, value));
}

float iou(const Detection& a, const Detection& b) {
    float x1 = std::max(a.x1, b.x1);
    float y1 = std::max(a.y1, b.y1);
    float x2 = std::min(a.x2, b.x2);
    float y2 = std::min(a.y2, b.y2);
    float w = std::max(0.0f, x2 - x1 + 1.0f);
    float h = std::max(0.0f, y2 - y1 + 1.0f);
    float intersection = w * h;
    float areaA = std::max(0.0f, a.x2 - a.x1 + 1.0f) * std::max(0.0f, a.y2 - a.y1 + 1.0f);
    float areaB = std::max(0.0f, b.x2 - b.x1 + 1.0f) * std::max(0.0f, b.y2 - b.y1 + 1.0f);
    float denom = areaA + areaB - intersection;
    return denom <= 0.0f ? 0.0f : intersection / denom;
}

std::vector<Detection> nmsByClass(std::vector<Detection> candidates) {
    std::vector<Detection> kept;
    std::sort(candidates.begin(), candidates.end(), [](const Detection& a, const Detection& b) {
        return a.score > b.score;
    });

    for (const Detection& candidate : candidates) {
        bool suppressed = false;
        for (const Detection& selected : kept) {
            if (iou(candidate, selected) > kNmsThreshold) {
                suppressed = true;
                break;
            }
        }
        if (!suppressed) kept.push_back(candidate);
    }
    return kept;
}

std::string jsonEscape(const std::string& value) {
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
                    out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                        << static_cast<int>(static_cast<unsigned char>(ch));
                } else {
                    out << ch;
                }
        }
    }
    return out.str();
}

std::string detectionsToJson(const std::vector<Detection>& detections, int imageWidth, int imageHeight) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(4);
    out << "{\"image_width\":" << imageWidth
        << ",\"image_height\":" << imageHeight
        << ",\"detections\":[";
    for (size_t i = 0; i < detections.size(); i += 1) {
        const Detection& d = detections[i];
        if (i > 0) out << ",";
        const char* className = (d.classId >= 0 && d.classId < static_cast<int>(std::size(kClassNames)))
            ? kClassNames[d.classId]
            : "unknown";
        out << "{\"class\":\"" << jsonEscape(className)
            << "\",\"class_id\":" << d.classId
            << ",\"score\":" << d.score
            << ",\"box\":["
            << std::setprecision(1) << d.x1 << "," << d.y1 << "," << d.x2 << "," << d.y2
            << std::setprecision(4) << "]}";
    }
    out << "]}";
    return out.str();
}

MNN::Tensor* findScoresTensor(MNN::Interpreter* net, MNN::Session* session) {
    MNN::Tensor* named = net->getSessionOutput(session, "output");
    if (named != nullptr) return named;
    const auto& outputs = net->getSessionOutputAll(session);
    for (const auto& item : outputs) {
        std::vector<int> shape = item.second->shape();
        if (shape.size() == 3 && shape[2] >= 80) return item.second;
    }
    return nullptr;
}

MNN::Tensor* findBoxesTensor(MNN::Interpreter* net, MNN::Session* session) {
    MNN::Tensor* named = net->getSessionOutput(session, "791");
    if (named != nullptr) return named;
    const auto& outputs = net->getSessionOutputAll(session);
    for (const auto& item : outputs) {
        std::vector<int> shape = item.second->shape();
        if (shape.size() == 3 && shape[2] == 4) return item.second;
    }
    return nullptr;
}

std::vector<Detection> decodeYolo(
    const float* scores,
    const std::vector<int>& scoresShape,
    const float* boxes,
    const std::vector<int>& boxesShape,
    int imageWidth,
    int imageHeight
) {
    if (scoresShape.size() != 3 || boxesShape.size() != 3 || boxesShape[2] != 4) {
        throw std::runtime_error("Unexpected DAMO-YOLO output tensor shape.");
    }

    int count = std::min(scoresShape[1], boxesShape[1]);
    int classCount = std::min(scoresShape[2], static_cast<int>(std::size(kClassNames)));
    float xScale = static_cast<float>(std::max(1, imageWidth)) / static_cast<float>(kInputSize);
    float yScale = static_cast<float>(std::max(1, imageHeight)) / static_cast<float>(kInputSize);

    std::vector<std::vector<Detection>> byClass(classCount);
    for (int index = 0; index < count; index += 1) {
        const float* box = boxes + (index * 4);
        float x1 = clampFloat(box[0] * xScale, 0.0f, static_cast<float>(std::max(1, imageWidth)));
        float y1 = clampFloat(box[1] * yScale, 0.0f, static_cast<float>(std::max(1, imageHeight)));
        float x2 = clampFloat(box[2] * xScale, 0.0f, static_cast<float>(std::max(1, imageWidth)));
        float y2 = clampFloat(box[3] * yScale, 0.0f, static_cast<float>(std::max(1, imageHeight)));
        if (x2 <= x1 || y2 <= y1) continue;

        for (int classId = 0; classId < classCount; classId += 1) {
            float score = scores[(index * scoresShape[2]) + classId];
            if (score < kScoreThreshold) continue;
            byClass[classId].push_back(Detection{x1, y1, x2, y2, score, classId});
        }
    }

    std::vector<Detection> detections;
    for (std::vector<Detection>& classCandidates : byClass) {
        std::vector<Detection> kept = nmsByClass(std::move(classCandidates));
        detections.insert(detections.end(), kept.begin(), kept.end());
    }

    std::sort(detections.begin(), detections.end(), [](const Detection& a, const Detection& b) {
        return a.score > b.score;
    });
    if (detections.size() > kMaxDetections) detections.resize(kMaxDetections);
    return detections;
}

std::string runYolo(const std::string& modelDir, const float* chwRgb, int imageWidth, int imageHeight) {
    std::string modelPath = findFirstFile(modelDir, kYoloModelCandidates);
    if (modelPath.empty()) {
        throw std::runtime_error("DAMO-YOLO .mnn model file was not found.");
    }

    std::unique_ptr<MNN::Interpreter, decltype(&MNN::Interpreter::destroy)> net(
        MNN::Interpreter::createFromFile(modelPath.c_str()),
        MNN::Interpreter::destroy
    );
    if (!net) {
        throw std::runtime_error("Failed to create MNN interpreter for DAMO-YOLO.");
    }

    MNN::ScheduleConfig config;
    MNN::BackendConfig backendConfig;
    config.type = MNN_FORWARD_CPU;
    config.numThread = 2;
    backendConfig.precision = MNN::BackendConfig::Precision_Normal;
    backendConfig.power = MNN::BackendConfig::Power_Normal;
    backendConfig.memory = MNN::BackendConfig::Memory_Normal;
    config.backendConfig = &backendConfig;

    MNN::Session* session = net->createSession(config);
    if (session == nullptr) {
        throw std::runtime_error("Failed to create DAMO-YOLO MNN session.");
    }

    MNN::Tensor* input = net->getSessionInput(session, "images");
    if (input == nullptr) input = net->getSessionInput(session, nullptr);
    if (input == nullptr) {
        throw std::runtime_error("DAMO-YOLO input tensor was not found.");
    }

    net->resizeTensor(input, {1, 3, kInputSize, kInputSize});
    net->resizeSession(session);

    std::unique_ptr<MNN::Tensor, decltype(&MNN::Tensor::destroy)> inputHost(
        MNN::Tensor::create<float>({1, 3, kInputSize, kInputSize}, const_cast<float*>(chwRgb), MNN::Tensor::CAFFE),
        MNN::Tensor::destroy
    );
    if (!input->copyFromHostTensor(inputHost.get())) {
        throw std::runtime_error("Failed to copy image tensor into DAMO-YOLO.");
    }

    MNN::ErrorCode code = net->runSession(session);
    if (code != MNN::NO_ERROR) {
        throw std::runtime_error("DAMO-YOLO MNN inference failed.");
    }

    MNN::Tensor* scoresDevice = findScoresTensor(net.get(), session);
    MNN::Tensor* boxesDevice = findBoxesTensor(net.get(), session);
    if (scoresDevice == nullptr || boxesDevice == nullptr) {
        throw std::runtime_error("DAMO-YOLO output tensors were not found.");
    }

    std::unique_ptr<MNN::Tensor, decltype(&MNN::Tensor::destroy)> scoresHost(
        MNN::Tensor::createHostTensorFromDevice(scoresDevice, true),
        MNN::Tensor::destroy
    );
    std::unique_ptr<MNN::Tensor, decltype(&MNN::Tensor::destroy)> boxesHost(
        MNN::Tensor::createHostTensorFromDevice(boxesDevice, true),
        MNN::Tensor::destroy
    );
    if (!scoresHost || !boxesHost) {
        throw std::runtime_error("Failed to copy DAMO-YOLO outputs to host.");
    }

    std::vector<Detection> detections = decodeYolo(
        scoresHost->host<float>(),
        scoresHost->shape(),
        boxesHost->host<float>(),
        boxesHost->shape(),
        imageWidth,
        imageHeight
    );
    return detectionsToJson(detections, imageWidth, imageHeight);
}

MNN::Transformer::Llm* ensureLlmLoaded(const std::string& modelDir, const std::string& role) {
    std::string configPath = findTextConfig(modelDir, role);
    if (configPath.empty()) {
        throw std::runtime_error(textModelLabel(role) + " config.json was not found.");
    }

    std::lock_guard<std::mutex> lock(gLlmMutex);
    if (gLlm && gLlmConfigPath == configPath) {
        return gLlm.get();
    }

    std::unique_ptr<MNN::Transformer::Llm, LlmDeleter> next(
        MNN::Transformer::Llm::createLLM(configPath)
    );
    if (!next) {
        throw std::runtime_error("Failed to create MNN LLM.");
    }
    if (!next->load()) {
        throw std::runtime_error("Failed to load " + textModelLabel(role) + " model.");
    }

    gLlmConfigPath = configPath;
    gLlm = std::move(next);
    return gLlm.get();
}

std::string runLlm(
    const std::string& modelDir,
    const std::string& role,
    const std::string& prompt,
    const std::string& tuningConfigJson,
    int requestedMaxNewTokens,
    const std::string& endWith
) {
    std::lock_guard<std::mutex> lock(gLlmMutex);
    std::string configPath = findTextConfig(modelDir, role);
    if (configPath.empty()) {
        throw std::runtime_error(textModelLabel(role) + " config.json was not found.");
    }
    std::string normalizedTuningConfig = normalizeTuningConfigJson(tuningConfigJson);
    if (!gLlm || gLlmConfigPath != configPath || gLlmTuningConfigJson != normalizedTuningConfig) {
        std::unique_ptr<MNN::Transformer::Llm, LlmDeleter> next(
            MNN::Transformer::Llm::createLLM(configPath)
        );
        if (!next) {
            throw std::runtime_error("Failed to create MNN LLM.");
        }
        applyLlmTuningConfig(next.get(), normalizedTuningConfig);
        if (!next->load()) {
            throw std::runtime_error("Failed to load " + textModelLabel(role) + " model.");
        }
        gLlmConfigPath = configPath;
        gLlmTuningConfigJson = normalizedTuningConfig;
        gLlm = std::move(next);
    }

    int defaultMaxNewTokens = isTextModel15B(role) ? 128 : 160;
    int maxNewTokens = requestedMaxNewTokens > 0 ? requestedMaxNewTokens : defaultMaxNewTokens;
    maxNewTokens = std::max(16, std::min(maxNewTokens, 512));
    std::ostringstream response;
    const char* endWithPtr = endWith.empty() ? nullptr : endWith.c_str();
    gLlm->response(prompt, &response, endWithPtr, maxNewTokens);
    return response.str();
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeRuntimeKind(
    JNIEnv* env,
    jobject
) {
    return env->NewStringUTF(supportsSme2CpuFeature() ? "mnn-arm64-v8a+sme2" : "mnn-arm64-v8a");
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeSupportsSme2(
    JNIEnv*,
    jobject
) {
    return supportsSme2CpuFeature() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeVisionJson(
    JNIEnv* env,
    jobject,
    jstring modelDir,
    jstring,
    jfloatArray chwRgb,
    jint imageWidth,
    jint imageHeight,
    jstring
) {
    jfloat* values = nullptr;
    try {
        if (chwRgb == nullptr) {
            throw std::runtime_error("Image tensor is empty.");
        }
        jsize length = env->GetArrayLength(chwRgb);
        if (length != 3 * kInputSize * kInputSize) {
            throw std::runtime_error("Image tensor has an unexpected size.");
        }
        values = env->GetFloatArrayElements(chwRgb, nullptr);
        if (values == nullptr) {
            throw std::runtime_error("Failed to access image tensor.");
        }
        std::string json = runYolo(toString(env, modelDir), values, imageWidth, imageHeight);
        env->ReleaseFloatArrayElements(chwRgb, values, JNI_ABORT);
        return env->NewStringUTF(json.c_str());
    } catch (const std::exception& error) {
        if (values != nullptr) env->ReleaseFloatArrayElements(chwRgb, values, JNI_ABORT);
        throwIllegalState(env, error.what());
        return nullptr;
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeTextJson(
    JNIEnv* env,
    jobject,
    jstring modelDir,
    jstring prompt,
    jstring role,
    jstring tuningConfigJson,
    jint maxNewTokens,
    jstring endWith
) {
    try {
        std::string response = runLlm(
            toString(env, modelDir),
            toString(env, role),
            toString(env, prompt),
            toString(env, tuningConfigJson),
            static_cast<int>(maxNewTokens),
            toString(env, endWith)
        );
        return env->NewStringUTF(response.c_str());
    } catch (const std::exception& error) {
        throwIllegalState(env, error.what());
        return nullptr;
    }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_silvercare_aiassistant_MnnNativeBridge_nativeTranscribe(
    JNIEnv* env,
    jobject,
    jstring,
    jstring
) {
    throwIllegalState(env, "Local ASR is not implemented for the text-only Qwen MNN runtime.");
    return nullptr;
}
