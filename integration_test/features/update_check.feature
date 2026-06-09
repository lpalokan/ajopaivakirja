Feature: App update check
  As a sideloaded user
  I want the app to tell me when a newer build is available
  so that I can install it from inside the app

  Background:
    Given a clean database
    And the app is running

  Scenario: Manual check shows up-to-date message
    Given the update service reports {'up_to_date'}
    When I open settings
    And I tap {'Tarkista päivitykset'}
    Then I see text containing {'Sovellus on ajan tasalla'}

  Scenario: Manual check shows install prompt when an update is available
    Given the update service reports {'update_available'}
    When I open settings
    And I tap {'Tarkista päivitykset'}
    Then I see text containing {'Päivitys saatavilla'}

  Scenario: Installing an update shows a download progress indicator that clears when done
    Given the update service reports {'update_available'}
    And the update download is held open
    When I open settings
    And I tap {'Tarkista päivitykset'}
    And I tap {'Asenna'}
    Then I see text containing {'Ladataan'}
    When the held download is released
    Then I see text containing {'Asenna'}

  Scenario: Home banner appears once the app finds an available update
    Given the update service reports {'update_available'}
    When the app checks for updates
    Then I see text containing {'Päivitys saatavilla'}

  Scenario: No home banner when the app is already on the latest build
    Given the update service reports {'up_to_date'}
    When the app checks for updates
    Then I do not see {'Päivitys saatavilla'}
