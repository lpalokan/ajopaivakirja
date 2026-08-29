package fi.lpalokan.kilometrikorvaus

import android.content.Context
import android.content.SharedPreferences

/**
 * Where the driver's chosen car lives, and whether a trip is open.
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
    private const val KEY_TRIP_ACTIVE = "trip_active"

    /** The MAC address whose connect/disconnect prompts, or null when off. */
    fun triggerAddress(context: Context): String? =
        prefs(context).getString(KEY_ADDRESS, null)?.takeIf { it.isNotBlank() }

    /** Pass null to switch the reminders off. */
    fun setTriggerAddress(context: Context, address: String?) {
        val edit = prefs(context).edit()
        if (address.isNullOrBlank()) edit.remove(KEY_ADDRESS)
        else edit.putString(KEY_ADDRESS, address)
        edit.apply()
    }

    /**
     * Whether the app currently has a trip open. Mirrored here by Dart on
     * every start, arrival, cancel and load, because the receiver has no way
     * to ask. Defaults to false: a phone that has never run the app, or one
     * whose flag was lost, is better off prompting a start it does not need
     * than silently skipping one it does.
     */
    fun isTripActive(context: Context): Boolean =
        prefs(context).getBoolean(KEY_TRIP_ACTIVE, false)

    fun setTripActive(context: Context, active: Boolean) {
        prefs(context).edit().putBoolean(KEY_TRIP_ACTIVE, active).apply()
    }

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
}
