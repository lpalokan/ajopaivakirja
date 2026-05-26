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

  Scenario: Arrival notification action ends the leg even if in-memory state was lost
    When I start the {'Töihin'} route at {1000} km
    And the in-memory trip state is cleared
    And the arrival notification action is tapped
    Then I do not see {'Ajo käynnissä'}

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

  Scenario: The 45-min reminder is suppressed while activity is in_vehicle
    Given activity recognition reports {'in_vehicle'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then no arrival reminder has been shown

  Scenario: The 45-min reminder fires when activity has left the vehicle
    Given activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the reminder backstop elapses
    Then an arrival reminder has been shown

  Scenario: The 45-min reminder fires when activity recognition is unavailable
    When I start the {'Töihin'} route at {1000} km
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
