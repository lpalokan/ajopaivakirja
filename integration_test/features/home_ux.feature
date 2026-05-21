Feature: Home screen UX refinements
  As a driver
  I want the home screen to remember my last odometer reading
  So that starting a new trip is faster

  Background:
    Given a clean database
    And the app is running

  Scenario: The odometer field is prefilled from the last completed trip
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then the odometer field shows {1054} km

  Scenario: The bottom "Olen perillä" button opens the arrival dialog
    When I start the {'Töihin'} route at {1000} km
    And I tap the bottom {'Olen perillä'}
    Then I see {'Matkamittari perillä (km)'}

  Scenario: The arrival dialog pre-fills the odometer for a route-based trip
    When I start the {'Töihin'} route at {1000} km
    And I tap {'Olen perillä'}
    Then the arrival dialog odometer field shows {1054} km

  Scenario: The "Vapaa ajo" card stays visible after completing trips
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then I see {'Vapaa ajo'}
    And I see text containing {'Tänään'}
