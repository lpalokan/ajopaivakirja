package fi.lpalokan.kilometrikorvaus

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.util.Calendar

/**
 * Reminds the driver to start or stop the trip log when the car's Bluetooth
 * connects or disconnects.
 *
 * Most cars pair when the ignition comes on and drop the link when it goes
 * off, which makes this a better start-of-drive signal than anything the app
 * can infer — and a perfectly timed one, because the driver is sitting in
 * front of the odometer at exactly that moment.
 *
 * Declared in the manifest rather than registered at runtime, on purpose:
 * ACTION_ACL_CONNECTED / ACTION_ACL_DISCONNECTED are on Android's exemption
 * list for the API 26+ implicit-broadcast restrictions, so the system starts
 * this process to deliver them even when the app is not running. That is the
 * whole reason this feature is possible where GPS auto-detection was not: no
 * service, no wake lock, no GNSS, nothing running between rides.
 *
 * The notification is posted from here rather than through
 * flutter_local_notifications because when the car connects there may be no
 * Flutter engine at all. Tapping it opens the app, where "Aloita ajo" and
 * "Olen perillä" already live.
 *
 * Whether a prompt is worth showing is [CarReminderPolicy]'s call — it holds
 * the whole of the judgement (already started, already finished, weekend) in
 * one Android-free place, because none of this file can be exercised from the
 * test suite: an emulator has no Bluetooth to connect.
 */
class CarBluetoothReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val watched = BluetoothTriggerStore.triggerAddress(context) ?: return

        val device: BluetoothDevice? = intentDevice(intent)
        val address = device?.address ?: return
        if (!address.equals(watched, ignoreCase = true)) return

        val connected = when (action) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> true
            BluetoothDevice.ACTION_ACL_DISCONNECTED -> false
            else -> return
        }

        val reminder = CarReminderPolicy.reminderFor(
            connected = connected,
            tripActive = BluetoothTriggerStore.isTripActive(context),
            dayOfWeek = Calendar.getInstance().get(Calendar.DAY_OF_WEEK),
        ) ?: return

        when (reminder) {
            CarReminder.START -> notify(
                context,
                CONNECTED_NOTIFICATION_ID,
                context.getString(R.string.bt_start_title),
                context.getString(R.string.bt_start_text),
            )
            CarReminder.STOP -> notify(
                context,
                DISCONNECTED_NOTIFICATION_ID,
                context.getString(R.string.bt_stop_title),
                context.getString(R.string.bt_stop_text),
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun intentDevice(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
        }

    private fun notify(context: Context, id: Int, title: String, text: String) {
        // POST_NOTIFICATIONS is asked for by the app itself on first run; if
        // the driver has since revoked it there is nothing to do but skip —
        // notify() would throw.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ensureChannel(context)

        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            id,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        NotificationManagerCompat.from(context).notify(id, notification)
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.bt_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.bt_channel_description)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "kilometrikorvaus_bluetooth"

        // Distinct from the ids NotificationService owns (1–3), so a driving
        // reminder and an arrival reminder never overwrite each other.
        const val CONNECTED_NOTIFICATION_ID = 11
        const val DISCONNECTED_NOTIFICATION_ID = 12
    }
}
