package com.pappostudios.milometry

import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "com.pappostudios.milometry/tts"
    private val insetsChannelName = "com.pappostudios.milometry/insets"
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

        // Some OEM builds (seen on Samsung One UI with 3-button navigation,
        // Android 16 targetSdk where edge-to-edge can no longer be opted out
        // of) don't reliably propagate the navigation-bar inset through
        // Flutter's MediaQuery. Read it directly from the real WindowInsets
        // as a fallback so Dart can pad bottom action buttons correctly.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, insetsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNavigationBarInsetDp" -> {
                        val insets = ViewCompat.getRootWindowInsets(window.decorView)
                        val bottomPx = insets
                            ?.getInsets(WindowInsetsCompat.Type.navigationBars())
                            ?.bottom ?: 0
                        val density = resources.displayMetrics.density
                        result.success(bottomPx / density)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun speakNow(text: String, language: String, rate: Float) {
        val locale = if (language.startsWith("he")) Locale("he", "IL") else Locale.US
        tts?.language = locale
        selectBestVoice(locale)
        // Dart passes ~0.5 as "normal" (matching iOS AVSpeech default); Android's
        // normal rate is 1.0, so scale by 2 to keep the speed slider consistent.
        tts?.setSpeechRate((rate * 2f).coerceIn(0.1f, 3.0f))
        tts?.stop()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "milometry-utterance")
    }

    // Cache the best voice chosen per language tag so we don't re-scan each call.
    private val voiceCache = HashMap<String, Voice>()

    /// Picks the clearest installed voice for a locale, preferring higher
    /// quality and voices that don't require a network fetch. Addresses the
    /// "robotic voice" complaint the same way iOS enhanced-voice selection does.
    private fun selectBestVoice(locale: Locale) {
        val engine = tts ?: return
        val key = locale.language
        voiceCache[key]?.let { engine.voice = it; return }

        val best = try {
            engine.voices
                ?.filter { it.locale.language == locale.language }
                ?.filterNot { it.isNetworkConnectionRequired }
                ?.filterNot { it.features?.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) == true }
                ?.maxByOrNull { it.quality }
        } catch (e: Exception) {
            null
        }

        if (best != null) {
            engine.voice = best
            voiceCache[key] = best
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
