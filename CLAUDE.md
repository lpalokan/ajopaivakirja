# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## GitHub Workflow

- **Never merge pull requests.** Only create PRs. The user will review, merge, and close them.
- **Never add commits to a branch after its PR has been merged.** Once merged, create a new branch from `main` for any remaining work.
- Create a separate feature branch per task from the task breakdown in GitHub Issues.
- Branch naming: `feature/N-short-description`
- Push the branch and create a PR targeting `main`.
- Reference the issue number in the PR body (e.g., "Closes #2").

## Project

Flutter Android app for tracking work mileage and daily allowances (kilometrikorvaus / päiväraha).

## BDD-first development (mandatory)

Every new feature or behaviour change MUST start with Gherkin scenarios,
before any implementation code:

1. **Write/extend the `.feature` file first.** Add scenarios in plain
   English under `integration_test/features/`. This is the source of truth
   for what the feature does.
2. **Wire steps to the harness.** Reuse existing steps where possible; only
   add a new step file in `integration_test/features/step/` (delegating to
   `integration_test/support/harness.dart`) when no existing phrase fits.
3. **Generate and run the failing test** (`dart run build_runner build
   --delete-conflicting-outputs`, then the emulator suite) — confirm it
   fails for the right reason (red).
4. **Only then implement** the feature until the scenario passes (green),
   then refactor.

Do not write feature/implementation code before its Gherkin scenario
exists and fails. Bug fixes follow the same loop: add a scenario that
reproduces the bug first. See `docs/testing.md` for the full workflow,
step catalogue, and maintenance guide.

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
