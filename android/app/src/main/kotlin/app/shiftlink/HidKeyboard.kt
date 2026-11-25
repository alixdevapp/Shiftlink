package app.shiftlink

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * ShiftLink se présente comme un clavier Bluetooth (profil HID) auprès d'un
 * ordinateur ou d'une tablette, pour envoyer les touches de changement de
 * vitesse à Rouvy ou TrainingPeaks Virtual.
 */
@SuppressLint("MissingPermission")
class HidKeyboard(private val activity: Activity, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val context: Context = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private var hid: BluetoothHidDevice? = null
    private var registered = false
    private var host: BluetoothDevice? = null
    private var pendingConnect: String? = null

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, isRegistered: Boolean) {
            registered = isRegistered
            emit("status", mapOf("registered" to isRegistered))
            if (isRegistered) {
                val target = pendingConnect
                pendingConnect = null
                when {
                    target != null -> connectTo(target)
                    pluggedDevice != null -> hid?.connect(pluggedDevice)
                }
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> host = device
                BluetoothProfile.STATE_DISCONNECTED -> if (host?.address == device.address) host = null
            }
            emit(
                "connection",
                mapOf(
                    "address" to device.address,
                    "name" to (device.name ?: device.address),
                    "state" to when (state) {
                        BluetoothProfile.STATE_CONNECTED -> "connected"
                        BluetoothProfile.STATE_CONNECTING -> "connecting"
                        else -> "disconnected"
                    },
                ),
            )
        }
    }

    private fun emit(method: String, args: Any?) = main.post { channel.invokeMethod(method, args) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && adapter != null)
                "start" -> {
                    start(call.argument<String>("address"))
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "bondedDevices" -> result.success(
                    adapter?.bondedDevices?.map { mapOf("address" to it.address, "name" to (it.name ?: it.address)) }
                        ?: emptyList<Map<String, String>>(),
                )
                "connect" -> {
                    connectTo(call.argument<String>("address")!!)
                    result.success(null)
                }
                "makeDiscoverable" -> {
                    val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                        .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 120)
                    activity.startActivity(intent)
                    result.success(null)
                }
                "pressKey" -> result.success(pressKey(call.argument<Int>("usage")!!, call.argument<Int>("modifier") ?: 0))
                "keyDown" -> result.success(keyDown(call.argument<Int>("usage")!!, call.argument<Int>("modifier") ?: 0))
                "keyUp" -> result.success(keyUp())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("hid", e.message, null)
        }
    }

    private fun start(address: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        pendingConnect = address
        if (hid != null) {
            if (registered && address != null) connectTo(address)
            return
        }
        adapter?.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
                if (profile != BluetoothProfile.HID_DEVICE) return
                hid = proxy as BluetoothHidDevice
                val sdp = BluetoothHidDeviceAppSdpSettings(
                    "ShiftLink",
                    "Clavier de changement de vitesse",
                    "ShiftLink",
                    BluetoothHidDevice.SUBCLASS1_KEYBOARD,
                    KEYBOARD_DESCRIPTOR,
                )
                hid?.registerApp(sdp, null, null, Executors.newSingleThreadExecutor(), callback)
            }

            override fun onServiceDisconnected(profile: Int) {
                hid = null
                registered = false
                emit("status", mapOf("registered" to false))
            }
        }, BluetoothProfile.HID_DEVICE)
    }

    private fun connectTo(address: String) {
        val device = adapter?.getRemoteDevice(address) ?: return
        hid?.connect(device)
    }

    private fun stop() {
        host?.let { hid?.disconnect(it) }
        hid?.unregisterApp()
        hid?.let { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it) }
        hid = null
        host = null
        registered = false
    }

    private fun pressKey(usage: Int, modifier: Int): Boolean {
        val h = hid ?: return false
        val d = host ?: return false
        val down = byteArrayOf(modifier.toByte(), 0, usage.toByte(), 0, 0, 0, 0, 0)
        val up = ByteArray(8)
        val ok = h.sendReport(d, REPORT_ID, down)
        main.postDelayed({ h.sendReport(d, REPORT_ID, up) }, 50) // 50 ms : les jeux qui lisent le clavier une fois par image ne ratent pas l’appui
        return ok
    }

    /** Touche maintenue (direction) jusqu'à keyUp. */
    private fun keyDown(usage: Int, modifier: Int): Boolean {
        val h = hid ?: return false
        val d = host ?: return false
        return h.sendReport(d, REPORT_ID, byteArrayOf(modifier.toByte(), 0, usage.toByte(), 0, 0, 0, 0, 0))
    }

    private fun keyUp(): Boolean {
        val h = hid ?: return false
        val d = host ?: return false
        return h.sendReport(d, REPORT_ID, ByteArray(8))
    }

    companion object {
        private const val REPORT_ID = 1

        // Descripteur HID d'un clavier standard (rapport n° 1, 8 octets).
        private val KEYBOARD_DESCRIPTOR = byteArrayOf(
            0x05, 0x01, // Usage Page (Generic Desktop)
            0x09, 0x06, // Usage (Keyboard)
            0xA1.toByte(), 0x01, // Collection (Application)
            0x85.toByte(), REPORT_ID.toByte(), // Report ID
            0x05, 0x07, // Usage Page (Key Codes)
            0x19, 0xE0.toByte(), 0x29, 0xE7.toByte(), // Modifiers
            0x15, 0x00, 0x25, 0x01,
            0x75, 0x01, 0x95.toByte(), 0x08,
            0x81.toByte(), 0x02, // Input (Data, Variable, Absolute)
            0x95.toByte(), 0x01, 0x75, 0x08,
            0x81.toByte(), 0x01, // Input (Constant) : octet réservé
            0x95.toByte(), 0x06, 0x75, 0x08,
            0x15, 0x00, 0x25, 0x65,
            0x05, 0x07, 0x19, 0x00, 0x29, 0x65,
            0x81.toByte(), 0x00, // Input (Data, Array) : 6 touches
            0xC0.toByte(), // End Collection
        )
    }
}
