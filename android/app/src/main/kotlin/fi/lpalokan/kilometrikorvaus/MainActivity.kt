package fi.lpalokan.kilometrikorvaus

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var pendingPermissionResult: MethodChannel.Result? = null

    /**
     * Serves the Bluetooth reminder settings: which devices the phone is
     * paired with, whether "Nearby devices" is granted, and which device the
     * driver picked. The reminder itself is [CarBluetoothReceiver]'s job and
     * never comes through here — by the time the car connects, this activity
     * usually does not exist.
     */
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(
                packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
            )

            "hasPermission" -> result.success(hasBluetoothPermission())

            "requestPermission" -> requestBluetoothPermission(result)

            "pairedDevices" -> result.success(pairedDevices())

            "triggerAddress" ->
                result.success(BluetoothTriggerStore.triggerAddress(this))

            "setTriggerAddress" -> {
                BluetoothTriggerStore.setTriggerAddress(
                    this,
                    call.argument<String>("address"),
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * BLUETOOTH_CONNECT is a runtime permission from Android 12; before that
     * the manifest's BLUETOOTH is granted at install time and there is
     * nothing to ask for.
     */
    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBluetoothPermission(result: MethodChannel.Result) {
        if (hasBluetoothPermission()) {
            result.success(true)
            return
        }
        // A second request while one is in flight would strand the first
        // result; answer it rather than leaving Dart waiting forever.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        pending.success(
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        )
    }

    /**
     * Pairing happens in Android's own settings; this only reads back what is
     * already paired so the driver can point at their car. Without
     * BLUETOOTH_CONNECT the platform returns nothing rather than throwing, but
     * the check keeps the empty list honest instead of looking like a phone
     * with no devices.
     */
    private fun pairedDevices(): List<Map<String, String>> {
        if (!hasBluetoothPermission()) return emptyList()
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = manager?.adapter ?: return emptyList()
        return try {
            (adapter.bondedDevices ?: emptySet()).map {
                mapOf("address" to it.address, "name" to (it.name ?: ""))
            }
        } catch (e: SecurityException) {
            // Revoked between the check and the call; an empty list is the
            // honest answer.
            emptyList()
        }
    }

    companion object {
        private const val CHANNEL = "fi.lpalokan.kilometrikorvaus/bluetooth_trigger"
        private const val PERMISSION_REQUEST_CODE = 4711
    }
}
