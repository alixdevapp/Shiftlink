package app.shiftlink

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Voix du téléphone : annonce la vitesse et les alertes, par-dessus le son de l'appli. */
class Voice(context: Context) : MethodChannel.MethodCallHandler, TextToSpeech.OnInitListener {
    private val tts = TextToSpeech(context.applicationContext, this)
    private var ready = false
    private var pending: Pair<String, String>? = null

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
            tts.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            pending?.let { speak(it.first, it.second) }
        }
        pending = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "speak") return result.notImplemented()
        val text = call.argument<String>("text").orEmpty()
        val lang = call.argument<String>("lang") ?: "fr"
        if (text.isNotEmpty()) {
            if (ready) speak(text, lang) else pending = text to lang
        }
        result.success(null)
    }

    private fun speak(text: String, lang: String) {
        val locale = Locale.forLanguageTag(lang)
        if (tts.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) tts.language = locale
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "shiftlink")
    }
}
