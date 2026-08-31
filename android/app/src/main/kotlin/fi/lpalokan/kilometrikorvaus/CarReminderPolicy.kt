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
 *  - the car is still moving. A head unit drops the link for reasons that
 *    have nothing to do with the ignition, and "Päättyikö ajo?" at 100 km/h
 *    is the same false prompt the app's own movement gate exists to prevent
 *    — so the same evidence gates this, mirrored across by the app.
 */
object CarReminderPolicy {

    /**
     * How recently the vehicle must have been measured at driving speed for
     * a disconnect to be read as interference rather than an arrival.
     *
     * Deliberately far shorter than the app's own five-minute movement
     * window. That window answers "has this trip been moving lately?" for a
     * poll that runs blind every five minutes; this answers "is the car
     * rolling *right now*?" at the instant the link dropped, and the two
     * cases it has to separate are seconds apart in evidence: a dropout
     * mid-drive leaves a fix from moments ago, while parking, stopping and
     * killing the ignition puts a good deal more than this between the last
     * fast fix and the disconnect.
     */
    const val MOVING_RECENCY_MS = 45_000L

    /**
     * [connected] is true for ACTION_ACL_CONNECTED and false for
     * ACTION_ACL_DISCONNECTED; [dayOfWeek] is a [Calendar.DAY_OF_WEEK] value
     * in the device's own time zone. [millisSinceDrivingEvidence] is how long
     * ago the app last saw the vehicle at driving speed, or null when it has
     * nothing to offer — no location permission, no fix yet, or a build with
     * GPS unavailable. Null keeps the old behaviour rather than silencing the
     * reminder: a missing signal must not cost the driver a prompt.
     *
     * Null means "say nothing".
     */
    fun reminderFor(
        connected: Boolean,
        tripActive: Boolean,
        dayOfWeek: Int,
        millisSinceDrivingEvidence: Long? = null,
    ): CarReminder? {
        if (!isWorkday(dayOfWeek)) return null
        return when {
            connected && !tripActive -> CarReminder.START
            !connected && tripActive ->
                if (isStillMoving(millisSinceDrivingEvidence)) null else CarReminder.STOP
            else -> null
        }
    }

    /**
     * Whether the vehicle was moving too recently for this disconnect to be
     * an arrival.
     *
     * A negative age — a mirrored timestamp in the future, which means the
     * clock moved, not the car — is not treated as evidence of movement: the
     * standing rule here is that a prompt the driver does not need beats a
     * missing one they do.
     */
    fun isStillMoving(millisSinceDrivingEvidence: Long?): Boolean =
        millisSinceDrivingEvidence != null &&
            millisSinceDrivingEvidence >= 0L &&
            millisSinceDrivingEvidence < MOVING_RECENCY_MS

    /** Mon–Fri in the device's local time, which is the driver's own week. */
    fun isWorkday(dayOfWeek: Int): Boolean =
        dayOfWeek != Calendar.SATURDAY && dayOfWeek != Calendar.SUNDAY
}
