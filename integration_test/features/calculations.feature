Feature: Reimbursement calculations end-to-end
  As a driver
  I want correct mileage and totals
  So that I claim the right amounts

  Background:
    Given a clean database
    And the app is running

  Scenario: A zero-distance trip yields zero allowance
    When I start the 'Töihin' route at {2000} km
    And I arrive at {2000} km
    And I open history
    Then I see text containing '0.0 km'

  Scenario: Two legs accumulate total distance
    When I start the 'Töihin' route at {1000} km
    And I arrive at {1040} km
    And I start the 'Kotiin' route at {1040} km
    And I arrive at {1075} km
    Then I see text containing '75.0 km'

  Scenario: Grand total combines the km allowance
    When I start the 'Töihin' route at {1000} km
    And I arrive at {1200} km
    Then I see text containing '€114.00'
