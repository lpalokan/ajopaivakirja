package fi.lpalokan.kilometrikorvaus

import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * [CarReminderPolicy] is the whole of the car reminder's judgement, and the
 * receiver around it cannot be exercised at all — an emulator has no
 * Bluetooth to connect, which is why the Gherkin suite stops at the mirror.
 * These run on the JVM, where the policy's deliberate freedom from Android
 * types is what makes them possible.
 */
class CarReminderPolicyTest {

    private val monday = Calendar.MONDAY
    private val saturday = Calendar.SATURDAY
    private val sunday = Calendar.SUNDAY

    @Test
    fun `connecting with no trip open asks the driver to start one`() {
        assertEquals(
            CarReminder.START,
            CarReminderPolicy.reminderFor(
                connected = true,
                tripActive = false,
                dayOfWeek = monday,
            ),
        )
    }

    @Test
    fun `connecting with a trip already open says nothing`() {
        assertNull(
            CarReminderPolicy.reminderFor(
                connected = true,
                tripActive = true,
                dayOfWeek = monday,
            ),
        )
    }

    @Test
    fun `disconnecting with a trip open asks the driver to end it`() {
        assertEquals(
            CarReminder.STOP,
            CarReminderPolicy.reminderFor(
                connected = false,
                tripActive = true,
                dayOfWeek = monday,
            ),
        )
    }

    @Test
    fun `disconnecting with nothing open says nothing`() {
        assertNull(
            CarReminderPolicy.reminderFor(
                connected = false,
                tripActive = false,
                dayOfWeek = monday,
            ),
        )
    }

    @Test
    fun `the weekend is never a tyomatka`() {
        for (day in listOf(saturday, sunday)) {
            assertNull(
                CarReminderPolicy.reminderFor(
                    connected = true,
                    tripActive = false,
                    dayOfWeek = day,
                ),
            )
            assertNull(
                CarReminderPolicy.reminderFor(
                    connected = false,
                    tripActive = true,
                    dayOfWeek = day,
                ),
            )
        }
    }

    // ── The movement gate ──────────────────────────────────────────────────
    //
    // A head unit drops the link for reasons that are not the ignition. Left
    // ungated, every one of those during an open trip was a "Päättyikö ajo?"
    // at road speed — the same false prompt the app's own movement gate
    // exists to prevent, arriving by a route that gate could not see.

    @Test
    fun `a dropout while the car is still moving says nothing`() {
        assertNull(
            CarReminderPolicy.reminderFor(
                connected = false,
                tripActive = true,
                dayOfWeek = monday,
                millisSinceDrivingEvidence = 2_000L,
            ),
        )
    }

    @Test
    fun `a disconnect after the car has stopped still asks`() {
        assertEquals(
            CarReminder.STOP,
            CarReminderPolicy.reminderFor(
                connected = false,
                tripActive = true,
                dayOfWeek = monday,
                millisSinceDrivingEvidence =
                    CarReminderPolicy.MOVING_RECENCY_MS + 1_000L,
            ),
        )
    }

    @Test
    fun `no movement evidence at all prompts as before`() {
        // GPS unavailable, permission denied, or no fix yet this trip. A
        // missing signal must not cost the driver the prompt — the reminder
        // is the only thing standing between them and an unlogged trip.
        assertEquals(
            CarReminder.STOP,
            CarReminderPolicy.reminderFor(
                connected = false,
                tripActive = true,
                dayOfWeek = monday,
                millisSinceDrivingEvidence = null,
            ),
        )
    }

    @Test
    fun `evidence from the future is not evidence of movement`() {
        // The clock moved, not the car. Prompting is the safe read.
        assertEquals(
            CarReminder.STOP,
            CarReminderPolicy.reminderFor(
                connected = false,
                tripActive = true,
                dayOfWeek = monday,
                millisSinceDrivingEvidence = -5_000L,
            ),
        )
    }

    @Test
    fun `the movement gate never silences the start prompt`() {
        // Connecting is the ignition coming on; whatever the last drive's
        // GPS said has no bearing on it.
        assertEquals(
            CarReminder.START,
            CarReminderPolicy.reminderFor(
                connected = true,
                tripActive = false,
                dayOfWeek = monday,
                millisSinceDrivingEvidence = 1_000L,
            ),
        )
    }
}
