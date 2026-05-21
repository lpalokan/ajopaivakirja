Feature: Accessibility
  As a user — including users of TalkBack and high-contrast modes
  I want every state and action to be reachable and labelled
  So that the app meets WCAG 2.1 AA

  Background:
    Given a clean database
    And the app is running

  Scenario: Active-trip card announces state in text alongside colour
    When I start the {'Töihin'} route at {1000} km
    Then I see text containing {'Ajo käynnissä'}

  Scenario: Long press on the live counter freezes its value
    When I start the {'Töihin'} route at {1000} km
    And I long press the live distance counter
    Then I see {'Pinjattu'}

  Scenario: Tapping the pinned counter resumes live updates
    When I start the {'Töihin'} route at {1000} km
    And I long press the live distance counter
    And I tap {'Pinjattu'}
    Then I do not see {'Pinjattu'}
