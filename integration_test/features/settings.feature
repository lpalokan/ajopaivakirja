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

  Scenario: Home location persists
    When I open settings
    And I enter {'Saunatie 9'} in the {'Kotiosoite'} field
    And I save settings
    Then the {'home_location'} setting is {'Saunatie 9'}

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

  Scenario: Creating the spreadsheet requires signing in
    When I open settings
    Then I see {'Kirjaudu Googleen'}
    And I see {'Luo taulukko Google Driveen'}

  Scenario: Creating a spreadsheet stores its id
    Given I am signed in to Google
    When I open settings
    And I tap {'Luo taulukko Google Driveen'}
    Then the {'sheet_id'} setting is {'test-sheet-id'}
    And I see {'Vientitaulukko'}
    And I do not see {'Luo taulukko Google Driveen'}

  Scenario: Sheet tab persists
    When I open settings
    And I enter {'Matkat2026'} in the {'Välilehden nimi'} field
    And I save settings
    Then the {'sheet_tab'} setting is {'Matkat2026'}

  Scenario: Debug logging toggle reveals log actions
    When I open settings
    And I toggle debug logging
    Then I see {'Jaa loki'}

  Scenario: Auto-detection is gone from settings
    When I open settings
    Then I do not see text containing {'Ajontunnistus'}
    And I do not see text containing {'Tunnista ajo automaattisesti'}
    And I do not see text containing {'Nopeusraja'}

  Scenario: No driving reminder device is chosen to begin with
    When I open settings
    Then I see {'Muistutus Bluetoothista'}
    And I see {'Ei käytössä'}

  Scenario: Choosing the car that triggers driving reminders
    Given the phone is paired with {'Auton handsfree'}
    When I open settings
    And I choose {'Auton handsfree'} as the reminder device
    Then the reminder device is {'Auton handsfree'}

  Scenario: The Bluetooth reminder can be switched back off
    Given the phone is paired with {'Auton handsfree'}
    When I open settings
    And I choose {'Auton handsfree'} as the reminder device
    And I choose {'Ei käytössä'} as the reminder device
    Then no reminder device is set
