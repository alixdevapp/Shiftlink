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
 * ShiftLink se présente comme un home trainer Bluetooth (FTMS, norme publique)
 * auprès de l'appli d'entraînement. Les commandes de l'appli remontent à Dart,
 * qui applique les vitesses virtuelles et pilote le vrai trainer.
 */
@SuppressLint("MissingPermission")
class FtmsPeripheral(private val context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var server: BluetoothGattServer? = null
    private val chars = mutableMapOf<Int, BluetoothGattCharacteristic>()
    private val subscribed = mutableMapOf<Int, MutableSet<BluetoothDevice>>()
    private val connected = mutableSetOf<BluetoothDevice>()
    private var advertising = false

    companion object {
        fun uuid(short: Int): UUID = UUID.fromString(String.format("0000%04x-0000-1000-8000-00805f9b34fb", short))
        val CCCD: UUID = uuid(0x2902)
        const val SERVICE = 0x1826
        const val FEATURE = 0x2ACC
        const val BIKE_DATA = 0x2AD2
        const val TRAINING_STATUS = 0x2AD3
        const val RESISTANCE_RANGE = 0x2AD6
        const val POWER_RANGE = 0x2AD8
        const val CONTROL_POINT = 0x2AD9
        const val MACHINE_STATUS = 0x2ADA

        // Une seule appli d'entraînement à la fois : un voisin ne peut pas prendre la main.
        const val MAX_CLIENTS = 1

        // Les commandes FTMS tiennent en quelques octets.
        const val MAX_COMMAND = 20
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> result.success(start())
                "stop" -> { stop(); result.success(null) }
                "notify" -> {
                    val id = call.argument<Int>("uuid")!!
                    val data = call.argument<ByteArray>("data")!!
                    notify(id, data)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ftms", e.message, null)
        }
    }

    private fun characteristic(id: Int, props: Int, value: ByteArray? = null): BluetoothGattCharacteristic {
        val perms = (if (props and BluetoothGattCharacteristic.PROPERTY_READ != 0) BluetoothGattCharacteristic.PERMISSION_READ else 0) or
            (if (props and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) BluetoothGattCharacteristic.PERMISSION_WRITE else 0)
        val c = BluetoothGattCharacteristic(uuid(id), props, perms)
        if (props and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0) {
            c.addDescriptor(
                BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE)
            )
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
        val service = BluetoothGattService(uuid(SERVICE), BluetoothGattService.SERVICE_TYPE_PRIMARY)
        val r = BluetoothGattCharacteristic.PROPERTY_READ
        val n = BluetoothGattCharacteristic.PROPERTY_NOTIFY
        // Fonctions : cadence, cardio, puissance. Réglages : résistance, puissance, simulation.
        service.addCharacteristic(characteristic(FEATURE, r, byteArrayOf(0x02, 0x44, 0, 0, 0x0C, 0x20, 0, 0)))
        service.addCharacteristic(characteristic(BIKE_DATA, n))
        service.addCharacteristic(characteristic(TRAINING_STATUS, r or n, byteArrayOf(0x00, 0x01)))
        service.addCharacteristic(characteristic(RESISTANCE_RANGE, r, byteArrayOf(0, 0, 0xE8.toByte(), 0x03, 0x01, 0)))
        service.addCharacteristic(characteristic(POWER_RANGE, r, byteArrayOf(0, 0, 0xD0.toByte(), 0x07, 0x01, 0)))
        service.addCharacteristic(
            characteristic(CONTROL_POINT, BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_INDICATE)
        )
        service.addCharacteristic(characteristic(MACHINE_STATUS, n))
        s.addService(service)
        return true
    }

    private fun advertise() {
        val adv = manager.adapter?.bluetoothLeAdvertiser ?: return
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()
        // Données de service FTMS : machine disponible, type vélo d'intérieur.
        val data = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(uuid(SERVICE)))
            .addServiceData(ParcelUuid(uuid(SERVICE)), byteArrayOf(0x01, 0x20, 0x00))
            .build()
        val scan = AdvertiseData.Builder().setIncludeDeviceName(true).build()
        try {
            adv.startAdvertising(settings, data, scan, advertiseCallback)
        } catch (e: Exception) {
            emit("log", mapOf("message" to "annonce Bluetooth impossible : ${e.message}"))
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            advertising = true
        }

        override fun onStartFailure(errorCode: Int) {
            advertising = false
            emit("log", mapOf("message" to "annonce Bluetooth refusée (code $errorCode)"))
        }
    }

    private fun stop() {
        try {
            manager.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        } catch (_: Exception) {}
        advertising = false
        server?.close()
        server = null
        chars.clear()
        subscribed.clear()
        connected.clear()
        queue.clear()
        main.removeCallbacks(unstick)
        sending = false
    }

    /** Notification en attente. Une seule part à la fois (Android perd les autres) ;
     *  la suivante attend onNotificationSent. */
    private class Pending(val id: Int, val data: ByteArray, var tries: Int = 0)

    private val queue = ArrayDeque<Pending>()
    private var sending = false
    private val unstick = Runnable { sending = false; pump() }

    /** Réponses au control point d'abord (l'appli attend l'accusé), puis les données :
     *  pour une donnée, seule la plus récente compte. */
    private fun notify(id: Int, data: ByteArray) {
        if (server == null || chars[id] == null || subscribed[id].isNullOrEmpty()) return
        if (id == CONTROL_POINT) {
            val lastAnswer = queue.indexOfLast { it.id == CONTROL_POINT }
            queue.add(lastAnswer + 1, Pending(id, data))
        } else {
            val i = queue.indexOfFirst { it.id == id }
            if (i >= 0) queue[i] = Pending(id, data) else queue.addLast(Pending(id, data))
        }
        pump()
    }

    private fun pump() {
        if (sending) return
        val s = server ?: run { queue.clear(); return }
        while (queue.isNotEmpty()) {
            val p = queue.first()
            val c = chars[p.id]
            val d = subscribed[p.id]?.firstOrNull()
            if (c == null || d == null) { queue.removeFirst(); continue }
            val ok = try {
                if (Build.VERSION.SDK_INT >= 33) {
                    s.notifyCharacteristicChanged(d, c, p.id == CONTROL_POINT, p.data) == BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    c.value = p.data
                    @Suppress("DEPRECATION")
                    s.notifyCharacteristicChanged(d, c, p.id == CONTROL_POINT)
                }
            } catch (_: Exception) {
                false
            }
            if (ok) {
                queue.removeFirst()
                sending = true
                // Sans nouvelles de la pile Bluetooth, on repart quand même.
                main.postDelayed(unstick, 500)
                return
            }
            // Pile occupée : on réessaie un peu plus tard (une réponse, jusqu'à 5 fois).
            p.tries++
            if (p.id != CONTROL_POINT || p.tries >= 5) queue.removeFirst()
            if (queue.isNotEmpty()) {
                sending = true
                main.postDelayed(unstick, 30)
            }
            return
        }
    }

    private fun shortId(u: UUID): Int = ((u.mostSignificantBits ushr 32) and 0xFFFF).toInt()

    private val callback = object : BluetoothGattServerCallback() {
        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                main.removeCallbacks(unstick)
                sending = false
                pump()
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            if (status == BluetoothGatt.GATT_SUCCESS) main.post { advertise() }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (connected.size >= MAX_CLIENTS && device !in connected) {
                        server?.cancelConnection(device)
                        emit("log", mapOf("message" to "connexion refusée : une appli est déjà connectée"))
                        return@post
                    }
                    connected.add(device)
                } else {
                    connected.remove(device)
                    subscribed.values.forEach { it.remove(device) }
                }
                emit(
                    "client",
                    mapOf("name" to (connected.firstOrNull()?.let { it.name ?: it.address }), "count" to connected.size)
                )
            }
        }

        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val v = characteristic.value ?: ByteArray(0)
            val part = if (offset < v.size) v.copyOfRange(offset, v.size) else ByteArray(0)
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, part)
        }

        override fun onDescriptorReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor) {
            val id = shortId(descriptor.characteristic.uuid)
            main.post {
                val on = subscribed[id]?.contains(device) == true
                val v = if (on) BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, v)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?
        ) {
            val id = shortId(descriptor.characteristic.uuid)
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
            val id = shortId(characteristic.uuid)
            val valid = id == CONTROL_POINT && value != null && value.isNotEmpty() && value.size <= MAX_COMMAND
            val status = if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH
            if (responseNeeded) server?.sendResponse(device, requestId, status, 0, null)
            val command = value
            if (!valid || command == null) return
            main.post {
                if (device !in connected) return@post
                channel.invokeMethod("controlPoint", command, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val response = result as? ByteArray ?: return
                        notify(CONTROL_POINT, response)
                    }

                    override fun error(code: String, msg: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
            }
        }
    }

    private fun emit(event: String, args: Map<String, Any?>) {
        main.post { channel.invokeMethod(event, args) }
    }
}
