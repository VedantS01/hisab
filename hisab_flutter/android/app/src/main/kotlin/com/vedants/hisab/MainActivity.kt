package com.vedants.hisab

import androidx.lifecycle.lifecycleScope
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Candidate
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private var model: GenerativeModel? = null

    /**
     * The statement reader's on-device model: Gemini Nano, through ML Kit's
     * Prompt API (AICore). Nothing leaves the phone. Dart asks "status" before
     * offering the model's look, then "label" with the prompt; the reply is
     * read in Dart (ColumnLabelPrompt) and trusted only if the balance chain
     * closes under it. The API runs only while the app is in the foreground,
     * which an import always is.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hisab/column_reader")
            .setMethodCallHandler { call, result ->
                lifecycleScope.launch {
                    try {
                        val model = model ?: Generation.getClient().also { model = it }
                        when (call.method) {
                            "status" -> result.success(
                                when (model.checkStatus()) {
                                    FeatureStatus.AVAILABLE -> "available"
                                    FeatureStatus.DOWNLOADABLE -> "downloadable"
                                    FeatureStatus.DOWNLOADING -> "downloading"
                                    else -> "unavailable"
                                }
                            )
                            "label" -> {
                                // Greedy, like the iOS reader: the most likely
                                // labels, the same ones every time.
                                val request = generateContentRequest(TextPart(call.argument<String>("prompt")!!)) {
                                    temperature = 0f
                                    topK = 1
                                    seed = 1
                                    candidateCount = 1
                                    maxOutputTokens = 256
                                }
                                val candidate = model.generateContent(request).candidates.first()
                                if (candidate.finishReason == Candidate.FinishReason.MAX_TOKENS) {
                                    result.error("truncated", "reply cut off", null)
                                } else {
                                    result.success(candidate.text)
                                }
                            }
                            else -> result.notImplemented()
                        }
                    } catch (e: Exception) {
                        // No AICore, an unsupported phone, a busy or
                        // background-blocked model: the import just refuses
                        // as it did before.
                        result.error("model", e.message, null)
                    }
                }
            }
    }

    override fun onDestroy() {
        model?.close()
        model = null
        super.onDestroy()
    }
}
