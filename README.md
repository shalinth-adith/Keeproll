# Sift

**Keep what matters.** Sift is an iPhone storage cleaner. It finds similar photos, screenshots, large videos and duplicate contacts, and removes only what you approve on a final Review screen. Everything runs on the device: no account, no network, no uploads.

Built for the AppFactory *App Builder Intern* selection task.

## Status

| Area | State |
|---|---|
| Onboarding & permissions (full / limited / denied) | ✅ |
| Storage dashboard | ✅ |
| Screenshots → Review → Delete → Summary | ✅ end to end |
| Large videos (list, filters, inline player) | ✅ |
| Similar photos UI (groups, Best, Smart select, Compare) | ✅ UI · ⏳ scan engine |
| Duplicate contacts UI (match reasons, merge preview, primary picker) | ✅ UI · ⏳ dedupe + merge/backup |
| Swipe to sort (bonus) | ✅ |
| Blurry photos, widget, TestFlight | ⏳ |

Screens whose scanner isn't built yet only appear in the app when it is. To exercise them in the simulator with fixture data, launch with `SIFT_DEMO=1` (DEBUG builds only):

```bash
SIMCTL_CHILD_SIFT_DEMO=1 xcrun simctl launch booted me.adithyan.shalinth.Sift
```

## Build

Requirements: Xcode 26+ (Swift 6.2), [XcodeGen](https://github.com/yonaskolb/XcodeGen), iOS 17+ device or simulator.

```bash
xcodegen generate          # creates Sift.xcodeproj from project.yml
open Sift.xcodeproj
```

Tests: `xcodebuild -project Sift.xcodeproj -scheme Sift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

Simulator fixtures (EXIF-tagged fake screenshots, short videos):

```bash
swift scripts/make_screenshot_fixtures.swift SiftTests/Fixtures/Screenshots 12
swift scripts/make_video_fixtures.swift SiftTests/Fixtures/Videos 3
xcrun simctl addmedia booted SiftTests/Fixtures/Screenshots/*.png SiftTests/Fixtures/Videos/*.mp4
```

## How it's built

- **SwiftUI + MVVM**, `@Observable`, Swift 6 strict concurrency, zero third-party dependencies.
- **Safety by construction:** the only type that can delete, `DeletionService`, accepts a `CleanupPlan`, and a plan can only be created by the Review screen's view model (its initialiser is `fileprivate`). iOS's own delete confirmation is always shown.
- **Honest numbers:** deleted photos go to Recently Deleted for 30 days, and the app says so.

Docs: [PRD](docs/PRD.md) · [Architecture](docs/ARCHITECTURE.md) · [Design system](docs/DESIGN_SYSTEM.md) · [Decisions](docs/DECISIONS.md) · [Agent instructions](CLAUDE.md)
