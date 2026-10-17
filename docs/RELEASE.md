# Release cadence

One small update every two to three weeks for the first quarter after launch. Apple's ranking rewards freshness, each release resets the displayed rating average, and short gaps keep the What's New sheet meaningful.

## Per release

1. Bump `CURRENT_PROJECT_VERSION` in `project.yml` (both targets); bump `MARKETING_VERSION` for user-visible changes.
2. Add a `WhatsNew.releases` entry for the new build (`Keeproll/Services/Growth/WhatsNew.swift`). Builds without an entry show no sheet.
3. New strings: build once in Xcode to sync the catalog, or `xcodebuild -exportLocalizations` / `-importLocalizations`; then add `hi` and `ta` rows to `scripts/l10n/translations_*.py` and run `python3 scripts/l10n/apply.py` (it reports anything missing and any placeholder mismatch).
4. `xcodegen generate`, build with zero warnings, run the tests, run the grep gates (CLAUDE.md §2).
5. Regenerate store screenshots if a screen changed: capture on the Pro Max simulator into `store/screenshots/raw/`, then `swift scripts/make_store_screenshots.swift`.
6. Archive, upload, write the App Store "What's New" text from the same list as the sheet.
7. Append to `.claude-progress.md`; commit with the requirement IDs.

## What to watch weekly in App Store Connect

- Product-page conversion ≥ 30 % (else: screenshots or subtitle).
- Day-7 retention ≥ 20 % (else: first scan time or the forecast's return hook).
- Crash-free sessions ≥ 99.5 % (MetricKit payloads from users who share analytics appear in Xcode Organizer).
- Rating ≥ 4.5 (the prompt fires once, after a ≥ 500 MB cleanup, never in session one).

## Deferred until there is data

- **App Clip / lighter first scan**: only if conversion is healthy but day-one retention is weak. The clip would run the screenshots-and-videos scan (seconds) and hand off to the full app.
