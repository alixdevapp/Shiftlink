package app.shiftlink

import android.app.Activity
import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.CyclingPedalingCadenceRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.PowerRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Length
import androidx.health.connect.client.units.Power
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId

/** Écrit les sorties de ShiftLink dans Health Connect (séance, puissance, cadence, cardio, distance). */
class HealthConnectChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val REQUEST = 4207
    }

    private val permissions = setOf(
        HealthPermission.getWritePermission(ExerciseSessionRecord::class),
        HealthPermission.getWritePermission(PowerRecord::class),
        HealthPermission.getWritePermission(CyclingPedalingCadenceRecord::class),
        HealthPermission.getWritePermission(HeartRateRecord::class),
        HealthPermission.getWritePermission(DistanceRecord::class),
    )
    private var pending: MethodChannel.Result? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    private fun client(): HealthConnectClient? =
        if (HealthConnectClient.getSdkStatus(activity) == HealthConnectClient.SDK_AVAILABLE) {
            HealthConnectClient.getOrCreate(activity)
        } else {
            null
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> result.success(client() != null)
            "request" -> request(result)
            "save" -> save(call, result)
            else -> result.notImplemented()
        }
    }

    private fun request(result: MethodChannel.Result) {
        val c = client()
        if (c == null) {
            result.success(false)
            return
        }
        scope.launch {
            try {
                val granted = c.permissionController.getGrantedPermissions()
                if (granted.containsAll(permissions)) {
                    result.success(true)
                    return@launch
                }
                pending?.success(false)
                pending = result
                val intent = PermissionController.createRequestPermissionResultContract().createIntent(activity, permissions)
                activity.startActivityForResult(intent, REQUEST)
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }

    /** À appeler depuis l'activité quand Health Connect rend la main. */
    fun onResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        val r = pending ?: return true
        pending = null
        val c = client()
        if (c == null) {
            r.success(false)
            return true
        }
        scope.launch {
            try {
                r.success(c.permissionController.getGrantedPermissions().containsAll(permissions))
            } catch (e: Exception) {
                r.success(false)
            }
        }
        return true
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        val c = client()
        if (c == null) {
            result.success(false)
            return
        }
        val start = Instant.ofEpochMilli((call.argument<Number>("start") ?: 0).toLong())
        val end = Instant.ofEpochMilli((call.argument<Number>("end") ?: 0).toLong())
        val distance = (call.argument<Number>("distance") ?: 0).toDouble()
        val times = (call.argument<List<Number>>("times") ?: emptyList()).map { Instant.ofEpochMilli(it.toLong()) }
        val power = call.argument<List<Number>>("power") ?: emptyList()
        val cadence = call.argument<List<Number>>("cadence") ?: emptyList()
        val hr = call.argument<List<Number>>("heartRate") ?: emptyList()
        val zone = ZoneId.systemDefault().rules.getOffset(start)
        fun meta() = Metadata.activelyRecorded(Device(type = Device.TYPE_PHONE))
        scope.launch {
            try {
                val records = mutableListOf<Record>(
                    ExerciseSessionRecord(
                        startTime = start, startZoneOffset = zone, endTime = end, endZoneOffset = zone,
                        exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY,
                        title = "ShiftLink", metadata = meta(),
                    ),
                )
                if (distance > 0) {
                    records += DistanceRecord(
                        startTime = start, startZoneOffset = zone, endTime = end, endZoneOffset = zone,
                        distance = Length.meters(distance), metadata = meta(),
                    )
                }
                val p = times.indices.filter { power.getOrNull(it)?.toInt() ?: -1 >= 0 }
                    .map { PowerRecord.Sample(times[it], Power.watts(power[it].toDouble())) }
                if (p.isNotEmpty()) {
                    records += PowerRecord(start, zone, end, zone, p, meta())
                }
                val cad = times.indices.filter { cadence.getOrNull(it)?.toInt() ?: -1 >= 0 }
                    .map { CyclingPedalingCadenceRecord.Sample(times[it], cadence[it].toDouble()) }
                if (cad.isNotEmpty()) {
                    records += CyclingPedalingCadenceRecord(start, zone, end, zone, cad, meta())
                }
                val beats = times.indices.filter { (hr.getOrNull(it)?.toInt() ?: -1) > 0 }
                    .map { HeartRateRecord.Sample(times[it], hr[it].toLong()) }
                if (beats.isNotEmpty()) {
                    records += HeartRateRecord(start, zone, end, zone, beats, meta())
                }
                withContext(Dispatchers.IO) { c.insertRecords(records) }
                result.success(true)
            } catch (e: Exception) {
                result.success(false)
            }
        }
    }
}

/** Envoie un Intent à chaque action d'une manette, pour Tasker, MacroDroid… */
class IntentChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "send") {
            result.notImplemented()
            return
        }
        val intent = Intent("app.shiftlink.ACTION").apply {
            putExtra("action", call.argument<String>("action"))
            putExtra("button", call.argument<String>("button"))
            putExtra("gesture", call.argument<String>("gesture"))
            putExtra("device", call.argument<String>("device"))
        }
        activity.applicationContext.sendBroadcast(intent)
        result.success(true)
    }
}
