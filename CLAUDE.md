# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## GitHub Workflow

- **Never merge pull requests.** Only create PRs. The user will review, merge, and close them.
- Create a separate feature branch per task from the task breakdown in GitHub Issues.
- Branch naming: `feature/N-short-description`
- Push the branch and create a PR targeting `main`.
- Reference the issue number in the PR body (e.g., "Closes #2").

## Project

Flutter Android app for tracking work mileage and daily allowances (kilometrikorvaus / päiväraha).

## Architecture

- State management: Riverpod
- Local DB: sqflite
- Google Sheets: googleapis + google_sign_in
- Background: flutter_background_service + geolocator + flutter_local_notifications
- Models in `lib/models/`
- Services in `lib/services/`
- Providers in `lib/providers/`
- Screens in `lib/screens/`
- Widgets in `lib/widgets/`
