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
  after a physical place. Used for automatic arrival detection and location
  naming from GPS.
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

- **Sheets sync** — Appending completed legs to a Google Sheets spreadsheet.
  Uses upsert-by-ID so repeated syncs don't duplicate rows.
- **Detection** — Background GPS monitoring that auto-detects when the user
  starts driving (>5 m/s for 30s) and when they arrive (<1 m/s for 60s after
  driving was detected).
- **Arrival monitoring** — GPS proximity checking against location zones.
  When the destination is Home, a periodic check fires a "have you arrived?"
  notification when within range.
- **OCR** — Camera-based odometer reading extraction using ML Kit text
  recognition.
