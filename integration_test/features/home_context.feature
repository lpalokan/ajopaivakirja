Feature: Top-of-screen context card and selection clarity
  The home screen's top zone reflects what the chip selection means
  And the StartCard banner shows the route name and destination
  So the driver can confirm what's about to happen before tapping start

  Background:
    Given a clean database
    And the app is running

  Scenario: With no route selected, the ad-hoc card is shown
    Then I see {'Vapaa ajo'}

  Scenario: Selecting a route replaces the ad-hoc card with a route preview
    When I tap {'Töihin'}
    Then I see {'Valittu reitti'}
    And I do not see {'Vapaa ajo'}

  Scenario: The StartCard banner shows the route name not just the start address
    When I tap {'Töihin'}
    Then I see text containing {'Reitti: Töihin'}

  Scenario: Tapping another route swaps the banner to the new route
    When I tap {'Töihin'}
    And I tap {'Kotiin'}
    Then I see text containing {'Reitti: Kotiin'}

  Scenario: Deselecting a route restores the ad-hoc card
    When I tap {'Töihin'}
    And I tap {'Töihin'}
    Then I see {'Vapaa ajo'}

  Scenario: Today's timeline shows the trip count when trips exist
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    And I start the {'Kotiin'} route at {1054} km
    And I arrive at {1108} km
    Then I see text containing {'2 matkaa'}
