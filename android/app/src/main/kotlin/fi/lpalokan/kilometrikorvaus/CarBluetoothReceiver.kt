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

        // A link that drops and comes straight back was interference, not the
        // ignition. The movement gate below should have stopped the prompt
        // going out at all, but it only has the evidence the app managed to
        // mirror — so if one did get posted, the reconnection is the proof it
        // was wrong, and it goes now rather than sitting in the shade.
        if (connected) {
            NotificationManagerCompat.from(context)
                .cancel(DISCONNECTED_NOTIFICATION_ID)
        }

        val evidenceAt = BluetoothTriggerStore.drivingEvidenceAt(context)
        val reminder = CarReminderPolicy.reminderFor(
            connected = connected,
            tripActive = BluetoothTriggerStore.isTripActive(context),
            dayOfWeek = Calendar.getInstance().get(Calendar.DAY_OF_WEEK),
            millisSinceDrivingEvidence =
                if (evidenceAt <= 0L) null else System.currentTimeMillis() - evidenceAt,
        ) ?: return

        when (reminder) {
            CarReminder.START -> notify(
                context,
                CONNECTED_NOTIFICATION_ID,
                context.getString(R.string.bt_start_title),
                context.getString(R.string.bt_start_text),
                context.getString(R.string.bt_start_action),
                ACTION_LOG_START,
            )
            CarReminder.STOP -> {
                // One "have you arrived?" at a time. The app's own
                // "Oletko perillä?" asks the same question from the other
                // side of the same evidence, and two notifications for one
                // question is the nagging the driver learns to swipe away.
                // Its scheduled backstop goes too: that only ever fires when
                // the process died mid-trip, which is exactly the case where
                // this receiver is the one still standing.
                NotificationManagerCompat.from(context).apply {
                    cancel(APP_ARRIVAL_REMINDER_ID)
                    cancel(APP_SCHEDULED_REMINDER_ID)
                }
                notify(
                    context,
                    DISCONNECTED_NOTIFICATION_ID,
                    context.getString(R.string.bt_stop_title),
                    context.getString(R.string.bt_stop_text),
                    context.getString(R.string.bt_stop_action),
                    ACTION_LOG_END,
                )
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun intentDevice(intent: Intent): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
        }

    private fun notify(
        context: Context,
        id: Int,
        title: String,
        text: String,
        actionLabel: String,
        action: String,
    ) {
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

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            // Body tap: just open the app, where the StartCard and the
            // active-trip card already are.
            .setContentIntent(openApp(context, id, null))
            // Button: go straight to the odometer. The whole reason this
            // trigger beats anything the app can infer is its timing — the
            // driver is sitting in front of the dash at the moment the car
            // connects or disconnects — and landing them on the home screen
            // to hunt for the field spends that advantage.
            .addAction(
                android.R.drawable.ic_menu_edit,
                actionLabel,
                openApp(context, id, action),
            )
            .build()

        NotificationManagerCompat.from(context).notify(id, notification)
    }

    /**
     * A PendingIntent that opens the app, optionally carrying the mileage
     * action [MainActivity] hands to Dart.
     *
     * The request code has to differ per (notification, action) pair:
     * FLAG_UPDATE_CURRENT rewrites the extras of any PendingIntent that
     * matches an existing one, and Intent equality ignores extras — so a
     * shared request code would leave the body tap and the button pointing at
     * whichever was built last.
     */
    private fun openApp(context: Context, id: Int, action: String?): PendingIntent {
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (action != null) putExtra(EXTRA_CAR_ACTION, action)
        }
        return PendingIntent.getActivity(
            context,
            if (action == null) id else id + ACTION_REQUEST_CODE_OFFSET,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
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

        /**
         * NotificationService.arrivalReminderId — the app's own
         * "Oletko perillä?". Named here so the stop prompt can take it down;
         * both are notifications of one app, so either side may cancel the
         * other's. Kept in step with the Dart constant of the same value.
         */
        const val APP_ARRIVAL_REMINDER_ID = 2

        /**
         * NotificationService.scheduledReminderId — the platform-scheduled
         * "Vieläkö ajat?" backstop, which is only ever on screen when the app
         * process died mid-trip.
         */
        const val APP_SCHEDULED_REMINDER_ID = 3

        /** Keeps the button's PendingIntent distinct from the body tap's. */
        private const val ACTION_REQUEST_CODE_OFFSET = 100

        /** Intent extra carrying the tapped button to [MainActivity]. */
        const val EXTRA_CAR_ACTION = "car_reminder_action"

        /** Matches BluetoothTriggerService.logStartAction on the Dart side. */
        const val ACTION_LOG_START = "log_start"

        /** Matches BluetoothTriggerService.logEndAction on the Dart side. */
        const val ACTION_LOG_END = "log_end"
    }
}
