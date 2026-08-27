Feature: Ad-hoc driving without a predefined route
  As a driver
  I want to start driving without first creating a route
  So that occasional trips are quick to log

  Background:
    Given a clean database
    And the app is running

  Scenario: Start and finish a trip with no predefined route
    When I start an ad-hoc trip from {'Siba'} at {3000} km
    And I finish driving at {'Asiakas'} at {3050} km
    Then I see text containing {'50.0 km'}

  Scenario: A finished ad-hoc trip is saved as a reusable route
    When I start an ad-hoc trip from {'Siba'} at {3000} km
    And I finish driving at {'Asiakas'} at {3050} km
    And I open routes
    Then I see text containing {'Siba → Asiakas'}

  Scenario: Active ad-hoc trip shows elapsed time as the primary metric
    When I start an ad-hoc trip from {'Siba'} at {3000} km
    Then I see {'0 h 00 min'}

  Scenario: Arriving at a known place fills in the destination
    Given location permission is granted
    And a known location {'Asiakas'} at {60.4} {25.0}
    When GPS reports position {60.2} {24.65}
    And I start a free trip at {1000} km
    And GPS reports position {60.4} {25.0}
    And I tap {'Olen perillä'}
    Then the {'Määränpää'} field shows {'Asiakas'}
