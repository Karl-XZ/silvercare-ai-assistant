package com.silvercare.aiassistant;

import java.io.File;

interface LocalTtsRuntimeBridge {
    boolean isAvailable();

    String runtimeSummary();

    File synthesizeToWav(File modelDir, File cacheDir, String text, String language) throws Exception;
}
