package fi.lpalokan.kilometrikorvaus

import android.content.Context

/**
 * Where the driver's chosen car lives.
 *
 * Its own SharedPreferences file rather than the app's SQLite settings or the
 * `shared_preferences` plugin's store: [CarBluetoothReceiver] reads this with
 * no Flutter engine running and no database open, so it has to be something
 * plain Android can read on a cold start — and it must not depend on the
 * internal key format of a Dart plugin.
 */
object BluetoothTriggerStore {
    private const val FILE = "car_bluetooth_trigger"
    private const val KEY_ADDRESS = "trigger_address"

    /** The MAC address whose connect/disconnect prompts, or null when off. */
    fun triggerAddress(context: Context): String? =
        context.applicationContext
            .getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .getString(KEY_ADDRESS, null)
            ?.takeIf { it.isNotBlank() }

    /** Pass null to switch the reminders off. */
    fun setTriggerAddress(context: Context, address: String?) {
        val prefs = context.applicationContext
            .getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
        if (address.isNullOrBlank()) prefs.remove(KEY_ADDRESS)
        else prefs.putString(KEY_ADDRESS, address)
        prefs.apply()
    }
}
