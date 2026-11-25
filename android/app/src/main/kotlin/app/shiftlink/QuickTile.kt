package app.shiftlink

import android.app.PendingIntent
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Tuile des réglages rapides : ouvre ShiftLink d'un glissement du doigt. */
class QuickTile : TileService() {
    override fun onStartListening() {
        val tile = qsTile ?: return
        tile.label = "ShiftLink"
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val go = {
            if (Build.VERSION.SDK_INT >= 34) {
                val pi = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
                startActivityAndCollapse(pi)
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            }
        }
        if (isLocked) unlockAndRun(go) else go()
    }
}

/** Demande à Android d'ajouter la tuile (Android 13 et plus). */
class QuickTileChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "add") return result.notImplemented()
        if (Build.VERSION.SDK_INT < 33) return result.success("manual")
        try {
            val sbm = context.getSystemService(StatusBarManager::class.java) ?: return result.success("manual")
            sbm.requestAddTileService(
                ComponentName(context, QuickTile::class.java),
                "ShiftLink",
                Icon.createWithResource(context, R.drawable.ic_tile),
                context.mainExecutor,
            ) { code ->
                result.success(
                    when (code) {
                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> "already"
                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> "refused"
                        else -> "manual"
                    }
                )
            }
        } catch (_: Exception) {
            result.success("manual")
        }
    }
}
