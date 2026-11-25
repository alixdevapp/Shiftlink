package app.shiftlink

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var health: HealthConnectChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/hid")
        channel.setMethodCallHandler(HidKeyboard(this, channel))
        val taps = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/taps")
        taps.setMethodCallHandler(ScreenTapsChannel(applicationContext, taps))
        val ftms = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/ftms")
        ftms.setMethodCallHandler(FtmsPeripheral(applicationContext, ftms))
        val obc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/obc")
        obc.setMethodCallHandler(ObcPeripheral(applicationContext, obc))
        val ride = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/zwiftride")
        ride.setMethodCallHandler(ZwiftRidePeripheral(applicationContext, ride))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/apps")
            .setMethodCallHandler(InstalledApps(applicationContext))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/sound").setMethodCallHandler(Sounds())
        health = HealthConnectChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/health").setMethodCallHandler(health)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/intent")
            .setMethodCallHandler(IntentChannel(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/voice").setMethodCallHandler(Voice(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/tile")
            .setMethodCallHandler(QuickTileChannel(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shiftlink/update")
            .setMethodCallHandler(AppUpdater(this))
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (health?.onResult(requestCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
