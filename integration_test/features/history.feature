Feature: Trip history
  As a driver
  I want to review, edit and delete recorded trips
  So that my logbook stays correct

  Background:
    Given a clean database
    And the app is running

  Scenario: A completed trip appears in history
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I open history
    Then I see "Töihin"
    And I do not see "Ei ajohistoriaa"

  Scenario: The edit-leg dialog opens from history
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I open history
    And I tap "Töihin"
    Then I see "Muokkaa merkintää"

  Scenario: Editing a leg purpose and saving
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I open history
    And I tap "Töihin"
    And I enter "Päivitetty syy" in the dialog "Tarkoitus" field
    And I tap the "Tallenna" dialog button
    Then I do not see "Muokkaa merkintää"

  Scenario: Delete a leg via swipe
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I open history
    And I swipe "Töihin" left
    Then I see "Poista merkintä"
    When I tap the "Poista" dialog button
    Then I see "Ei ajohistoriaa"

  Scenario: Cancelling leg deletion keeps the leg
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I open history
    And I swipe "Töihin" left
    And I tap the "Peruuta" dialog button
    Then I see "Töihin"

  Scenario: History shows a per-day total
    When I start the "Töihin" route at 1000 km
    And I arrive at 1100 km
    And I open history
    Then I see text containing "100.0 km"

  Scenario: Sync without a sheet id shows a notice
    When I start the "Töihin" route at 1000 km
    And I arrive at 1054 km
    And I open history
    And I sync to sheets
    Then I see "Sheets-tunnusta ei ole määritetty"
