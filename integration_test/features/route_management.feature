Feature: Route management
  As a driver
  I want to add, edit and delete routes
  So that my common trips are one tap away

  Background:
    Given a clean database
    And the app is running

  Scenario: Add a new route
    When I add route 'Asiakaskäynti' from 'Koti' to 'Asiakas' of {32} km
    Then I see 'Asiakaskäynti'

  Scenario: Empty route form blocks save
    When I open the add route dialog
    And I tap the 'Tallenna' dialog button
    Then I see 'Uusi reitti'

  Scenario: Cancel the route dialog
    When I open the add route dialog
    And I tap the 'Peruuta' dialog button
    Then I do not see 'Uusi reitti'

  Scenario: Editing a route opens the edit dialog
    When I open routes
    And I swipe 'Töihin' right
    Then I see 'Muokkaa reittiä'
    When I tap the 'Peruuta' dialog button
    Then I see 'Töihin'

  Scenario: Delete a route with confirmation
    When I open routes
    And I swipe 'Kotiin' left
    Then I see 'Poista reitti'
    When I tap the 'Poista' dialog button
    Then I do not see 'Kotiin'

  Scenario: Cancelling deletion keeps the route
    When I open routes
    And I swipe 'Kotiin' left
    And I tap the 'Peruuta' dialog button
    Then I see 'Kotiin'

  Scenario: A new route appears on the home recent list
    When I add route 'Varikko' from 'Koti' to 'Varikko' of {12} km
    And I go back
    Then I see 'Varikko'
