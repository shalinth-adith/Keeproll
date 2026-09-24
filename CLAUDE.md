# Sift — Agent Instructions

> Read this file first, every session. It takes precedence over any parent `CLAUDE.md` (for example `~/Desktop/CLAUDE.md` describes **Padivam**, a different app; ignore it here).

## 1. What this is

**Sift** is an iPhone storage cleaner built for the AppFactory *App Builder Intern* selection task. It finds similar/duplicate photos, screenshots, large videos and duplicate contacts, and deletes them **only after the user approves them on a Review screen**. It runs entirely on the device: no network, no login, no payments.

Read these before writing code, in this order:
1. `docs/DECISIONS.md`: locked decisions. Never contradict them silently.
2. `docs/PRD.md`: requirements with stable IDs (`FR-SIM-3`, …) and the day-by-day milestones.
3. `docs/ARCHITECTURE.md`: MVVM layers, folder layout, scan pipeline, the deletion invariant.
4. `docs/DESIGN_SYSTEM.md`: tokens, components, copy rules.
5. `.claude-progress.md`: what the previous session did and what comes next.

**How the work is evaluated (optimise in this order):** (1) the core loop works end to end, (2) nothing is deleted without approval, (3) scan speed and accuracy on a large library, (4) polish, (5) scope decisions and use of AI.

## 2. Commands

```bash
# Regenerate the Xcode project after editing project.yml or adding/removing files
xcodegen generate

# Build (compile check, no signing)
xcodebuild -project Sift.xcodeproj -scheme Sift -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Unit tests. Device names can be ambiguous across runtimes, so target by UDID
# (xcrun simctl list devices available). iPhone 17 Pro on iOS 27 = 76F4638C-446D-4A10-A78E-C3FA1B79CCE0
xcodebuild -project Sift.xcodeproj -scheme Sift -destination 'id=<UDID>' test

# Seed the simulator with EXIF-tagged fake screenshots and short videos
swift scripts/make_screenshot_fixtures.swift SiftTests/Fixtures/Screenshots 12
swift scripts/make_video_fixtures.swift SiftTests/Fixtures/Videos 3
xcrun simctl addmedia <UDID> SiftTests/Fixtures/Screenshots/*.png SiftTests/Fixtures/Videos/*.mp4

# Demo mode: fixture results for categories whose scanner isn't built (DEBUG only)
SIMCTL_CHILD_SIFT_DEMO=1 xcrun simctl launch <UDID> me.adithyan.shalinth.Sift

# Privacy + safety gates (all must print nothing; see §5)
grep -rnE "URLSession|URLRequest|NWConnection" Sift/
grep -rnE "deleteAssets|CNSaveRequest" Sift/ | grep -vE "Sift/Services/(Cleanup|Contacts)/"
grep -rn "CNContactNoteKey" Sift/
```

**Gotchas found on Day 1:**
- Never put `-derivedDataPath` inside this folder. The Desktop adds extended attributes, and codesign fails with *"resource fork, Finder information, or similar detritus not allowed"*. Use the default DerivedData or a temp dir.
- `simctl privacy grant photos` doesn't grant `.readWrite` on iOS 27 (the status still reads `notDetermined`). Go through the real prompt instead.
- `presentLimitedLibraryPicker` needs `import PhotosUI`.
- Automatic grammar (`^[…](inflect: true)`) only works inside `Text(...)` literals. It renders as raw markup in `String(localized:)` concatenations, and it will pluralise verbs ("0 to removes"), so keep it to noun counts.
- `ScanStore.availableCategories` hides a category until its scanner is injected. The live app never shows a fake "Scanning…" for an engine that doesn't exist.

Performance and accuracy work happens **only on the real iPhone**, with the real library (the simulator has almost no photos). Use Instruments (Time Profiler, Allocations, Hitches) and the signposts in `Core/Logging/Log.swift`.

## 3. Architecture rules (MVVM)

- **View** (SwiftUI): layout and bindings only. No `import Photos/Contacts/Vision`. Thumbnails come from `ThumbnailView(id:)`.
- **ViewModel**: `@Observable @MainActor final class <Feature>ViewModel`, placed next to its view in `Features/<Feature>/`. It talks to **service protocols** injected from `AppEnvironment`, never to PhotoKit or Contacts types.
- **Services** (`Services/<Area>/`): protocol + a live implementation (an actor or `nonisolated`) + a `Fake*` implementation for previews and tests.
- **Engines** (`SimilarityEngine`, `DHash`, `BestShotRanker`, `ContactDeduplicator`, `ContactMerger`): pure, deterministic, and unit-tested.
- **Models**: `Sendable` value types carrying IDs, never `PHAsset`/`CNContact`/`CGImage`.
- **Shared state**: `ScanStore` and `CleanupCart` are the only app-wide `@Observable`s. Don't create new globals or singletons.
- **Concurrency**: Swift 6 strict mode with default MainActor isolation. Heavy work goes in actors or `@concurrent` functions; bound parallelism with task groups; check `Task.isCancelled`. No `DispatchQueue`, no `@unchecked Sendable` without a comment saying why it's safe.
- **Observation only**: no `ObservableObject`, `@Published` or Combine.
- **No third-party packages.** Apple frameworks only.

## 4. Design rules

- Use tokens only: `Color.sift.*`, `Font.sift.*`, `Spacing.*`, `Radius.*`, `Motion.*`. No hex colours, fixed font sizes or magic numbers in feature views.
- Reuse components from `Core/DesignSystem/Components/` before making new ones. A new shared component gets added to DESIGN_SYSTEM.md §8.
- Every user-facing string goes in `Resources/Localizable.xcstrings` (use plural variants for counts). Format bytes with `ByteFormatter`.
- Copy rules: never say “junk”, “boost”, “clear cache”, “virus”. Always name the consequence (“Delete 42 items · 3.1 GB”). Red (`destructive`) appears only on the final Review button.
- Every view has a `#Preview` using `AppEnvironment.preview(...)`, covering its empty, loading, populated and locked states where they apply.
- Accessibility: Dynamic Type to AX5, VoiceOver labels on thumbnails, 44 pt targets, Reduce Motion (DESIGN_SYSTEM §11).

## 5. Safety & privacy invariants (a violation is a blocker)

1. **Deletion only through Review.** `PHAssetChangeRequest.deleteAssets` and `CNSaveRequest` appear only in `Services/Cleanup/` and `Services/Contacts/ContactsService.swift`. `CleanupPlan` is built only by `ReviewViewModel`. Bonus features (swipe mode, compress) **add to the cart**; they never delete.
2. **Contacts backup first.** `DeletionService` writes the vCard backup before any contact mutation. Never request `CNContactNoteKey`.
3. **No network.** No `URLSession`, sockets, analytics or crash SDKs. Thumbnails use `isNetworkAccessAllowed = false`.
4. **No personal data in logs.** Log counts and `privacy: .private` identifiers only; never names, numbers, emails or file names.
5. **Honest copy.** Explain Recently Deleted. Label iCloud-only sizes. Never promise cache or junk cleaning.
6. **Every permission state works.** `.notDetermined / .denied / .restricted / .limited / .authorized` for Photos and Contacts: no crash, and no blank, unexplained screen.
7. **No placeholder data in production paths.** Fixtures and fakes live under `#if DEBUG` or in `SiftTests/`. Missing values display “Unknown”, never invented data.

Run the grep gates in §2 before every commit.

## 6. Workflow

- Work **one vertical slice at a time**, following the PRD §9 milestones. The first slice is Screenshots → Cart → Review → Delete → Summary, end to end, before any other category.
- **Bonus features only after the core loop passes on the device** (DECISIONS D14 order).
- Put requirement IDs in commit messages: `feat(similar): stream groups from time-window engine (FR-SIM-2)`.
- Definition of done for a slice:
  - [ ] Builds with zero warnings in Swift 6 mode
  - [ ] Unit tests for any new engine or ViewModel logic pass
  - [ ] Previews render in light and dark
  - [ ] Run in the simulator (seeded fixtures), and screenshots checked for layout, contrast and truncation
  - [ ] Verified on the real iPhone for anything touching PhotoKit, Contacts, deletion or performance (if no device is available now, list it as pending in the progress log)
  - [ ] Grep gates are clean
  - [ ] `.claude-progress.md` has a new entry appended
- Commit only when asked. Branch off `main` for anything risky.
- If a requirement is ambiguous, pick the option that is **safer for the user's data**, document it as an assumption in the progress log, and continue. Don't block on questions during implementation.

## 7. Things that look reasonable but are wrong here

- Comparing every pair of photos (O(n²)). Use the pipeline in ARCHITECTURE §6.1.
- Holding `PHAsset`s or `CGImage`s in arrays for the whole library. Keep compact features only.
- Calling `PHImageManager.default()` from views for grids. Use `ThumbnailProvider` (a `PHCachingImageManager` with start/stop caching).
- Pre-selecting items for deletion (D9).
- Telling users space is freed immediately after deletion (Recently Deleted keeps it for 30 days).
- Suppressing or re-implementing iOS's own delete confirmation.
- Adding a paywall, login or any network call (out of scope).
- Using Cleanup's name, colours, icon or copy.
