Feature: Home lists the routes that start near me
  The route shortcuts on the home screen are the ones I can drive from here
  Falling back to the recently driven routes when my position is unknown
  So the route I want is one tap away wherever I am

  Background:
    Given a clean database
    And the app is running

  Scenario: Standing at home surfaces the route that starts at home
    Given a known location {'Koti'} at {60.2} {24.65}
    And a known location {'Työ'} at {60.4} {25.0}
    And location permission is granted
    When GPS reports position {60.2} {24.65}
    Then I see {'Lähellä'}
    And I see {'Töihin'}
    And I do not see {'Kotiin'}

  Scenario: Standing at work surfaces the route back home
    Given a known location {'Koti'} at {60.2} {24.65}
    And a known location {'Työ'} at {60.4} {25.0}
    And location permission is granted
    When GPS reports position {60.4} {25.0}
    Then I see {'Kotiin'}
    And I do not see {'Töihin'}

  Scenario: A route whose start is more than 500 m away is not nearby
    Given a known location {'Koti'} at {60.2} {24.65}
    And location permission is granted
    When GPS reports position {60.21} {24.65}
    Then I see {'Viimeksi ajetut'}
    And I see {'Töihin'}
    And I see {'Kotiin'}

  Scenario: With no known locations the recent routes are shown
    Given location permission is granted
    When GPS reports position {60.2} {24.65}
    Then I see {'Viimeksi ajetut'}
    And I see {'Töihin'}
    And I see {'Kotiin'}

  Scenario: Without location permission the recent routes are shown
    Given a known location {'Koti'} at {60.2} {24.65}
    When GPS reports position {60.2} {24.65}
    Then I see {'Viimeksi ajetut'}
    And I see {'Töihin'}
    And I see {'Kotiin'}

  Scenario: The nearby route can still be started
    Given a known location {'Koti'} at {60.2} {24.65}
    And location permission is granted
    When GPS reports position {60.2} {24.65}
    And I start the {'Töihin'} route at {1000} km
    Then I see text containing {'Töihin'}

  Scenario: Driving a route remembers both of its ends
    Given location permission is granted
    When GPS reports position {60.2} {24.65}
    And I start the {'Töihin'} route at {1000} km
    And GPS reports position {60.4} {25.0}
    And I arrive at {1054} km
    Then I see {'Lähellä'}
    And I see {'Kotiin'}
