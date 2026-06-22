package com.pappostudios.milometry

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "com.pappostudios.milometry/tts"
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    // Holds a speak request that arrived before the engine finished initializing.
    private var pending: Triple<String, String, Float>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        tts = TextToSpeech(applicationContext) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                pending?.let { (t, l, r) -> speakNow(t, l, r) }
            }
            pending = null
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("language") ?: "en-US"
                        val rate = (call.argument<Double>("rate") ?: 0.5).toFloat()
                        if (ttsReady) speakNow(text, lang, rate) else pending = Triple(text, lang, rate)
                        result.success(null)
                    }
                    "stop" -> {
                        tts?.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun speakNow(text: String, language: String, rate: Float) {
        val locale = if (language.startsWith("he")) Locale("he", "IL") else Locale.US
        tts?.language = locale
        // Dart passes ~0.5 as "normal" (matching iOS AVSpeech default); Android's
        // normal rate is 1.0, so scale by 2 to keep the speed slider consistent.
        tts?.setSpeechRate((rate * 2f).coerceIn(0.1f, 3.0f))
        tts?.stop()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "milometry-utterance")
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
