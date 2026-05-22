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
