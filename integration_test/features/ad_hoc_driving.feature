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
