Feature: Driving flow
  As a driver
  I want to start and finish trips
  So that mileage is recorded automatically

  Background:
    Given a clean database
    And the app is running

  Scenario: Tapping a route chip selects it on the StartCard
    When I tap {'Töihin'}
    Then I see text containing {'Reitti:'}

  Scenario: Empty odometer blocks start
    When I tap {'Töihin'}
    And I tap {'Aloita ajo'}
    Then I see {'Syötä mittarilukema'}

  Scenario: Starting a trip shows the active-trip card
    When I start the {'Töihin'} route at {1000} km
    Then I see {'Ajo käynnissä'}

  Scenario: Active route trip displays elapsed time alongside the start time
    When I start the {'Töihin'} route at {1000} km
    Then I see text containing {'0 h 00 min'}

  Scenario: Arrival notification action opens the mileage dialog without ending the leg
    When I start the {'Töihin'} route at {1000} km
    And the arrival notification action is tapped
    Then I see {'Matkamittari perillä (km)'}
    And I see {'Ajo käynnissä'}

  Scenario: The arrival dialog from the notification suggests the route's calculated mileage
    When I start the {'Töihin'} route at {1000} km
    And the arrival notification action is tapped
    Then the arrival dialog odometer field shows {1054} km

  Scenario: Confirming the arrival dialog from the notification records the trip
    When I start the {'Töihin'} route at {1000} km
    And the arrival notification action is tapped
    And I fill in the arrival mileage {1054} km
    Then I do not see {'Ajo käynnissä'}
    And I see text containing {'54.0 km'}

  Scenario: Arrival notification action opens the dialog even if in-memory state was lost
    When I start the {'Töihin'} route at {1000} km
    And the in-memory trip state is cleared
    And the arrival notification action is tapped
    Then I see {'Matkamittari perillä (km)'}

  Scenario: Returning to the foreground re-shows the active-trip card when in-memory state was lost
    When I start the {'Töihin'} route at {1000} km
    And the in-memory trip state is cleared
    And the app returns to the foreground
    Then I see {'Ajo käynnissä'}

  Scenario: A completed trip shows in today's summary
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then I see text containing {'Tänään'}
    And I see text containing {'54.0 km'}

  Scenario: Stopping a trip clears the active card
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then I do not see {'Ajo käynnissä'}

  Scenario: Km allowance is reflected in the grand total
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1100} km
    Then I see text containing {'€55.00'}

  Scenario: A return-home day accumulates total distance
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    And I start the {'Kotiin'} route at {1054} km
    And I arrive at {1108} km
    Then I see text containing {'108.0 km'}

  Scenario: DayTimeline shows draft with Täydennä link while trip is active
    When I start the {'Töihin'} route at {1000} km
    Then I see text containing {'Täydennä'}
    And I see text containing {'Tänään'}

  Scenario: GPS movement does not inflate the displayed route distance
    When I start the {'Töihin'} route at {1000} km
    And GPS reports {5} km of movement
    Then I see {'54.0 km'}
    And I do not see {'59.0 km'}

  Scenario: The reminder is suppressed while activity is in_vehicle
    Given activity recognition reports {'in_vehicle'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The first reminder of a trip is deferred past the steady-state poll
    Given activity recognition reports {'still'}
    And the first reminder is deferred well beyond the steady poll
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The reminder fires when activity has left the vehicle
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then an arrival reminder has been shown

  Scenario: The reminder fires when activity recognition is unavailable
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then an arrival reminder has been shown

  Scenario: The reminder is suppressed while activity recognition is uncertain
    Given activity recognition reports {'in_vehicle'}
    When I start the {'Töihin'} route at {1000} km
    And activity recognition reports {'unknown'}
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The reminder is suppressed while GPS shows driving speed
    Given location permission is granted
    And activity recognition reports {'still'}
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: GPS driving speed suppresses the reminder when activity recognition is unavailable
    Given location permission is granted
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The reminder fires once the vehicle has stopped moving
    Given location permission is granted
    And activity recognition reports {'still'}
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And GPS reports the vehicle has stopped
    And the reminder backstop elapses
    Then an arrival reminder has been shown

  Scenario: Tapping still driving defers the reminder and the next tick suppresses while in_vehicle
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    And the still driving notification action is tapped
    And activity recognition reports {'in_vehicle'}
    And the reminder backstop elapses
    Then exactly {1} arrival reminder has been shown

  Scenario: Tapping still driving dismisses the reminder notification
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    And the still driving notification action is tapped
    Then the reminder notification has been dismissed

  Scenario: Tapping still driving silences reminders for the whole snooze window
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    And the still driving notification action is tapped with a long snooze
    And the reminder backstop elapses
    Then exactly {1} arrival reminder has been shown

  Scenario: A confident still reading right after in_vehicle does not fire the reminder
    Given activity recognition reports {'in_vehicle'}
    And the in-vehicle recency window is long
    When I start the {'Töihin'} route at {1000} km
    And activity recognition reports {'still'}
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The reminder is shown only once per stop while activity stays out of the vehicle
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    And the reminder backstop elapses
    Then exactly {1} arrival reminder has been shown

  Scenario: Pressing still driving snoozes and the reminder fires again if still stopped
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    And the still driving notification action is tapped
    And the reminder backstop elapses
    Then exactly {2} arrival reminder has been shown

  Scenario: Returning to the vehicle and stopping again re-prompts on the next stop
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    And activity recognition reports {'in_vehicle'}
    And the reminder backstop elapses
    And activity recognition reports {'still'}
    And the reminder backstop elapses
    Then exactly {2} arrival reminder has been shown

  Scenario: Proximity-based reminder fires while a trip is active
    Given location permission is granted
    And activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the location service reports arrival at the destination
    Then an arrival reminder has been shown

  Scenario: Proximity-based reminder is suppressed while activity is in_vehicle
    Given location permission is granted
    And activity recognition reports {'in_vehicle'}
    When I start the {'Töihin'} route at {1000} km
    And the location service reports arrival at the destination
    Then no arrival reminder has been shown

  Scenario: Proximity-based reminder is suppressed while GPS shows driving speed
    Given location permission is granted
    And activity recognition reports {'still'}
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And the location service reports arrival at the destination
    Then no arrival reminder has been shown

  Scenario: Proximity-based reminder is suppressed shortly after the vehicle signal
    Given location permission is granted
    And activity recognition reports {'in_vehicle'}
    And the in-vehicle recency window is long
    When I start the {'Töihin'} route at {1000} km
    And activity recognition reports {'still'}
    And the location service reports arrival at the destination
    Then no arrival reminder has been shown

  Scenario: Proximity-based reminder is shown only once per stop
    Given location permission is granted
    And activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the location service reports arrival at the destination
    And the location service reports arrival at the destination
    Then exactly {1} arrival reminder has been shown

  Scenario: Proximity-based reminder respects the still-driving snooze
    Given location permission is granted
    And activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the location service reports arrival at the destination
    And the still driving notification action is tapped with a long snooze
    And the location service reports arrival at the destination
    Then exactly {1} arrival reminder has been shown

  Scenario: Proximity-based reminder is suppressed after arrival is confirmed
    Given location permission is granted
    And activity recognition reports {'in_vehicle'}
    When I start the {'Töihin'} route at {1000} km
    And the arrival notification action is tapped
    And I fill in the arrival mileage {1054} km
    And the location service reports arrival at the destination
    Then no arrival reminder has been shown

  Scenario: Locking the phone mid-drive keeps the reminder suppressed
    Given location permission is granted
    And activity recognition reports {'still'}
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And the app is backgrounded
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The reminder fires when the vehicle stops with the app backgrounded
    Given location permission is granted
    And activity recognition reports {'still'}
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And the app is backgrounded
    And GPS reports the vehicle has stopped
    And the reminder backstop elapses
    Then an arrival reminder has been shown

  # The car-Bluetooth reminder decides in native code, with no Flutter engine
  # and no database, whether to prompt "Aloititko ajon?" or "Päättyikö ajo?".
  # Whether a trip is open is knowledge only the app has, so it has to be
  # pushed across as it changes — and re-asserted on every load, because the
  # app can be killed mid-trip.
  Scenario: Before any trip the car reminder knows nothing is in progress
    Then the car reminder knows no trip is in progress

  Scenario: Starting a trip tells the car reminder that driving has begun
    When I start the {'Töihin'} route at {1000} km
    Then the car reminder knows a trip is in progress

  Scenario: Arriving tells the car reminder that driving has ended
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then the car reminder knows no trip is in progress

  Scenario: A free trip tells the car reminder that driving has begun
    When I start a free trip at {1000} km
    Then the car reminder knows a trip is in progress

  Scenario: Reloading re-asserts an open trip to the car reminder
    When I start the {'Töihin'} route at {1000} km
    And the car reminder has lost track of the trip
    And the app returns to the foreground
    Then the car reminder knows a trip is in progress

  # A car's Bluetooth link drops for reasons that are not the ignition going
  # off, and a dropout mid-drive used to prompt "Päättyikö ajo?" at 100 km/h:
  # the receiver's only gates were "is a trip open" and "is it a weekday". It
  # has no GPS of its own and no engine to ask, so the app mirrors when the
  # vehicle was last measurably moving into the same store it already mirrors
  # the open trip into.
  Scenario: Driving speed tells the car reminder the vehicle is moving
    Given location permission is granted
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    Then the car reminder knows the vehicle was recently moving

  Scenario: A trip that never sees driving speed leaves no movement evidence
    Given location permission is granted
    When I start the {'Töihin'} route at {1000} km
    Then the car reminder has no movement evidence

  Scenario: Ending a trip clears the car reminder movement evidence
    Given location permission is granted
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then the car reminder has no movement evidence

  # One "have you arrived?" at a time. The app's own reminder and the car's
  # disconnect prompt ask the same question by different routes, and two
  # notifications for one question is the nagging the driver learns to swipe.
  Scenario: The app arrival reminder takes down the car stop prompt
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then the car stop prompt has been dismissed

  # Both car prompts carry a mileage button: the odometer is in front of the
  # driver at exactly the moment the car connects or disconnects, which is
  # the whole reason this trigger beats anything the app can infer.
  Scenario: The car end-mileage button opens the arrival dialog
    When I start the {'Töihin'} route at {1000} km
    And the car end-mileage button is tapped
    Then I see {'Matkamittari perillä (km)'}
    And I see {'Ajo käynnissä'}

  Scenario: The car end-mileage button does nothing when no trip is open
    When the car end-mileage button is tapped
    Then I do not see {'Matkamittari perillä (km)'}

  Scenario: The car start-mileage button opens the start dialog
    When the car start-mileage button is tapped
    Then I see {'Matkamittari lähdössä (km)'}

  Scenario: Confirming the car start-mileage dialog begins a trip
    When the car start-mileage button is tapped
    And I fill in the start mileage {1000} km
    Then I see {'Ajo käynnissä'}
    And the car reminder knows a trip is in progress

  Scenario: The car start-mileage button does nothing while a trip is open
    When I start the {'Töihin'} route at {1000} km
    And the car start-mileage button is tapped
    Then I do not see {'Matkamittari lähdössä (km)'}
