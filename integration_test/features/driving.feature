Feature: Driving flow
  As a driver
  I want to start and finish trips
  So that mileage is recorded automatically

  Background:
    Given a clean database
    And the app is running

  Scenario: Start dialog appears from a route
    When I open routes
    And I tap "Töihin"
    Then I see text containing "Reitti:"

  Scenario: Empty odometer blocks start
    When I open routes
    And I tap "Töihin"
    And I tap the "Aloita ajo" dialog button
    Then I see "Syötä mittarilukema"

  Scenario: Starting a trip shows the active-trip card
    When I start the "Töihin" route at 1000 km
    Then I see "Ajo käynnissä"

  Scenario: A completed trip shows in today's summary
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    Then I see text containing "Tänään"
    And I see text containing "54.0 km"

  Scenario: Stopping a trip clears the active card
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    Then I do not see "Ajo käynnissä"

  Scenario: Km allowance is reflected in the grand total
    When I start the "Töihin" route at 1000 km
    And I arrive at 1100 km
    Then I see text containing "€57.00"

  Scenario: A return-home day accumulates total distance
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I start the "Kotiin" route at 1054 km
    And I arrive at 1108 km
    Then I see text containing "108.0 km"
