Feature: The app learns places from driving
  A place the driver names while standing there is remembered by itself
  A place the app only guessed at is never recorded
  So the home screen knows where it is without anyone maintaining a list

  Background:
    Given a clean database
    And the app is running

  Scenario: Arriving somewhere remembers it
    Given location permission is granted
    When GPS reports position {60.2} {24.65}
    And I start the {'Töihin'} route at {1000} km
    And GPS reports position {60.4} {25.0}
    And I arrive at {1054} km
    Then the app remembers the place {'Työ'}

  Scenario: A guessed start location is never recorded
    Given location permission is granted
    When GPS reports position {60.2} {24.65}
    And I start a free trip at {1000} km
    Then the app does not remember the place {'Koti'}

  Scenario: A start location I set myself is recorded
    Given location permission is granted
    When GPS reports position {60.2} {24.65}
    And I start an adhoc trip from {'Varasto'} at {1000} km
    Then the app remembers the place {'Varasto'}

  Scenario: Home is learned from the first drive home
    Given location permission is granted
    When GPS reports position {60.2} {24.65}
    And I start the {'Töihin'} route at {1000} km
    And GPS reports position {60.4} {25.0}
    And I arrive at {1054} km
    And I start the {'Kotiin'} route at {1054} km
    And GPS reports position {60.2} {24.65}
    And I arrive at {1108} km
    Then the app remembers the place {'Koti'}

  Scenario: Nothing is remembered without location permission
    When GPS reports position {60.2} {24.65}
    And I start an adhoc trip from {'Varasto'} at {1000} km
    Then the app does not remember the place {'Varasto'}
