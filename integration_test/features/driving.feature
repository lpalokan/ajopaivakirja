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
