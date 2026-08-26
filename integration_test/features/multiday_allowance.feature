Feature: Daily allowance for trips that span more than one day
  A työmatka is measured in 24-hour travel days from the moment of departure
  Not in calendar dates
  So an overnight trip pays the päivärahat it actually earned

  Background:
    Given a clean database
    And the app is running

  Scenario: An overnight trip pays for both of its travel days
    Given I left home {32} hours ago and drove to {'Työ'}
    When I start the {'Kotiin'} route at {1054} km
    And I arrive at {1108} km
    Then the trip pays {2} full and {0} half daily allowances

  Scenario: Hours past the last full travel day pay a half allowance
    Given I left home {27} hours ago and drove to {'Työ'}
    When I start the {'Kotiin'} route at {1054} km
    And I arrive at {1108} km
    Then the trip pays {1} full and {1} half daily allowances

  Scenario: A trip barely past a travel day pays nothing for the remainder
    Given I left home {25} hours ago and drove to {'Työ'}
    When I start the {'Kotiin'} route at {1054} km
    And I arrive at {1108} km
    Then the trip pays {1} full and {0} half daily allowances

  Scenario: An unfinished trip has earned nothing yet
    Given I left home {32} hours ago and drove to {'Työ'}
    Then the trip pays {0} full and {0} half daily allowances

  Scenario: A trip inside one travel day pays by its total hours
    Given I left home {11} hours ago and drove to {'Työ'}
    When I start the {'Kotiin'} route at {1054} km
    And I arrive at {1108} km
    Then the trip pays {1} full and {0} half daily allowances
