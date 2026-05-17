Feature: Settings
  As a driver
  I want to configure rates and persist them
  So that reimbursements are calculated correctly

  Background:
    Given a clean database
    And the app is running

  Scenario: Settings shows default values
    When I open settings
    Then I see {'Asetukset'}
    And I see {'Kirjaudu Googleen'}

  Scenario: Saving shows a confirmation
    When I open settings
    And I enter {'Kotikatu 1'} in the {'Kotiosoite'} field
    And I save settings
    Then I see {'Asetukset tallennettu'}

  Scenario: Home location persists across reopen
    When I open settings
    And I enter {'Saunatie 9'} in the {'Kotiosoite'} field
    And I save settings
    And I open settings
    Then I see {'Saunatie 9'}

  Scenario: Km rate persists across reopen
    When I open settings
    And I enter {'0,62'} in the {'Km-korvaus (€/km)'} field
    And I save settings
    And I open settings
    Then I see text containing {'0.62'}

  Scenario: Driver name persists across reopen
    When I open settings
    And I enter {'Matti M'} in the {'Kuljettajan nimi'} field
    And I save settings
    And I open settings
    Then I see {'Matti M'}

  Scenario: Sheet tab persists across reopen
    When I open settings
    And I enter {'Matkat2026'} in the {'Välilehden nimi'} field
    And I save settings
    And I open settings
    Then I see {'Matkat2026'}

  Scenario: Debug logging toggle reveals log actions
    When I open settings
    And I toggle debug logging
    Then I see {'Jaa loki'}
