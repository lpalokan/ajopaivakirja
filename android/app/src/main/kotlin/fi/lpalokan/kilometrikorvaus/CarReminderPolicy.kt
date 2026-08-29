package fi.lpalokan.kilometrikorvaus

import java.util.Calendar

/** What the car's Bluetooth should prompt for, if anything. */
enum class CarReminder {
    /** "Aloititko ajon?" — the car connected and no trip is open. */
    START,

    /** "Päättyikö ajo?" — the car disconnected and a trip is still open. */
    STOP,
}

/**
 * Decides whether a car connect/disconnect is worth a notification.
 *
 * Kept free of every Android type on purpose: this is the whole of the
 * reminder's judgement, and [CarBluetoothReceiver] — which cannot be exercised
 * from the test suite, since there is no Bluetooth on an emulator — is left
 * with nothing but plumbing around it.
 *
 * Two things make a prompt noise rather than help:
 *
 *  - the driver already did it. Starting the car with a trip already running
 *    means they logged it before turning the key; shutting it off with no trip
 *    open means there is nothing to end. Either way the notification would ask
 *    for something already done.
 *  - it is the weekend. This is a work-mileage log, and a Saturday errand is
 *    not a työmatka. Prompting for one trains the driver to swipe the reminder
 *    away, which is how it comes to be ignored on the Monday that matters.
 */
object CarReminderPolicy {

    /**
     * [connected] is true for ACTION_ACL_CONNECTED and false for
     * ACTION_ACL_DISCONNECTED; [dayOfWeek] is a [Calendar.DAY_OF_WEEK] value
     * in the device's own time zone. Null means "say nothing".
     */
    fun reminderFor(connected: Boolean, tripActive: Boolean, dayOfWeek: Int): CarReminder? {
        if (!isWorkday(dayOfWeek)) return null
        return when {
            connected && !tripActive -> CarReminder.START
            !connected && tripActive -> CarReminder.STOP
            else -> null
        }
    }

    /** Mon–Fri in the device's local time, which is the driver's own week. */
    fun isWorkday(dayOfWeek: Int): Boolean =
        dayOfWeek != Calendar.SATURDAY && dayOfWeek != Calendar.SUNDAY
}
