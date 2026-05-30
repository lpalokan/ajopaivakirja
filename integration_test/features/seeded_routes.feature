Feature: Seeded debug routes
  In debug builds the app seeds two starter routes
  So that a new install is immediately usable

  Background:
    Given a clean database
    And the app is running

  Scenario: Both seeded routes are shown
    Then I see {'Töihin'}
    And I see {'Kotiin'}

  Scenario: The all-routes link is gone from home
    Then I do not see {'Kaikki reitit (2)'}

  Scenario: Recent routes show their distance
    Then I see text containing {'54.0 km'}

  Scenario: Route list shows both routes
    When I open routes
    Then I see {'Töihin'}
    And I see {'Kotiin'}
