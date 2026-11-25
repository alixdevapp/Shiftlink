// Vitesses sur le même téléphone : ShiftLink touche les boutons + et − de l'appli
// d'entraînement à l'écran, grâce au service d'accessibilité d'Android.
package app.shiftlink

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ShiftTapService : AccessibilityService() {
    companion object {
        var instance: ShiftTapService? = null
            private set
        var listener: ((String, Map<String, Any?>) -> Unit)? = null
        var lastPackage: String? = null

        /** Capture des touches des télécommandes, manettes de jeu et claviers externes. */
        var captureKeys = false

        /** Touches réglées sur une action, « appareil|TOUCHE » : seules celles-ci sont prises. */
        var capturedKeys: Set<String> = emptySet()

        /** Appareils déjà connus de ShiftLink. */
        var knownDevices: Set<String> = emptySet()

        /** Touches prises sur un appareil encore inconnu (réglages par défaut). */
        var defaultKeys: Set<String> = emptySet()
    }

    /** Télécommandes et manettes de jeu : tout est pris, comme avant. Vrai clavier : seules
     *  les touches réglées sur une action, pour qu'il continue de taper normalement. */
    private fun consumes(dev: InputDevice, label: String): Boolean {
        if (dev.keyboardType != InputDevice.KEYBOARD_TYPE_ALPHABETIC) return true
        val d = dev.descriptor
        return if (d in knownDevices) "$d|$label" in capturedKeys else label in defaultKeys
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (!captureKeys) return false
        val dev = event.device ?: return false
        if (dev.isVirtual) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !dev.isExternal) return false
        if (event.action != KeyEvent.ACTION_DOWN && event.action != KeyEvent.ACTION_UP) return false
        val label = KeyEvent.keyCodeToString(event.keyCode).removePrefix("KEYCODE_")
        val consume = consumes(dev, label)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount > 0) return consume
        notify("key", mapOf(
            "device" to dev.descriptor,
            "name" to dev.name,
            "code" to event.keyCode,
            "label" to label,
            "down" to (event.action == KeyEvent.ACTION_DOWN),
        ))
        return consume
    }

    private val main = Handler(Looper.getMainLooper())
    private var bubble: View? = null
    private var capture: View? = null

    override fun onServiceConnected() {
        instance = this
        notify("status", mapOf("enabled" to true))
    }

    override fun onUnbind(intent: Intent?): Boolean {
        removeOverlays()
        instance = null
        notify("status", mapOf("enabled" to false))
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        removeOverlays()
        hud?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        hud = null
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg != packageName && pkg != "com.android.systemui") lastPackage = pkg
    }

    override fun onInterrupt() {}

    private fun notify(method: String, args: Map<String, Any?>) {
        main.post { listener?.invoke(method, args) }
    }

    /** Taille réelle de l'écran, dans son orientation actuelle. */
    private fun screenSize(): Pair<Float, Float> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            return b.width().toFloat() to b.height().toFloat()
        }
        val m = android.util.DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(m)
        return m.widthPixels.toFloat() to m.heightPixels.toFloat()
    }

    /** Un appui bref à la position (x %, y %) de l'écran. */
    fun tap(xPct: Float, yPct: Float): Boolean {
        if (capture != null) return false
        val (w, h) = screenSize()
        val path = Path().apply { moveTo(xPct / 100f * w, yPct / 100f * h) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    fun global(name: String): Boolean {
        val action = when (name) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            "screenshot" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) GLOBAL_ACTION_TAKE_SCREENSHOT else return false
            else -> return false
        }
        return performGlobalAction(action)
    }

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    private val wm get() = getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private fun label(text: String, size: Float, bold: Boolean = false) = TextView(this).apply {
        this.text = text
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
    }

    /** Affiche la bulle « Régler » par-dessus toutes les applis. */
    private var labels: List<String> = emptyList()

    fun showBubble(labels: List<String>) {
        this.labels = labels
        main.post {
            removeOverlays()
            val box = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(16), dp(10), dp(8), dp(10))
                background = GradientDrawable().apply {
                    cornerRadius = dp(24).toFloat()
                    setColor(Color.parseColor("#FF5A1F"))
                }
                elevation = dp(6).toFloat()
            }
            val go = label("ShiftLink · Régler les boutons", 15f, bold = true)
            val close = label("  ✕  ", 16f, bold = true)
            box.addView(go)
            box.addView(close)
            go.setOnClickListener { showCapture() }
            close.setOnClickListener {
                removeOverlays()
                notify("calibration", mapOf("state" to "cancelled"))
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                y = dp(48)
            }
            wm.addView(box, params)
            bubble = box
        }
    }

    /** Écran transparent qui attend l'appui sur +, puis sur −. */
    private fun showCapture() {
        removeOverlays()
        val points = mutableListOf<Pair<Float, Float>>()
        val total = labels.size
        fun prompt(i: Int) = "Touche le bouton « ${labels[i]} » de ton appli" + if (total > 1) "  (${i + 1}/$total)" else ""
        val root = FrameLayout(this).apply { setBackgroundColor(Color.parseColor("#66000000")) }
        val text = label(prompt(0), 20f, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(dp(24), dp(16), dp(24), dp(16))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#DD14161C"))
            }
        }
        root.addView(text, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER,
        ))
        root.setOnTouchListener { _, e ->
            if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                val (w, h) = screenSize()
                points.add(e.rawX / w * 100f to e.rawY / h * 100f)
                if (points.size < total) {
                    text.text = prompt(points.size)
                } else {
                    removeOverlays()
                    notify("calibration", mapOf(
                        "state" to "done",
                        "points" to points.map { listOf(it.first.toDouble(), it.second.toDouble()) },
                        "package" to lastPackage,
                    ))
                }
            }
            true
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        wm.addView(root, params)
        capture = root
    }

    private var hud: LinearLayout? = null
    private var hudTitle: TextView? = null
    private var hudSub: TextView? = null
    private var hudParams: WindowManager.LayoutParams? = null

    /** Petit affichage déplaçable par-dessus l'appli d'entraînement. */
    private var hudButtons = false

    fun showHud(title: String, subtitle: String, buttons: Boolean = false) {
        main.post {
            // Boutons ajoutés ou retirés : on refait la fenêtre.
            if (hud != null && buttons != hudButtons) {
                hud?.let { try { wm.removeView(it) } catch (_: Exception) {} }
                hud = null
            }
            hudButtons = buttons
            if (hud == null) {
                val box = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(14), dp(8), dp(14), dp(8))
                    background = GradientDrawable().apply {
                        cornerRadius = dp(16).toFloat()
                        setColor(Color.parseColor("#E614161C"))
                        setStroke(dp(2), Color.parseColor("#FF5A1F"))
                    }
                }
                val t = label(title, 22f, bold = true)
                val st = label(subtitle, 13f).apply { setTextColor(Color.parseColor("#FFC9CDD6")) }
                box.addView(t)
                box.addView(st)
                if (buttons) {
                    // − et + : changent de vitesse sans quitter l'appli.
                    val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                    for ((text, delta) in listOf("−" to -1, "+" to 1)) {
                        val b = label(text, 26f, bold = true).apply {
                            gravity = Gravity.CENTER
                            setPadding(dp(18), dp(2), dp(18), dp(4))
                            background = GradientDrawable().apply {
                                cornerRadius = dp(12).toFloat()
                                setColor(Color.parseColor(if (delta > 0) "#FFFF5A1F" else "#FF3A3D46"))
                            }
                            contentDescription = if (delta > 0) "Plus dur" else "Plus facile"
                            setOnClickListener { notify("hudShift", mapOf("delta" to delta)) }
                        }
                        row.addView(b, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                            setMargins(dp(3), dp(6), dp(3), 0)
                        })
                    }
                    box.addView(row, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
                }
                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT,
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = hudX
                    y = hudY
                }
                var startX = 0f
                var startY = 0f
                var baseX = 0
                var baseY = 0
                box.setOnTouchListener { v, e ->
                    when (e.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            startX = e.rawX; startY = e.rawY; baseX = params.x; baseY = params.y
                        }
                        MotionEvent.ACTION_MOVE -> {
                            params.x = baseX + (e.rawX - startX).toInt()
                            params.y = baseY + (e.rawY - startY).toInt()
                            hudX = params.x
                            hudY = params.y
                            try { wm.updateViewLayout(v, params) } catch (_: Exception) {}
                        }
                    }
                    true
                }
                wm.addView(box, params)
                hud = box
                hudTitle = t
                hudSub = st
                hudParams = params
            } else {
                hudTitle?.text = title
                hudSub?.text = subtitle
            }
        }
    }

    fun hideHud() {
        main.post {
            hud?.let { try { wm.removeView(it) } catch (_: Exception) {} }
            hud = null
        }
    }

    private var hudX = 24
    private var hudY = 160

    private var markers: View? = null

    /** Montre les cibles enregistrées pendant quelques secondes, sans bloquer l'écran. */
    fun showMarkers(points: List<List<Double>>, names: List<String>) {
        main.post {
            markers?.let { try { wm.removeView(it) } catch (_: Exception) {} }
            val (w, h) = screenSize()
            val view = object : View(this) {
                val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = dp(4).toFloat()
                    color = Color.parseColor("#FF5A1F")
                }
                val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#55FF5A1F") }
                val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = Color.WHITE
                    textSize = dp(14).toFloat()
                    isFakeBoldText = true
                    setShadowLayer(dp(3).toFloat(), 0f, 0f, Color.BLACK)
                }
                override fun onDraw(c: Canvas) {
                    for ((i, p) in points.withIndex()) {
                        val x = (p[0] / 100.0 * w).toFloat()
                        val y = (p[1] / 100.0 * h).toFloat()
                        c.drawCircle(x, y, dp(22).toFloat(), fill)
                        c.drawCircle(x, y, dp(22).toFloat(), ring)
                        val n = names.getOrElse(i) { "" }
                        c.drawText(n, x - text.measureText(n) / 2, y - dp(30), text)
                    }
                }
            }
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT,
            )
            wm.addView(view, params)
            markers = view
            main.postDelayed({
                if (markers === view) {
                    try { wm.removeView(view) } catch (_: Exception) {}
                    markers = null
                }
            }, 6000)
        }
    }

    fun removeOverlays() {
        for (v in listOfNotNull(bubble, capture)) {
            try {
                wm.removeView(v)
            } catch (_: Exception) {}
        }
        bubble = null
        capture = null
    }
}

/** Canal entre Flutter et le service d'accessibilité. */
class ScreenTapsChannel(private val context: Context, channel: MethodChannel) : MethodChannel.MethodCallHandler {
    init {
        ShiftTapService.listener = { method, args -> channel.invokeMethod(method, args) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isEnabled" -> result.success(ShiftTapService.instance != null)
            "openSettings" -> {
                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            "openAppInfo" -> {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(null)
            }
            "openBluetoothSettings" -> {
                val tries = listOf(
                    Intent(Settings.ACTION_BLUETOOTH_SETTINGS),
                    Intent(Settings.ACTION_WIRELESS_SETTINGS),
                    Intent(Settings.ACTION_SETTINGS),
                )
                var ok = false
                for (i in tries) {
                    try {
                        context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        ok = true
                        break
                    } catch (_: Exception) {}
                }
                result.success(ok)
            }
            "calibrate" -> {
                val s = ShiftTapService.instance
                s?.showBubble(call.argument<List<String>>("labels") ?: listOf("Plus dur", "Plus facile"))
                result.success(s != null)
            }
            "showMarkers" -> {
                val s = ShiftTapService.instance
                s?.showMarkers(call.argument<List<List<Double>>>("points") ?: emptyList(), call.argument<List<String>>("labels") ?: emptyList())
                result.success(s != null)
            }
            "captureKeys" -> {
                ShiftTapService.captureKeys = call.argument<Boolean>("on") ?: false
                call.argument<List<String>>("keys")?.let { ShiftTapService.capturedKeys = it.toSet() }
                call.argument<List<String>>("devices")?.let { ShiftTapService.knownDevices = it.toSet() }
                call.argument<List<String>>("defaults")?.let { ShiftTapService.defaultKeys = it.toSet() }
                result.success(null)
            }
            "hud" -> {
                val s = ShiftTapService.instance
                if (call.argument<Boolean>("show") == true) {
                    s?.showHud(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("subtitle") ?: "",
                        call.argument<Boolean>("buttons") == true,
                    )
                } else {
                    s?.hideHud()
                }
                result.success(s != null)
            }
            "global" -> result.success(ShiftTapService.instance?.global(call.argument<String>("name") ?: "") ?: false)
            "media" -> {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val code = when (call.argument<String>("key")) {
                    "playPause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                    "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                    else -> null
                }
                if (code != null) {
                    audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
                    audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
                }
                result.success(code != null)
            }
            "volume" -> {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val up = call.argument<Boolean>("up") ?: true
                audio.adjustStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    if (up) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                    AudioManager.FLAG_SHOW_UI,
                )
                result.success(true)
            }
            "rumble" -> result.success(rumble(call.argument<String>("device") ?: "", call.argument<Boolean>("strong") == true))
            "cancelCalibration" -> {
                ShiftTapService.instance?.removeOverlays()
                result.success(null)
            }
            "tap" -> {
                val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                result.success(ShiftTapService.instance?.tap(x, y) ?: false)
            }
            else -> result.notImplemented()
        }
    }

    /** Vibration courte d'une manette de jeu, retrouvée par son descripteur. */
    private fun rumble(descriptor: String, strong: Boolean): Boolean {
        val ms = if (strong) 180L else 60L
        for (id in android.view.InputDevice.getDeviceIds()) {
            val dev = android.view.InputDevice.getDevice(id) ?: continue
            if (dev.descriptor != descriptor) continue
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = dev.vibratorManager
                    if (vm.vibratorIds.isEmpty()) return false
                    vm.vibrate(
                        android.os.CombinedVibration.createParallel(
                            android.os.VibrationEffect.createOneShot(ms, if (strong) 255 else 120)
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    val v = dev.vibrator
                    if (!v.hasVibrator()) return false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        v.vibrate(android.os.VibrationEffect.createOneShot(ms, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        v.vibrate(ms)
                    }
                }
                return true
            } catch (_: Exception) {
                return false
            }
        }
        return false
    }
}
