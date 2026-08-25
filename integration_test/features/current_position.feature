Feature: Current position on the home screen
  The home screen names where the driver is right now, from GPS
  Matched to the closest known location within 500 m
  So the start location is right without typing it

  Background:
    Given a clean database
    And the app is running

  Scenario: The chip names the known location I am standing in
    Given a known location {'Toimisto'} at {60.2} {24.65}
    And location permission is granted
    When GPS reports position {60.2} {24.65}
    Then I see {'Toimisto'}

  Scenario: A known location 300 m away still names where I am
    Given a known location {'Toimisto'} at {60.2} {24.65}
    And location permission is granted
    When GPS reports position {60.2027} {24.65}
    Then I see {'Toimisto'}

  Scenario: A known location further than 500 m away does not
    Given a known location {'Toimisto'} at {60.2} {24.65}
    And location permission is granted
    When GPS reports position {60.21} {24.65}
    Then I do not see {'Toimisto'}

  Scenario: The closest known location wins
    Given a known location {'Toimisto'} at {60.2} {24.65}
    And a known location {'Varasto'} at {60.2018} {24.65}
    And location permission is granted
    When GPS reports position {60.2027} {24.65}
    Then I see {'Varasto'}
    And I do not see {'Toimisto'}

  Scenario: The chip follows me while the app is open
    Given a known location {'Toimisto'} at {60.2} {24.65}
    And a known location {'Varasto'} at {60.4} {25.0}
    And location permission is granted
    When GPS reports position {60.2} {24.65}
    And GPS reports position {60.4} {25.0}
    Then I see {'Varasto'}
    And I do not see {'Toimisto'}

  Scenario: Returning to the foreground re-resolves the position
    Given a known location {'Toimisto'} at {60.2} {24.65}
    And a known location {'Varasto'} at {60.4} {25.0}
    And location permission is granted
    When GPS reports position {60.2} {24.65}
    And the app is backgrounded
    And GPS reports position {60.4} {25.0}
    And the app returns to the foreground
    Then I see {'Varasto'}

  Scenario: Without location permission the chip says so
    Given a known location {'Toimisto'} at {60.2} {24.65}
    When GPS reports position {60.2} {24.65}
    Then I do not see {'Toimisto'}
    And I see text containing {'ei sijaintilupaa'}
