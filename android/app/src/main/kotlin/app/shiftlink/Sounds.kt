package app.shiftlink

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bips courts : une vitesse, la dernière vitesse, la butée, le compte à rebours des séances. */
class Sounds : MethodChannel.MethodCallHandler {
    private val tones: ToneGenerator? = try {
        ToneGenerator(AudioManager.STREAM_NOTIFICATION, 70)
    } catch (_: RuntimeException) {
        null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "tone") return result.notImplemented()
        val (tone, ms) = when (call.argument<String>("kind")) {
            "last" -> ToneGenerator.TONE_PROP_BEEP2 to 220
            "limit" -> ToneGenerator.TONE_PROP_NACK to 250
            "count" -> ToneGenerator.TONE_PROP_BEEP to 150
            "go" -> ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD to 450
            else -> ToneGenerator.TONE_PROP_BEEP to 60
        }
        tones?.startTone(tone, ms)
        result.success(null)
    }
}
