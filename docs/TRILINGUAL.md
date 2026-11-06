# 银龄智护三语版

基线为公开发布标签 `v1.0.0-beta.1`，上游提交 `4ee07a31479b3ff6bb05d024d1e72066f762f387`。本分支版本为 `1.1.0-trilingual`（versionCode 12），保留原稳定版的 Qwen/MNN、DAMO-YOLO 与 SenseVoice 方案。

## 使用

打开设置，选择“语言 / Language / 言語”，切换“简体中文 / English / 日本語”。选择会保存，重新启动后仍然生效。界面、原生对话框、语音识别参数、朗读语言、模型回答和应用生成的功能提示统一切换；切换时结束旧语言录音与播报。

本地 SenseVoice 直接使用同一组多语权重，识别语言依次为 `zh`、`en`、`ja`。系统 TTS 使用 `zh-CN`、`en-US`、`ja-JP`；联网 TTS 使用相应语言参数。英语、日语不会使用中文专用的 MNN 声音，需安装对应系统语音或使用联网朗读。

联网功能需要在应用设置中填入自己的 DashScope Key。安装包不内置测试 Key。新安装默认视觉模型为已在本轮接口验证可用的 `qwen3-vl-plus`；已有的自定义模型配置保留。

用户姓名、原始记录、历史描述和自定义路径保持原样。内部指令与检测类别仍使用稳定版的协议，展示时转换为当前语言。历史物品位置明确标注为上次记录，不能当作当前位置。

## 翻译文件

- 网页界面：`app/src/main/assets/static/js/locales/{zh,en,ja}.js`。
- Android 与业务提示：`app/src/main/resources/i18n/{native,backend}-{en,ja}.json`。中文原文作为键和默认值。
- Android 应用名称：`app/src/main/res/values*/strings.xml`。
- 入口与语音策略：`i18n.js`、`AppLanguage.java`、`LanguageResources.java`。

模型提示词保留协议结构，并明确要求当前语言输出。检测类别、协议字段和数据库键不是展示文字，不应随翻译修改。

若生成文字夹带中文，会由实际文本模型补做一次语言修正，只替换生成的展示、朗读字段，不改检测类别、协议、姓名或原始记录。正常回答不增加调用，语音识别结果不会经过这一翻译步骤。

## 验证

常规检查：

```text
node tools/check-js.mjs
node --test app/src/test/js/*.test.mjs
gradlew.bat :app:testDebugUnitTest :app:assembleDebug --offline
```

真实云端测试使用单独的 `SILVERCARE_I18N_TEST_KEY`，避免将测试凭据写入 BuildConfig。`tools/run-language-build.py` 可选读取测试人员指定的本地环境文件，测试输出位于 `reports/i18n-20261105/`。

`LanguageValidationActivity` 只存在于 debug 源集，用真实音频检查本地 ASR 和系统语音合成。测试 WAV 和 ASR 权重不打入安装包。浏览器和模拟器测试脚本、截图与原始结果用于复核；模拟器相机、传感器回放和单元测试模拟不能代替真实行走、跌倒或真人识别准确率测试。

本机 x86_64 模拟器可运行 SenseVoice 和系统 TTS；稳定版 MNN 离线大语言模型运行库面向 arm64，端侧 Qwen 的实际整机推理仍需在兼容 arm64 设备验收。本轮未连接或安装到实体手机。

ASR 是统计识别模型，测试中存在个别词语误识别；界面翻译与切换测试通过不代表任何语言、任何口音的识别准确率达到百分之百。
