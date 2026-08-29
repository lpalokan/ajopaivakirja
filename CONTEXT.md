# Domain Glossary

The project's shared vocabulary. Use these terms exactly when discussing the
codebase — they name the concepts behind good seams.

## Core entities

- **Trip** (Matka) — A journey driven for work purposes. Composed of one or
  more legs on a given date.
- **Leg** (Leg, `TripLeg`) — A single segment of a trip: one departure to one
  arrival. Ordered within a date. Can be active, draft, or completed.
- **Route** (Reitti) — A predefined path between two named locations with an
  expected distance. Used as a shortcut when starting a trip from a regular
  destination pair.
- **Expense** (Kulu) — An additional cost incurred during a leg (parking,
  toll, meal, other).
- **Location zone** (Sijaintialue) — A geofence (lat/lon + radius) named
  after a physical place. Used for automatic arrival detection, for naming
  the current position from GPS, and for deciding which routes start near
  the driver. Entered by hand in Settings, saved by long-pressing the
  position chip, or learned automatically from where a leg starts and ends.
- **Nearby route** (Lähellä oleva reitti) — A route whose start location is
  a known location within 500 m of the current GPS fix. The home screen
  offers these as shortcuts, falling back to the recently driven routes when
  the position is unknown.
- **Km rate** (Kilometrikorvaus) — Year-specific per-km reimbursement rate
  published by the Finnish Tax Administration.
- **Home** (Koti) — The user's home location, configured in settings. Used as
  the default start location and to determine when a return-home leg triggers
  daily-allowance finalization.

## Trip life-cycle

- **Active trip** — A leg currently in progress. The app shows a live
  distance counter, a background notification, and GPS proximity monitoring.
- **Draft** — A leg that was started but never finished (missing end odometer
  or end location). Surfaced in history for manual completion or deletion.
- **Completed leg** — A leg with both start and end odometer/location
  populated. Ready for export.
- **Return home** (Kotiinpaluu) — A completed leg whose end location matches
  the configured home location. Triggers daily-allowance calculation for the
  entire day.

## Calculations

- **Km allowance** (Km-korvaus) — `kmDriven × rate(year)`. Computed per leg.
- **Daily allowance** (Päiväraha) — Per-diem for the whole day: half-day
  (>6h away from home) or full-day (>10h). Computed once per day when the
  last leg returns home. Can be manually overridden per day.
- **Working time** (Työaika) — Time spent at the work site: the span between
  the first leg's arrival and the last leg's departure. Stored on the last
  leg of the day.
- **Day summary** — Total km, total km allowance, total daily allowance,
  grand total, and whether any leg in the day is still a draft (estimated).

## External integration

- **Sheets sync** — Appending completed legs to a Google Sheets spreadsheet
  that the app itself created in the user's Drive (the `drive.file` scope
  grants access per file, so an app-created file is the only one it may
  touch). Uses upsert-by-ID so repeated syncs don't duplicate rows. If that
  spreadsheet becomes unreachable, the app creates a replacement and re-syncs
  the full history into it.
- **Arrival monitoring** — GPS proximity checking against location zones.
  A periodic check fires a "have you arrived?" notification once the driver
  is within range of the trip's own destination.

- **Bluetooth reminder** — The driver picks one paired device in Settings →
  Muistutus Bluetoothista, usually the car. When it connects or disconnects,
  a native `BroadcastReceiver` posts a reminder to log the trip. Costs
  nothing to run: `ACL_CONNECTED` / `ACL_DISCONNECTED` are exempt from the
  API 26+ implicit-broadcast restrictions, so Android starts the process to
  deliver them with no service, wake lock or GPS involved — and the prompt
  arrives while the driver is still sitting in front of the odometer. The
  chosen address is stored natively (`BluetoothTriggerStore`) because the
  receiver reads it with no Flutter engine running.

  A prompt only appears when it still asks for something: no "Aloititko
  ajon?" if a trip is already open, no "Päättyikö ajo?" if none is, and
  nothing at all on Saturday or Sunday — this is a work-mileage log, and a
  weekend errand prompt only teaches the driver to swipe reminders away.
  Whether a trip is open is knowledge only Dart has, so `TripNotifier`
  mirrors it into the same native store on every start, arrival, cancel and
  load; the judgement itself lives in `CarReminderPolicy`, kept free of
  Android types because an emulator has no Bluetooth and the receiver around
  it cannot be exercised by the test suite. Acting in the app also clears the
  reminder it makes moot, so a prompt never sits in the shade asking for
  something already done.

  There is deliberately **no automatic trip detection**. It existed, and it
  only ever worked while the app was open on screen: without a foreground
  service Android stops delivering location to a `whileInUse` app the moment
  it is backgrounded, which is every real drive. Making it work would have
  meant a permanent notification and continuous GNSS between rides; the
  feature was removed instead (#51). Trips are started by hand.
- **Trip location tracking** — The position stream that runs for the duration
  of an active trip. On Android it runs under geolocator's **location
  foreground service**, because a `whileInUse` app stops receiving location
  the moment it is backgrounded — which is every real drive, since the driver
  locks the screen. Without the service the movement signal below is fed for
  a few minutes and then silently starves.
- **Movement signal** (`MovementSignal`) — "was there a GPS fix at driving
  speed recently?", folded from the position stream that runs during a trip.
  Gates the "Oletko perillä?" reminder on both the poll and the proximity
  path. Needed because Android's activity recognition only emits when its
  reading *changes*, so a long steady drive reports `in_vehicle` once and
  then goes quiet — leaving a stale timestamp and a stray `still` reading
  enough to ask "have you arrived?" at speed.
- **OCR** — Camera-based odometer reading extraction using ML Kit text
  recognition.
