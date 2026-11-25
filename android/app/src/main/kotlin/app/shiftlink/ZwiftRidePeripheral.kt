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
 * ShiftLink vu par Zwift comme une manette Zwift Ride (bêta). Protocole public :
 * poignée de main « RideOn » sans chiffrement, puis état des boutons en
 * notifications. Dart construit les messages ; ici on tient le serveur GATT.
 */
@SuppressLint("MissingPermission")
class ZwiftRidePeripheral(private val context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var server: BluetoothGattServer? = null
    private val chars = mutableMapOf<UUID, BluetoothGattCharacteristic>()
    private val subscribed = mutableMapOf<UUID, MutableSet<BluetoothDevice>>()
    private val connected = mutableSetOf<BluetoothDevice>()
    private var handshaken: BluetoothDevice? = null
    private val pendingServices = ArrayDeque<BluetoothGattService>()

    companion object {
        fun zwift(n: Int): UUID = UUID.fromString("0000000$n-19ca-4651-86e5-fa29dcdd09d1")
        fun sig(short: Int): UUID = UUID.fromString(String.format("0000%04x-0000-1000-8000-00805f9b34fb", short))
        val SERVICE: UUID = sig(0xFC82)
        val ASYNC: UUID = zwift(2)
        val SYNC_RX: UUID = zwift(3)
        val SYNC_TX: UUID = zwift(4)
        val CCCD: UUID = sig(0x2902)
        val RIDE_ON = "RideOn".toByteArray(Charsets.US_ASCII)
        const val MANUFACTURER_ZWIFT = 0x094A
        const val RIDE_LEFT: Byte = 8
        const val MAX_CLIENTS = 1
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> result.success(start())
                "stop" -> { stop(); result.success(null) }
                "send" -> { notify(ASYNC, call.argument<ByteArray>("data")!!); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("zwiftride", e.message, null)
        }
    }

    private fun characteristic(id: UUID, props: Int, perms: Int, value: ByteArray? = null): BluetoothGattCharacteristic {
        val c = BluetoothGattCharacteristic(id, props, perms)
        if (props and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) {
            c.addDescriptor(BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        }
        @Suppress("DEPRECATION")
        if (value != null) c.value = value
        chars[id] = c
        return c
    }

    private fun start(): Boolean {
        if (server != null) return true
        val adapter = manager.adapter ?: return false
        if (!adapter.isEnabled) return false
        val s = manager.openGattServer(context, callback) ?: return false
        server = s
        val read = BluetoothGattCharacteristic.PROPERTY_READ
        val pr = BluetoothGattCharacteristic.PERMISSION_READ
        val ride = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        ride.addCharacteristic(characteristic(ASYNC, BluetoothGattCharacteristic.PROPERTY_NOTIFY, 0))
        ride.addCharacteristic(
            characteristic(
                SYNC_RX,
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                BluetoothGattCharacteristic.PERMISSION_WRITE,
            )
        )
        ride.addCharacteristic(characteristic(SYNC_TX, read or BluetoothGattCharacteristic.PROPERTY_INDICATE, pr))
        val info = BluetoothGattService(sig(0x180A), BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(characteristic(sig(0x2A29), read, pr, "ShiftLink".toByteArray()))
            addCharacteristic(characteristic(sig(0x2A27), read, pr, "A.0".toByteArray()))
            addCharacteristic(characteristic(sig(0x2A26), read, pr, "1.3.0".toByteArray()))
        }
        val battery = BluetoothGattService(sig(0x180F), BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(characteristic(sig(0x2A19), read or BluetoothGattCharacteristic.PROPERTY_NOTIFY, pr, byteArrayOf(100)))
        }
        pendingServices.clear()
        pendingServices.add(info)
        pendingServices.add(battery)
        s.addService(ride)
        return true
    }

    private fun advertise() {
        val adapter = manager.adapter ?: return
        val adv = adapter.bluetoothLeAdvertiser ?: return
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()
        // Comme une vraie Ride : type « poignée gauche » et deux octets d'adresse.
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(SERVICE))
            .addManufacturerData(MANUFACTURER_ZWIFT, byteArrayOf(RIDE_LEFT, 0x13, 0x37))
            .build()
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
        main.removeCallbacks(keepAlive)
        server?.close()
        server = null
        chars.clear()
        subscribed.clear()
        connected.clear()
        pendingServices.clear()
        handshaken = null
        queue.clear()
        sending = false
    }

    // Une notification à la fois, dans l'ordre (un relâchement perdu laisserait un bouton enfoncé).
    private class Pending(val id: UUID, val data: ByteArray)
    private val queue = ArrayDeque<Pending>()
    private var sending = false
    private val unstick = Runnable { sending = false; pump() }

    private fun notify(id: UUID, data: ByteArray) {
        if (server == null || subscribed[id].isNullOrEmpty()) return
        queue.addLast(Pending(id, data))
        pump()
    }

    private fun pump() {
        if (sending) return
        val s = server ?: return
        val p = queue.firstOrNull() ?: return
        val c = chars[p.id]
        val d = subscribed[p.id]?.firstOrNull()
        if (c == null || d == null) { queue.removeFirst(); pump(); return }
        val indicate = p.id == SYNC_TX
        val ok = try {
            if (Build.VERSION.SDK_INT >= 33) {
                s.notifyCharacteristicChanged(d, c, indicate, p.data) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                c.value = p.data
                @Suppress("DEPRECATION")
                s.notifyCharacteristicChanged(d, c, indicate)
            }
        } catch (_: Exception) {
            false
        }
        if (ok) queue.removeFirst()
        sending = true
        main.postDelayed(unstick, if (ok) 500 else 30)
    }

    // Une vraie Ride donne signe de vie régulièrement : aucun bouton appuyé, toutes les 5 s.
    private val keepAlive = object : Runnable {
        override fun run() {
            if (handshaken == null) return
            if (queue.isEmpty()) notify(ASYNC, byteArrayOf(0x23, 0x08, 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0x0F))
            main.postDelayed(this, 5000)
        }
    }

    private val callback = object : BluetoothGattServerCallback() {
        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post { main.removeCallbacks(unstick); sending = false; pump() }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            main.post {
                val next = pendingServices.removeFirstOrNull()
                if (next != null) server?.addService(next) else advertise()
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
                    subscribed.values.forEach { it.remove(device) }
                    if (handshaken == device) {
                        handshaken = null
                        main.removeCallbacks(keepAlive)
                        emit("client", mapOf("name" to null))
                    }
                }
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
                val on = subscribed[descriptor.characteristic.uuid]?.contains(device) == true
                val v = if (on) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, v)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            val id = descriptor.characteristic.uuid
            val on = value != null && value.isNotEmpty() && value[0].toInt() != 0
            main.post {
                val set = subscribed.getOrPut(id) { mutableSetOf() }
                if (on) set.add(device) else set.remove(device)
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            if (characteristic.uuid != SYNC_RX || value == null || value.isEmpty()) return
            main.post {
                if (device !in connected) return@post
                if (value.size >= RIDE_ON.size && value.copyOfRange(0, RIDE_ON.size).contentEquals(RIDE_ON)) {
                    // Poignée de main : on répond « RideOn », sans chiffrement.
                    notify(SYNC_TX, RIDE_ON)
                    if (handshaken != device) {
                        handshaken = device
                        emit("client", mapOf("name" to (device.name ?: device.address)))
                        main.removeCallbacks(keepAlive)
                        main.postDelayed(keepAlive, 5000)
                    }
                    notify(ASYNC, byteArrayOf(0x23, 0x08, 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0x0F))
                } else if (value[0].toInt() == 0x12) {
                    // Commande de vibration (même famille que les Zwift Play).
                    emit("haptic", emptyMap())
                }
            }
        }
    }

    private fun emit(event: String, args: Map<String, Any?>) {
        main.post { channel.invokeMethod(event, args) }
    }
}
