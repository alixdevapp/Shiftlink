package app.shiftlink

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * ShiftLink vu comme une manette OpenBikeControl en Bluetooth (protocole ouvert,
 * https://openbikecontrol.org/ble). Les applis (Grimpa, applis web en Bluetooth…)
 * s'abonnent à l'état des boutons et peuvent demander une vibration.
 */
@SuppressLint("MissingPermission")
class ObcPeripheral(private val context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var server: BluetoothGattServer? = null
    private var buttonChar: BluetoothGattCharacteristic? = null
    private val subscribed = mutableSetOf<BluetoothDevice>()
    private val connected = mutableSetOf<BluetoothDevice>()

    companion object {
        val SERVICE: UUID = UUID.fromString("d273f680-d548-419d-b9d1-fa0472345229")
        val BUTTON_STATE: UUID = UUID.fromString("d273f681-d548-419d-b9d1-fa0472345229")
        val HAPTIC: UUID = UUID.fromString("d273f682-d548-419d-b9d1-fa0472345229")
        val APP_INFO: UUID = UUID.fromString("d273f683-d548-419d-b9d1-fa0472345229")
        fun sig(short: Int): UUID = UUID.fromString(String.format("0000%04x-0000-1000-8000-00805f9b34fb", short))
        val CCCD: UUID = sig(0x2902)
        val DEVICE_INFO: UUID = sig(0x180A)
        const val MAX_CLIENTS = 1
        const val MAX_WRITE = 100
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> result.success(start(call.argument<String>("version") ?: "1"))
                "stop" -> { stop(); result.success(null) }
                "send" -> {
                    send(call.argument<ByteArray>("data")!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("obc", e.message, null)
        }
    }

    private fun readOnly(id: Int, text: String): BluetoothGattCharacteristic {
        val c = BluetoothGattCharacteristic(sig(id), BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ)
        @Suppress("DEPRECATION")
        c.value = text.toByteArray(Charsets.UTF_8)
        return c
    }

    private fun start(version: String): Boolean {
        if (server != null) return true
        val adapter = manager.adapter ?: return false
        if (!adapter.isEnabled) return false
        val s = manager.openGattServer(context, callback) ?: return false
        server = s
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val buttons = BluetoothGattCharacteristic(
            BUTTON_STATE,
            BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ,
        )
        buttons.addDescriptor(BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        @Suppress("DEPRECATION")
        buttons.value = byteArrayOf(0x01)
        buttonChar = buttons
        service.addCharacteristic(buttons)
        val write = BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        service.addCharacteristic(BluetoothGattCharacteristic(HAPTIC, write, BluetoothGattCharacteristic.PERMISSION_WRITE))
        service.addCharacteristic(BluetoothGattCharacteristic(APP_INFO, write, BluetoothGattCharacteristic.PERMISSION_WRITE))
        s.addService(service)
        pendingInfo = BluetoothGattService(DEVICE_INFO, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(readOnly(0x2A29, "ShiftLink"))
            addCharacteristic(readOnly(0x2A24, "ShiftLink"))
            addCharacteristic(readOnly(0x2A25, (adapter.name ?: "ShiftLink").take(20)))
            addCharacteristic(readOnly(0x2A27, "Android"))
            addCharacteristic(readOnly(0x2A26, version))
        }
        return true
    }

    // Android n'ajoute qu'un service à la fois : celui-ci part après le premier.
    private var pendingInfo: BluetoothGattService? = null

    private fun advertise() {
        val adv = manager.adapter?.bluetoothLeAdvertiser ?: return
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()
        val data = AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).build()
        val scan = AdvertiseData.Builder().setIncludeDeviceName(true).build()
        try {
            adv.startAdvertising(settings, data, scan, advertiseCallback)
        } catch (e: Exception) {
            emit("log", mapOf("message" to "annonce Bluetooth impossible : ${e.message}"))
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartFailure(errorCode: Int) {
            emit("log", mapOf("message" to "annonce Bluetooth refusée (code $errorCode)"))
        }
    }

    private fun stop() {
        try {
            manager.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) {}
        server?.close()
        server = null
        buttonChar = null
        pendingInfo = null
        subscribed.clear()
        connected.clear()
        queue.clear()
        main.removeCallbacks(unstick)
        sending = false
    }

    // Les boutons partent dans l'ordre, un à la fois (Android perd les autres) :
    // un relâchement perdu laisserait un bouton enfoncé dans l'appli.
    private val queue = ArrayDeque<ByteArray>()
    private var sending = false
    private val unstick = Runnable { sending = false; pump() }

    private fun send(data: ByteArray) {
        if (server == null || subscribed.isEmpty()) return
        queue.addLast(data)
        pump()
    }

    private fun pump() {
        if (sending) return
        val s = server ?: run { queue.clear(); return }
        val c = buttonChar ?: return
        val d = subscribed.firstOrNull() ?: run { queue.clear(); return }
        if (queue.isEmpty()) return
        val data = queue.first()
        val ok = try {
            if (Build.VERSION.SDK_INT >= 33) {
                s.notifyCharacteristicChanged(d, c, false, data) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                c.value = data
                @Suppress("DEPRECATION")
                s.notifyCharacteristicChanged(d, c, false)
            }
        } catch (_: Exception) {
            false
        }
        if (ok) queue.removeFirst()
        sending = true
        main.postDelayed(unstick, if (ok) 500 else 30)
    }

    private val callback = object : BluetoothGattServerCallback() {
        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                main.removeCallbacks(unstick)
                sending = false
                pump()
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            main.post {
                val next = pendingInfo
                if (next != null) {
                    pendingInfo = null
                    server?.addService(next)
                } else if (status == BluetoothGatt.GATT_SUCCESS) {
                    advertise()
                }
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (connected.size >= MAX_CLIENTS && device !in connected) {
                        server?.cancelConnection(device)
                        return@post
                    }
                    connected.add(device)
                } else {
                    connected.remove(device)
                    subscribed.remove(device)
                }
                emit("client", mapOf("name" to (connected.firstOrNull()?.let { it.name ?: it.address })))
            }
        }

        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val v = characteristic.value ?: ByteArray(0)
            val part = if (offset < v.size) v.copyOfRange(offset, v.size) else ByteArray(0)
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, part)
        }

        override fun onDescriptorReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor) {
            main.post {
                val v = if (device in subscribed) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, v)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            val on = value != null && value.isNotEmpty() && value[0].toInt() != 0
            main.post { if (on) subscribed.add(device) else subscribed.remove(device) }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            val known = characteristic.uuid == HAPTIC || characteristic.uuid == APP_INFO
            val valid = known && value != null && value.isNotEmpty() && value.size <= MAX_WRITE
            val status = if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH
            if (responseNeeded) server?.sendResponse(device, requestId, status, 0, null)
            if (!valid || value == null) return
            main.post {
                if (device !in connected) return@post
                channel.invokeMethod("received", value)
            }
        }
    }

    private fun emit(event: String, args: Map<String, Any?>) {
        main.post { channel.invokeMethod(event, args) }
    }
}
