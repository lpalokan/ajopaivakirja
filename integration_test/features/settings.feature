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

  Scenario: Auto-detection thresholds show their defaults
    When I open settings
    Then I see text containing {'Ajontunnistus'}
    And I see text containing {'18 km/h'}
    And I see text containing {'30 s'}
    And I see text containing {'60 s'}

  Scenario: Detection speed threshold persists
    When I open settings
    And I drag the {'detection_speed'} slider to its {'maximum'}
    And I save settings
    Then the {'detection_speed_mps'} setting is {'8.0'}

  Scenario: Sustained driving duration persists
    When I open settings
    And I drag the {'detection_driving'} slider to its {'minimum'}
    And I save settings
    Then the {'detection_driving_seconds'} setting is {'15'}

  Scenario: Arrival stop duration persists
    When I open settings
    And I drag the {'detection_arrival'} slider to its {'maximum'}
    And I save settings
    Then the {'detection_arrival_seconds'} setting is {'180'}

  Scenario: Auto-detection is on to begin with
    When I open settings
    Then I see {'Tunnista ajo automaattisesti'}
    And I see text containing {'18 km/h'}

  Scenario: Auto-detection can be switched off
    When I open settings
    And I toggle {'Tunnista ajo automaattisesti'}
    And I save settings
    Then the {'auto_detect'} setting is {'0'}

  Scenario: Switching auto-detection off hides its thresholds
    When I open settings
    And I toggle {'Tunnista ajo automaattisesti'}
    Then I do not see text containing {'18 km/h'}
