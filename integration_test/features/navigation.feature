Feature: App boot and navigation
  As a driver
  I want to move between the main screens
  So that I can reach every part of the app

  Background:
    Given a clean database
    And the app is running

  Scenario: Home screen renders
    Then I see 'Ajopäiväkirja'
    And I see 'Viimeisimmät reitit'

  Scenario: Navigate to Settings and back
    When I open settings
    Then I see 'Asetukset'
    When I go back
    Then I see 'Ajopäiväkirja'

  Scenario: Navigate to Routes and back
    When I open routes
    Then I see 'Reitit'
    When I go back
    Then I see 'Ajopäiväkirja'

  Scenario: Navigate to History and back
    When I open history
    Then I see 'Historia'
    When I go back
    Then I see 'Ajopäiväkirja'

  Scenario: History is empty before any trips
    When I open history
    Then I see 'Ei ajohistoriaa'
