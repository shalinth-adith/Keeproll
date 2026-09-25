# Keeproll — Architecture (MVVM)

> How the code is organised, how data flows, and how the two hard problems are solved: **fast, accurate similarity on large libraries** and **deletion that can't happen without approval**. Locked decisions and their reasons are listed in [DECISIONS.md](DECISIONS.md).

---

## 1. Stack

| Concern | Choice |
|---|---|
| UI | SwiftUI, `NavigationStack`, iOS 17.0 minimum |
| State | Observation (`@Observable`); **no** `ObservableObject`/Combine |
| Language | Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency on |
| Photos | PhotoKit (`PHAsset`, `PHCachingImageManager`, `PHAssetResource`, `PHPhotoLibraryChangeObserver`) |
| Analysis | Vision (`VNGenerateImageFeaturePrintRequest`, `VNDetectFaceCaptureQualityRequest`), Accelerate (vImage/vDSP for dHash and sharpness) |
| Contacts | Contacts (`CNContactStore`, `CNSaveRequest`, `CNContactVCardSerialization`) |
| Persistence | SwiftData (`@ModelActor`) for the scan cache; `UserDefaults` for small settings (onboarding done, lifetime bytes freed) |
| Logging | `os.Logger` + `OSSignposter` |
| Tests | Swift Testing (`import Testing`) |
| Project | XcodeGen (`project.yml` is the source of truth; the `.xcodeproj` is generated and gitignored) |
| Dependencies | **None** (no SPM packages). Everything is Apple frameworks. |

## 2. Layers

```
┌─────────────────────────────────────────────────────────────┐
│ View (SwiftUI)          — layout, bindings, no logic        │
│   reads ↓ / sends intents →                                 │
│ ViewModel (@Observable, @MainActor, final class)            │
│   — screen state, user intents, formatting for display      │
│   calls ↓ (async)                                           │
│ Services (protocols; live impls are actors or nonisolated)  │
│   — PhotoKit, Contacts, Vision, storage, persistence        │
│   use ↓                                                     │
│ Models (value types, Sendable) + pure Engines (no I/O)      │
└─────────────────────────────────────────────────────────────┘
      App-wide shared state: ScanStore, CleanupCart (@Observable)
```

**Rules**
1. A **View** never imports Photos, Contacts or Vision. It gets thumbnails through `ThumbnailView(id:)`, which asks the `ThumbnailProvider` in the environment.
2. A **ViewModel** never touches PhotoKit or Contacts types directly. It talks to service **protocols**, so fakes can be injected in previews and tests.
3. **Services** do I/O. **Engines** (`SimilarityEngine`, `ContactDeduplicator`, `BestShotRanker`, `DHash`) are pure and deterministic, so they can be unit-tested with fixtures.
4. **Models** are `struct`/`enum`, `Sendable`, `Hashable`. They carry IDs (`localIdentifier`, `CNContact.identifier`), never `PHAsset`/`CNContact` objects, because those aren't Sendable.

## 3. Folder structure

```
Keeproll/                          # repo root
├─ project.yml                 # XcodeGen spec (targets, settings, Info.plist keys)
├─ CLAUDE.md                   # agent instructions
├─ docs/                       # PRD, DESIGN_SYSTEM, ARCHITECTURE, DECISIONS
├─ Keeproll/
│  ├─ App/
│  │  ├─ KeeprollApp.swift         # @main; builds AppEnvironment, injects it
│  │  ├─ AppEnvironment.swift  # dependency container (live / preview / test)
│  │  ├─ AppRouter.swift       # @Observable NavigationPath + Route enum + sheets
│  │  └─ RootView.swift        # onboarding gate → Dashboard
│  ├─ Core/
│  │  ├─ DesignSystem/         # Tokens (KeeprollColor, Font.keeproll, Spacing, Radius, Motion) + Components/
│  │  ├─ Logging/              # Log.swift (Logger categories), Signposts.swift
│  │  ├─ Formatting/           # ByteFormatter, DateFormatting
│  │  └─ Extensions/
│  ├─ Models/                  # MediaItem, SimilarGroup, ContactSummary, DuplicateContactGroup,
│  │                           # CartItem, CleanupPlan, CleanupResult, ScanProgress, StorageSnapshot,
│  │                           # PermissionState, AppError
│  ├─ Services/
│  │  ├─ Permissions/          # PermissionService
│  │  ├─ Storage/              # DeviceStorageService
│  │  ├─ Photos/               # PhotoLibraryService, ThumbnailProvider, AssetSizeService, LibraryChangeMonitor
│  │  ├─ Analysis/             # SimilarityEngine, DHash, SharpnessAnalyzer, BestShotRanker, SimilarityConfig
│  │  ├─ Contacts/             # ContactsService, ContactDeduplicator, ContactMerger, ContactBackupService
│  │  ├─ Scan/                 # ScanCoordinator (orchestrates all category scans)
│  │  ├─ Cleanup/              # DeletionService (THE ONLY place that deletes)
│  │  └─ Persistence/          # ScanCache (@ModelActor), CachedAssetRecord (@Model), SettingsStore
│  ├─ State/                   # ScanStore, CleanupCart (app-wide @Observable)
│  ├─ Features/
│  │  ├─ Onboarding/           # OnboardingView(+VM), PermissionPrimerView
│  │  ├─ Dashboard/            # DashboardView, DashboardViewModel
│  │  ├─ SimilarPhotos/        # SimilarPhotosView(+VM), GroupRow, CompareView(+VM)
│  │  ├─ Screenshots/          # ScreenshotsView(+VM), DragSelectGrid
│  │  ├─ LargeVideos/          # LargeVideosView(+VM), VideoPreviewView
│  │  ├─ Contacts/             # DuplicateContactsView(+VM), ContactGroupCard
│  │  ├─ Review/               # ReviewView, ReviewViewModel
│  │  ├─ Summary/              # SummaryView, SummaryViewModel
│  │  └─ Bonus/                # SwipeMode/, Blurry/, CompressVideo/ (only after core loop)
│  └─ Resources/               # Assets.xcassets (Colors/, AppIcon), Localizable.xcstrings
├─ KeeprollTests/                  # Swift Testing: Engines/, ViewModels/, Fakes/, Fixtures/
└─ KeeprollWidget/                 # (bonus B5) WidgetKit extension
```

Feature naming: `<Feature>View.swift` + `<Feature>ViewModel.swift`, with subviews in the same folder. A ViewModel lives next to its View, not in a global `ViewModels/` folder.

## 4. Dependency injection

```swift
// App/AppEnvironment.swift
@MainActor
struct AppEnvironment {
    let permissions: PermissionServicing
    let storage: DeviceStorageProviding
    let photos: PhotoLibraryProviding
    let thumbnails: ThumbnailProviding
    let sizes: AssetSizeProviding
    let contacts: ContactsProviding
    let deletion: DeletionServicing
    let scanStore: ScanStore        // app-wide state
    let cart: CleanupCart           // app-wide state

    static func live() -> AppEnvironment { ... }
    static func preview(_ fixture: PreviewFixture = .typical) -> AppEnvironment { ... }  // fakes, no PhotoKit
}
```

- Injected once at the root via `.environment(...)`. ViewModels are created by their View with the dependencies they need, e.g. `@State private var vm: ScreenshotsViewModel` initialised in `init(env:)`.
- `ScanStore` and `CleanupCart` are single `@Observable` instances shared by every screen, which is how the dashboard, category screens and Review stay in sync.
- The preview/test environment uses `Fake*` services with fixture data (`KeeprollTests/Fakes`, which also compiles into the app under `#if DEBUG` for previews).

## 5. Core models

```swift
struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String                 // PHAsset.localIdentifier
    let kind: Kind                 // .photo, .screenshot, .video, .livePhoto
    let creationDate: Date?
    let pixelSize: CGSize
    let duration: TimeInterval?    // videos
    var byteSize: Int64?           // filled by AssetSizeService
    let isFavorite: Bool
    let isCloudOnly: Bool
}

struct SimilarGroup: Identifiable, Hashable, Sendable {
    let id: UUID
    var memberIDs: [String]        // ordered: best first
    var bestID: String
    let kind: Kind                 // .exactDuplicate, .similar
    var freeableBytes: Int64       // sum(sizes) - size(best)
}

enum CartItem: Hashable, Sendable {
    case asset(id: String, category: Category, bytes: Int64)
    case contactMerge(groupID: UUID, primaryID: String, mergedIDs: [String])
    case contactDelete(id: String)
}

struct CleanupPlan: Sendable { let assetIDs: [String]; let contactActions: [ContactAction]; let totalBytes: Int64 }
struct CleanupResult: Sendable { let deletedAssetIDs: [String]; let bytesFreed: Int64; let contactsChanged: Int; let failures: [CleanupFailure]; let backupURL: URL? }
```

`CleanupCart` stores `[String: CartItem]` keyed by a stable key (`asset:<id>`, `contact:<id>`, `merge:<groupID>`), so an asset selected under both Similar and Screenshots is counted **once** (FR-CART-2).

## 6. Scan pipeline

`ScanCoordinator` (an actor) runs the category scans **concurrently, fastest first**, and publishes `ScanProgress` and results into `ScanStore` on the main actor.

```
t=0  ─┬─ DeviceStorageService.snapshot()                        (~ms)
      ├─ PhotoLibraryService.fetchScreenshots()  → ids + sizes     (fast: predicate)
      ├─ PhotoLibraryService.fetchVideos()       → sizes, sort desc (fast: few items)
      ├─ ContactsService.fetchAll() → ContactDeduplicator        (fast: ~thousands)
      └─ SimilarityEngine.scan(photos)                            (slow: streams groups)
```

### 6.1 Similar photos: avoiding O(n²)

Comparing every pair is 50M comparisons for 10k photos. Instead, the engine uses **two cheap candidate generators**, then a precise check.

1. **Fetch** all image assets except screenshots, sorted by `creationDate` ascending. Keep a `PHFetchResult` (it is lazy) and don't materialise all `PHAsset`s at once.
2. **Per asset** (bounded `withTaskGroup`, width = `ProcessInfo.activeProcessorCount`, inside `autoreleasepool`):
   - Request a **thumbnail at ~256 px** from `PHCachingImageManager` (`deliveryMode: .highQualityFormat`, `resizeMode: .fast`, `isNetworkAccessAllowed: false`, so it never downloads from iCloud).
   - Compute a **dHash** (64-bit: 9×8 grayscale, compare neighbours) and a **sharpness** score (variance of the Laplacian via vImage). These are cheap and cached.
   - Compute the **feature print** (`VNGenerateImageFeaturePrintRequest`) **only if** the asset has a time-neighbour within `SimilarityConfig.timeWindow` (default 60 s). Photos taken in isolation are almost never “similar shots”, and skipping them removes most of the Vision cost.
3. **Candidate edges:**
   - **Exact/near duplicates, whole library:** index the dHashes with **multi-index hashing** (split the 64 bits into 4 × 16-bit bands, one dictionary per band). By the pigeonhole principle, any pair with Hamming distance ≤ 3 shares at least one band exactly, so near-duplicates are found in ~O(n) instead of O(n²). Confirm with a full Hamming check ≤ `dHashThreshold`.
   - **Similar shots, time-windowed:** a sliding window over the date-sorted sequence. Compare the feature print only with assets inside the window, keeping at most `SimilarityConfig.maxNeighbours` (default 8). Accept if `distance ≤ featureThreshold`.
4. **Grouping:** union-find over the accepted edges, with a **complete-linkage guard**: before merging a new member in, check its distance to the group's **anchor** (first member) as well, so A≈B≈C≈D chains don't grow into one giant group. Cap group size at `maxGroupSize` (default 30).
5. **Streaming:** because the input is date-sorted, a time-window group is **final** once the window has moved past its last member. The engine yields finished groups through an `AsyncStream<SimilarGroup>`, so the UI shows groups within seconds. Exact-duplicate groups found through the dHash index are merged and emitted at the end.
6. **Best shot:** `BestShotRanker` runs **per group only** (a small n): favourite › sharpness › `VNDetectFaceCaptureQualityRequest` score (only if faces are present) › pixel count › has edits. It is a pure function of the per-asset features, so it's unit-testable.
7. **Memory:** keep only compact features (`UInt64` hash, `Float` sharpness, and feature prints **only within the sliding window**). Prints that have left the window are released. Target peak < 250 MB.
8. **Cancellation:** check `Task.isCancelled` per asset. Pause when the app moves to the background (scenePhase) and resume from the cache.

All thresholds live in `SimilarityConfig`, a struct of named constants with one comment per value. Starting values for the **revision 2** feature print (iOS 17): `featureThreshold ≈ 0.35` and `dHashThreshold = 3`. **These must be calibrated on the real device against the real library on Day 2** before the UI is tuned. Write the calibrated values and the date in DECISIONS.md.

### 6.2 Asset sizes

`AssetSizeService` (an actor): `PHAssetResource.assetResources(for:)`, sums `value(forKey: "fileSize")` for the original resources (this is undocumented KVC, so it's wrapped and defensive). Fallback: an estimate from `pixelWidth × pixelHeight × bytesPerPixelEstimate` (or the duration × bitrate estimate for video), flagged `isEstimated`. Results are cached.

### 6.3 Scan cache

`ScanCache` is a `@ModelActor` over SwiftData `CachedAssetRecord { localIdentifier (unique), modificationDate, byteSize, dHash, sharpness, faceQuality? }`. A record is valid only if `modificationDate` matches the asset's current one. Feature prints are **not** cached in v1 (they're only computed for time-neighbours). If profiling shows that warm rescans miss the ≤ 50 % target, cache the archived `VNFeaturePrintObservation` (it's `NSSecureCoding`) with `@Attribute(.externalStorage)`.

### 6.4 Library changes

`LibraryChangeMonitor` registers a `PHPhotoLibraryChangeObserver`. On a change, it removes deleted IDs from `ScanStore`/`CleanupCart` right away and marks the affected categories stale (a “Rescan” affordance appears). A full rescan isn't forced automatically.

### 6.5 Duplicate contacts

- `ContactsService` fetches with **explicit keys**: identifier, name components, nickname, organization, phones, emails, postal addresses, URLs, birthday, `imageDataAvailable`, `thumbnailImageData`. **Never `CNContactNoteKey`**, which needs an entitlement.
- `ContactDeduplicator` (pure):
  - Name → lowercase, diacritics folded, whitespace collapsed, tokens sorted.
  - Phone → digits only, last 10 digits, with ≥ 7 digits required.
  - Email → trimmed and lowercased.
  - Union-find on shared phone OR email OR identical non-empty normalised name. Each group records its `MatchReason`s. Name-only matches are shown as lower confidence.
- `ContactMerger` (pure) builds the merged value (the union with values deduplicated by their normalised form). The default primary is the contact with the most non-empty fields.
- `ContactBackupService` writes a `.vcf` of every contact about to be changed to `Application Support/Backups/contacts-<ISO8601>.vcf` **before** any `CNSaveRequest` runs.

## 7. Deletion safety

This is the most important invariant in the app.

```
Category screens ──(select)──▶ CleanupCart ──▶ ReviewView ──(tap Delete)──▶ ReviewViewModel.confirm()
                                                                                  │
                                                         DeletionService.execute(plan) ◀─┘
                                                           1. ContactBackupService.backup(affected)
                                                           2. PHPhotoLibrary.performChanges { deleteAssets }  → iOS system prompt
                                                           3. CNSaveRequest (merge updates + deletes)
                                                           4. return CleanupResult → SummaryView
```

**Invariants (enforced by code review and a grep gate in CLAUDE.md):**
1. `PHAssetChangeRequest.deleteAssets`, `CNSaveRequest.delete` and `CNSaveRequest.update` appear **only** in `Services/Cleanup/` and `Services/Contacts/ContactsService.swift` (the live store wrapper that `DeletionService` calls).
2. `DeletionService.execute(_:)` takes a `CleanupPlan`, and a `CleanupPlan` can **only** be built by `ReviewViewModel` (its initialiser is `fileprivate` to the Review feature, via a factory in `ReviewViewModel.swift`). There's no other code path that can build one.
3. Swipe mode, compress video and all other bonus features **add to the cart**; they never delete directly.
4. If the user cancels the system prompt (a `PHPhotosError.userCancelled` error), the result is “0 deleted” and the cart is unchanged.
5. Photos are deleted before contacts; a failure in one doesn't roll back the other, but both are reported.
6. After success, remove the deleted IDs from the cart and the scan results, and add `bytesFreed` to the lifetime total.

## 8. Navigation

`AppRouter` (`@Observable`) owns `path: [Route]` and `presentedSheet: Sheet?`.

```swift
enum Route: Hashable { case similar, screenshots, videos, contacts, compare(groupID: UUID, startID: String), swipe }
enum Sheet: Identifiable { case review, summary(CleanupResult), videoPreview(id: String), permissionPrimer(PermissionKind) }
```

Review is a **sheet** (a deliberate, modal decision). Summary replaces Review inside the same sheet, and dismissing it returns to the dashboard.

## 9. Permissions

`PermissionService` exposes `photos: PermissionState` and `contacts: PermissionState` (`.notDetermined`, `.denied`, `.restricted`, `.limited`, `.authorized`) and re-reads them on `scenePhase == .active`. Info.plist keys are set in `project.yml`:

- `NSPhotoLibraryUsageDescription`: “Keeproll looks at your photos and videos on this iPhone to find duplicates, screenshots and large videos. Nothing is uploaded.”
- `NSContactsUsageDescription`: “Keeproll checks your contacts on this iPhone to find duplicates you can merge. Nothing is uploaded.”
- `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`: `YES`

Limited contacts status (`CNAuthorizationStatus.limited`) exists on iOS 18+ only, so check it inside `if #available(iOS 18, *)`.

## 10. Concurrency model

- The default isolation is `MainActor` (a project setting), so Views, ViewModels and the app-wide stores are main-actor.
- Heavy work runs in **actors** (`ScanCoordinator`, `AssetSizeService`, `ScanCache`) or in `nonisolated` pure engines with `@concurrent` async functions. Vision and vImage calls never run on the main actor.
- Data crosses boundaries only as `Sendable` value types. `PHAsset`, `CNContact` and `CGImage` stay inside the service that created them.
- Progress flows as `AsyncStream<ScanEvent>` → the `ScanStore` applies it on the main actor, **throttled** to ≤ 10 UI updates per second.
- Structured concurrency only: no `DispatchQueue`, no detached tasks except inside `@concurrent`. The scan task is owned by `ScanStore` and cancelled when a rescan starts.

## 11. Errors & logging

- `AppError: LocalizedError` has cases such as `permissionDenied(kind)`, `photoLibrary(underlying)`, `contactsReadOnly(containerName)`, `deletionCancelled` and `partialFailure(count)`. ViewModels map these into user-facing copy; Views never show `error.localizedDescription` from Apple frameworks directly.
- `Log` wraps `Logger(subsystem: "me.adithyan.shalinth.Sift", category:)` with categories `scan`, `photos`, `contacts`, `cleanup`, `ui`, `perf`. Log method entry/exit and decision points at `.debug`. **Never log contact names, numbers, emails or file names.** Log counts and hashed IDs only, and mark any identifier `privacy: .private`.
- `Signposts`: intervals `scan.similar`, `scan.sizes`, `scan.contacts`, `cleanup.execute`, used to check the §4 targets in the PRD with Instruments.

## 12. Testing strategy

| Layer | How | Examples |
|---|---|---|
| Engines (pure) | Swift Testing with fixtures | dHash of known images; multi-index lookup finds all pairs with Hamming ≤ 3; union-find + complete-link guard; BestShotRanker ordering; phone/email/name normalisation; ContactMerger union |
| ViewModels | Swift Testing + `Fake*` services | selection toggles update the cart; Smart select excludes Best; Review total = the sum of unique items; cancel keeps the cart |
| DeletionService | Fake photo/contact stores | backup happens before mutation; cancel → 0 deleted; partial failure reported |
| UI | Simulator run + screenshots | Seed with `xcrun simctl addmedia booted KeeprollTests/Fixtures/Photos/*` (fixture set: near-duplicate bursts, exact copies, screenshots, a few videos) |
| Performance & accuracy | **Real iPhone only** | Instruments Time Profiler + signposts on the real library; manual precision audit of 50 groups |

Commands are in `CLAUDE.md`.
