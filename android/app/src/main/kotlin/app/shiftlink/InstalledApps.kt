package app.shiftlink

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Une appli d'entraînement est-elle installée ? On compare seulement les noms du lanceur. */
class InstalledApps(private val context: Context) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "open") return open(call.argument<String>("name").orEmpty(), result)
        if (call.method == "color") {
            val n = call.argument<String>("name")?.trim()?.lowercase().orEmpty()
            val main = android.os.Handler(android.os.Looper.getMainLooper())
            worker.execute {
                val c = try { iconColor(n) } catch (_: Exception) { null }
                main.post { result.success(c) }
            }
            return
        }
        if (call.method == "iconPng") {
            val n = call.argument<String>("name")?.trim()?.lowercase().orEmpty()
            val size = call.argument<Int>("size") ?: 96
            val main = android.os.Handler(android.os.Looper.getMainLooper())
            worker.execute {
                val bytes = try { iconPng(n, size) } catch (_: Exception) { null }
                main.post { result.success(bytes) }
            }
            return
        }
        if (call.method != "installed") return result.notImplemented()
        val name = call.argument<String>("name")?.trim()?.lowercase()
        if (name.isNullOrEmpty()) return result.success(false)
        val main = android.os.Handler(android.os.Looper.getMainLooper())
        worker.execute {
            val found = try { find(name) } catch (_: Exception) { false }
            main.post { result.success(found) }
        }
    }

    private fun find(name: String): Boolean = findPackage(name) != null

    private fun findPackage(name: String): String? {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .filter { it.activityInfo.packageName != context.packageName }
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString().trim().lowercase() }
            .firstOrNull { (_, label) -> label == name || (label.contains(name) && !label.contains("companion")) }
            ?.first
    }

    /** Couleur principale de l'icône de l'appli installée (ARGB), ou null. */
    private fun iconColor(name: String): Int? {
        if (name.isEmpty()) return null
        val pkg = findPackage(name) ?: return null
        val icon = context.packageManager.getApplicationIcon(pkg)
        val size = 64
        val bmp = android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        icon.setBounds(0, 0, size, size)
        icon.draw(canvas)
        // On regroupe les pixels par teinte proche et on garde le groupe le plus présent,
        // en écartant le transparent, le blanc, le noir et les gris.
        val counts = HashMap<Int, Int>()
        val sums = HashMap<Int, LongArray>()
        val hsv = FloatArray(3)
        for (y in 0 until size) for (x in 0 until size) {
            val p = bmp.getPixel(x, y)
            if (android.graphics.Color.alpha(p) < 200) continue
            android.graphics.Color.colorToHSV(p, hsv)
            if (hsv[1] < 0.35f || hsv[2] < 0.25f) continue
            val key = (hsv[0] / 15f).toInt()
            counts[key] = (counts[key] ?: 0) + 1
            val s = sums.getOrPut(key) { LongArray(3) }
            s[0] += android.graphics.Color.red(p).toLong()
            s[1] += android.graphics.Color.green(p).toLong()
            s[2] += android.graphics.Color.blue(p).toLong()
        }
        bmp.recycle()
        val best = counts.maxByOrNull { it.value } ?: return null
        if (best.value < size * size / 40) return null // presque pas de couleur : icône noir et blanc
        val s = sums[best.key]!!
        val n = best.value
        return android.graphics.Color.rgb((s[0] / n).toInt(), (s[1] / n).toInt(), (s[2] / n).toInt())
    }

    /** Icône de l'appli installée, rendue à [size] × [size] en PNG, ou null. */
    private fun iconPng(name: String, size: Int): ByteArray? {
        if (name.isEmpty()) return null
        val pkg = findPackage(name) ?: return null
        val icon = context.packageManager.getApplicationIcon(pkg)
        val s = size.coerceIn(24, 192)
        val bmp = android.graphics.Bitmap.createBitmap(s, s, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bmp)
        icon.setBounds(0, 0, s, s)
        icon.draw(canvas)
        val out = java.io.ByteArrayOutputStream()
        bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    /** Ouvre l'appli du fabricant si elle est installée, sinon sa recherche dans le Play Store. */
    private fun open(name: String, result: MethodChannel.Result) {
        val pkg = try { findPackage(name.trim().lowercase()) } catch (_: Exception) { null }
        val launch = pkg?.let { context.packageManager.getLaunchIntentForPackage(it) }
        val q = android.net.Uri.encode(name)
        val intents = listOfNotNull(
            launch,
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse("market://search?q=$q&c=apps")),
            Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://play.google.com/store/search?q=$q&c=apps")),
        )
        for (i in intents) {
            try {
                context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return result.success(if (i == launch) "app" else "store")
            } catch (_: Exception) {}
        }
        result.success("none")
    }
}
