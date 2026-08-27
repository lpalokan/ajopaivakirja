Feature: What the app does for itself at startup
  Startup wiring runs on its own, without waiting for the GPS chip
  So a slow or unavailable fix cannot swallow the work behind it

  Background:
    Given a clean database

  Scenario: The update banner appears even when the first GPS fix is slow
    Given the update service reports {'update_available'}
    And the first GPS fix takes {20} seconds
    When the app is running
    Then I see text containing {'Päivitys saatavilla'}
