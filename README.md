# Sift

**Keep what matters.** Sift is an iPhone storage cleaner. It finds similar photos, screenshots, large videos and duplicate contacts, and removes only what you approve on a final Review screen. Everything runs on the device: no account, no network, no uploads.

Built for the AppFactory *App Builder Intern* selection task.

## Status

| Area | State |
|---|---|
| Onboarding & permissions (full / limited / denied) | ✅ |
| Storage dashboard | ✅ |
| Screenshots (filters, drag-to-select) | ✅ |
| Large videos (list, filters, inline player) | ✅ |
| Similar photos: dHash multi-index + time-windowed Vision prints + union-find, Best shot, Compare | ✅ · thresholds calibrated on device |
| Duplicate contacts: phone/email/name matching, merge, delete, vCard backup | ✅ |
| Review → Delete → Summary (the only deletion path) | ✅ |
| Scan cache (warm rescans skip analysis) | ✅ |
| Live library changes (deleted in Photos → gone from Sift; new photos → quick refresh) | ✅ |
| iCloud-only badges + honest "frees iCloud space" note on Review | ✅ |
| Bonus: Swipe to sort, Blurry photos, Home Screen widget, space-freed Summary | ✅ |
| Bonus: Compress large videos (HEVC copy saved first; original goes to Review) | ✅ |
| Bonus: Private vault (Face ID / passcode, on-device only; originals go to Review) | ✅ |
| Bonus: Calendar cleanup (duplicate and year-old single events, .ics backup first) | ✅ |
| TestFlight | ⏳ |

## Build

Requirements: Xcode 26+ (Swift 6.2), [XcodeGen](https://github.com/yonaskolb/XcodeGen), iOS 17+ device or simulator.

```bash
xcodegen generate          # creates Sift.xcodeproj from project.yml
open Sift.xcodeproj
```

Tests: `xcodebuild -project Sift.xcodeproj -scheme Sift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Simulator fixtures: tagged screenshots, short videos, photo bursts / duplicates / blurry shots, and duplicate contacts:

```bash
swift scripts/make_screenshot_fixtures.swift SiftTests/Fixtures/Screenshots 12
swift scripts/make_video_fixtures.swift SiftTests/Fixtures/Videos 3
swift scripts/make_photo_fixtures.swift SiftTests/Fixtures/Photos
xcrun simctl addmedia booted SiftTests/Fixtures/Screenshots/*.png SiftTests/Fixtures/Videos/*.mp4 \
  SiftTests/Fixtures/Photos/*.jpg SiftTests/Fixtures/Contacts/duplicates.vcf
```

With that library the expected result is: 4 similar groups (3 bursts + 1 exact-duplicate pair), 2 blurry photos, 3 duplicate-contact pairs.

## How it's built

- **SwiftUI + MVVM**, `@Observable`, Swift 6 strict concurrency, zero third-party dependencies.
- **Safety by construction:** the only type that can delete, `DeletionService`, accepts a `CleanupPlan`, and a plan can only be created by the Review screen's view model (its initialiser is `fileprivate`). iOS's own delete confirmation is always shown.
- **Honest numbers:** deleted photos go to Recently Deleted for 30 days, and the app says so.
- **Fast on big libraries:** exact duplicates are found through a 4-band multi-index over 64-bit dHashes (no all-pairs comparison); similar shots are only compared with photos taken within 60 s. Results stream in batch by batch, and a binary cache makes rescans skip analysis.
- **Contacts are backed up** to a vCard before any merge or delete, since iOS has no Recently Deleted for contacts.

Docs: [PRD](docs/PRD.md) · [Architecture](docs/ARCHITECTURE.md) · [Design system](docs/DESIGN_SYSTEM.md) · [Decisions](docs/DECISIONS.md) · [Agent instructions](CLAUDE.md)
