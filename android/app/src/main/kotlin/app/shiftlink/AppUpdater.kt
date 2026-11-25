package app.shiftlink

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Mise à jour depuis l'appli : ouvre l'installeur d'Android sur l'APK téléchargé dans le
 * cache (dossier « updates »). Android refuse l'APK s'il n'est pas signé avec la même clé.
 */
class AppUpdater(private val activity: Activity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "install") return result.notImplemented()
        try {
            val path = call.argument<String>("path") ?: return result.success("failed")
            val dir = File(activity.cacheDir, "updates").canonicalFile
            val file = File(path).canonicalFile
            if (file.parentFile != dir || !file.name.endsWith(".apk") || !file.isFile) {
                return result.success("failed")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !activity.packageManager.canRequestPackageInstalls()
            ) {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    ),
                )
                return result.success("permission")
            }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.success("failed")
        }
    }
}
