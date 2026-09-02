Feature: Battery cost of location tracking
  As a driver
  I want the app to stop using GPS as soon as it stops needing it
  So that one 40-minute drive does not cost a day of battery

  Background:
    Given a clean database
    And the app is running

  # A trip runs the receiver flat out under a location foreground service,
  # so ending the trip has to take that down. It did not. The trip-state
  # listener started the home screen's own position watch one step BEFORE
  # the trip stream was cancelled, and geolocator hands every caller the
  # SAME platform request, tearing it down only when its LAST listener goes.
  # The home screen watch therefore inherited the trip's foreground service,
  # wake lock and high accuracy instead of opening a cheap one of its own —
  # and when the trip ended with the app already in the background there was
  # no later pause to stop it, so it ran until the process died.

  Scenario: A trip tracks location under the foreground service
    Given location permission is granted
    When I start the {'Töihin'} route at {1000} km
    Then the app is tracking location for the trip

  Scenario: Arriving drops back to the cheap home screen watch
    Given location permission is granted
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then the app is tracking location only for the home screen

  Scenario: The home screen watch is never opened on top of the trip request
    Given location permission is granted
    When I start the {'Töihin'} route at {1000} km
    And I arrive at {1054} km
    Then the home screen watch never shared the trip location request

  Scenario: A trip that ends with the app in the background leaves no GPS running
    Given location permission is granted
    When I start the {'Töihin'} route at {1000} km
    And the app is backgrounded
    And the trip ends in the background
    Then the app is not tracking location

  Scenario: Coming back to the foreground resumes the home screen watch
    Given location permission is granted
    When I start the {'Töihin'} route at {1000} km
    And the app is backgrounded
    And the trip ends in the background
    And the app returns to the foreground
    Then the app is tracking location only for the home screen

  # Nothing but the driver tapping "Olen perillä" used to stop a trip's GPS,
  # so a leg left open by mistake kept the receiver — and its wake lock —
  # running for the rest of the day. The sensors now stand down once nothing
  # says the vehicle is moving, and Activity Recognition brings them back.

  Scenario: GPS tracking stops once the vehicle has stopped moving
    Given location permission is granted
    And activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the sensor stand down delay elapses
    Then the app is not tracking location

  Scenario: The trip stays open after the sensors stand down
    Given location permission is granted
    And activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the sensor stand down delay elapses
    Then I see {'Ajo käynnissä'}

  Scenario: GPS tracking keeps running while the vehicle is moving
    Given location permission is granted
    And GPS reports driving speed
    When I start the {'Töihin'} route at {1000} km
    And the sensor stand down delay elapses
    Then the app is tracking location for the trip

  Scenario: Getting back in the vehicle restarts GPS tracking
    Given location permission is granted
    And activity recognition reports {'still'}
    When I start the {'Töihin'} route at {1000} km
    And the sensor stand down delay elapses
    And activity recognition reports {'in_vehicle'}
    Then the app is tracking location for the trip
