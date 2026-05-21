Feature: Draft trips
  As a driver
  I want incomplete trips to show as drafts in history
  So that I can finish them later without losing data

  Background:
    Given a clean database
    And the app is running

  Scenario: Abandoned trip shows as draft with Luonnos tag
    When a draft trip from {'Koti'} at {1000} km exists
    And I open history
    Then I see {'Luonnos'}
    And I see {'Täydennä'}

  Scenario: Täydennä opens edit dialog with focus on first empty field
    When a draft trip from {'Koti'} at {1000} km exists
    And I open history
    And I tap {'Täydennä'}
    Then I see {'Muokkaa merkintää'}

  Scenario: Day totals show ± luonnos suffix for dates with drafts
    When a draft trip from {'Koti'} at {1000} km exists
    And I open history
    Then I see text containing {'± luonnos'}

  Scenario: Drafts excluded from CSV export
    When a draft trip from {'Koti'} at {1000} km exists
    And I open history
    And I export the CSV
    And I tap {'Avaa sovelluksessa'}
    Then the exported CSV file has only the header row
