# Keeproll — Product Requirements Document

> **Working name:** Keeproll (“keeproll through your library, keep what matters”). It can be renamed later: change `PRODUCT_NAME` in `project.yml` and the strings in `Localizable.xcstrings`.
> **Source brief:** *AppFactory — Build a Storage Cleaner iOS App* (App Builder Intern selection task). Reference app: Cleanup: Phone Storage Cleaner. **Do not copy its branding, artwork or text.**
> **Status:** v1.0 · 2026-09-24 · Owner: Shalinth Adithyan

---

## 1. Summary

Keeproll is an iPhone app that frees up storage safely. It finds duplicate and similar photos, screenshots, large videos and duplicate contacts, shows the user exactly what it found, and removes only what the user approves on a final review screen. Everything runs on the device. There is no account, network or paywall.

**Core loop:** **Scan → Review → Clean.** Every screen exists to make one of those three steps faster, more accurate or safer.

## 2. Goals & non-goals

### Goals (ranked the way the brief is evaluated)
1. **The core loop works end to end** in every must-have category (scan, review, clean).
2. **Safety.** Nothing is deleted without explicit approval on the Review screen. Contacts get a local backup before any change.
3. **Fast and accurate on large libraries.** Results show up progressively, and the scan never does an O(n²) comparison of all photos.
4. **Usable and polished.** Clear hierarchy, Dynamic Type, dark mode, honest copy.
5. **Deliberate scope.** Bonus features only after the loop works. What was skipped, and why, is written down in the submission note.

### Non-goals (out of scope, from the brief)
- Payments, subscriptions, trials or paywalls. Everything is free and unlocked.
- Email cleaning.
- Clearing other apps' data, caches or “junk files”. **iOS does not allow this; never promise it, even in copy.**
- Login, accounts, cloud sync, analytics SDKs, or any network call.
- iPad, Apple Watch and Mac. The app is iPhone only, portrait first.

## 3. Users

| Persona | Situation | What they need |
|---|---|---|
| **The full phone** | “Storage almost full” banner, 20–60k photos, can't take a video | The single biggest win, fast. Large videos and similar bursts first. |
| **The careful keeper** | Afraid of losing a photo that matters | To see every item before it goes; a clear “best” pick; an undo path |
| **The contact hoarder** | Years of synced SIMs and accounts, the same person 3× | Safe merging that keeps every number and email |

## 4. Success metrics (acceptance targets)

| Metric | Target | How measured |
|---|---|---|
| Time to first result on the dashboard | < 1 s for storage and counts, < 3 s for screenshot/video totals | os_signpost + Instruments on device |
| Similar-photo scan, 10k-photo library | ≤ 60 s cold on an iPhone 13-class device; first groups visible < 5 s | Signpost intervals `scan.similar` |
| Rescan (warm cache) | ≤ 50 % of the cold time | Same |
| Peak memory during scan | < 250 MB | Instruments Allocations |
| UI responsiveness during scan | No hitch > 100 ms; grid scrolls at 60 fps | Hitches instrument |
| Similar-photo precision | ≥ 90 % of suggested groups judged “actually similar” on the test library | Manual audit of 50 groups |
| Deletions without passing through Review | **0** (hard invariant) | Code review + grep gate (see ARCHITECTURE §7) |

## 5. Functional requirements

IDs are stable. Reference them in commits, tests and tasks (for example, `FR-SIM-3`).

### 5.1 Onboarding & permissions (`FR-PERM`)
- **FR-PERM-1** On first launch, show a short welcome with the privacy promise (“Everything stays on your iPhone. Nothing is uploaded.”) before any system prompt.
- **FR-PERM-2** Show a **pre-permission primer** for Photos that explains the reason, then trigger the system prompt (`PHPhotoLibrary.requestAuthorization(for: .readWrite)`).
- **FR-PERM-3** Contacts primer: same pattern, but skippable (“Not now”). The app is fully usable without Contacts.
- **FR-PERM-4 Denied:** the affected category card shows a locked state with an explanation and an **Open Settings** button (`UIApplication.openSettingsURLString`). Other categories keep working. Returning from Settings re-checks status (scenePhase `.active`).
- **FR-PERM-5 Limited Photos access:** scan only the accessible assets. Show a persistent, dismissible banner: “Keeproll can see N photos you chose.” with **Add more photos** (`presentLimitedLibraryPicker`) and **Allow full access** (Settings). Set `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = YES`.
- **FR-PERM-6 Limited Contacts access (iOS 18+):** treat it like limited Photos. Deduplicate within the visible set and explain that duplicates outside the selection can't be found.
- **FR-PERM-7** The app never crashes or shows an empty, unexplained screen in any authorization state: `.notDetermined`, `.denied`, `.restricted`, `.limited` or `.authorized`.

### 5.2 Storage dashboard (`FR-DASH`)
- **FR-DASH-1** Show device **used / free / total** storage as a hero visual (ring or segmented bar) plus text (“38.2 GB free of 128 GB”). Source: `volumeTotalCapacityKey` and `volumeAvailableCapacityForImportantUsageKey`.
- **FR-DASH-2** One card per category (Similar Photos, Screenshots, Large Videos, Duplicate Contacts) showing **space that can be freed** (bytes) and the item count. Contacts show a count, because their bytes are negligible.
- **FR-DASH-3** Cards fill in progressively while scanning (“Scanning… 42 %”) and never block the whole screen.
- **FR-DASH-4** A persistent **selection bar** appears whenever the cart is non-empty: “12 items · 1.4 GB → Review”.
- **FR-DASH-5** Pull to refresh (or a Rescan button) re-runs the scan, using the cache.
- **FR-DASH-6** The freeable total counts each asset once, even if it appears in several categories (see FR-CART-2).

### 5.3 Similar photos (`FR-SIM`)
- **FR-SIM-1** Scan all accessible image assets (excluding screenshots, which have their own category) and group **exact duplicates** (anywhere in the library) and **near-identical shots** (bursts, re-takes, edited copies).
- **FR-SIM-2** Groups stream in while scanning, newest first. A progress indicator shows processed/total.
- **FR-SIM-3** In each group, mark one photo as **Best** (badge). Ranking: favourite › sharpness › face capture quality › resolution › edited. The user can change Best with a tap.
- **FR-SIM-4** Per group: “Select all but best”. Globally: **Smart select** (all but best, in every group). Nothing is pre-selected.
- **FR-SIM-5** Tap a thumbnail to open a full-screen compare view (swipe between group members, with the Best badge and size shown).
- **FR-SIM-6** Group header: date, count, freeable bytes.
- **FR-SIM-7** Photos that are only in iCloud show a small cloud badge, and their size is labelled as iCloud space (deleting them frees little on-device space).

### 5.4 Screenshots (`FR-SHOT`)
- **FR-SHOT-1** A grid of all screenshots (`mediaSubtypes` contains `.photoScreenshot`), newest first, with a total size.
- **FR-SHOT-2** Multi-select: tap to toggle, **drag across the grid to select a range**, and a “Select all” toggle. Filters: *All / Older than 30 days*.
- **FR-SHOT-3** Tap and hold (or use the context menu) to preview full screen.

### 5.5 Large videos (`FR-VID`)
- **FR-VID-1** A list of videos sorted **largest → smallest**, each row showing a thumbnail, duration, date and size.
- **FR-VID-2** Tap to preview in an inline player (`AVPlayer` via `requestPlayerItem`).
- **FR-VID-3** Size filter chips: *All / > 100 MB / > 500 MB*. The header shows the total of the current filter.
- **FR-VID-4** Multi-select into the cart.

### 5.6 Duplicate contacts (`FR-CON`)
- **FR-CON-1** Find duplicate groups by: same phone number (normalized), same email (normalized) or same full name (normalized, token order ignored). Each group shows its **match reason**.
- **FR-CON-2** For each group, preview the **merged result** (the union of names, phones, emails, addresses and URLs; the primary's photo kept). The user can pick the primary contact. The default is the most complete contact.
- **FR-CON-3** Actions added to the cart: **Merge group** or **Delete selected contacts**.
- **FR-CON-4** Before any contact change, write a **vCard backup** of every affected contact to the app's container. The Summary screen offers to share the backup file.
- **FR-CON-5** If a contact's container is read-only (for example, some Exchange accounts), report it per group and don't fail the batch.

### 5.7 Cart & review before delete (`FR-CART`, `FR-REV`)
- **FR-CART-1** A single app-wide cart holds every pending action: asset deletions and contact merges/deletions.
- **FR-CART-2** Assets are keyed by `localIdentifier`, so the same photo selected in two places counts once.
- **FR-REV-1** The Review screen lists **exactly** what will be removed, grouped by category: thumbnails and counts for media, names and the action for contacts, plus the **total space freed**.
- **FR-REV-2** The user can remove individual items from the Review screen.
- **FR-REV-3** One primary button, “Delete 42 items · 3.1 GB”, which needs one clear tap (it is not hidden behind a swipe). iOS then shows its own system confirmation for photos; we don't try to suppress it.
- **FR-REV-4** Copy on Review explains: *“Photos and videos go to Recently Deleted in the Photos app. The space returns once you empty it, or automatically after 30 days. Merged or deleted contacts are backed up in Keeproll first.”*
- **FR-REV-5** If the user cancels the system prompt, **nothing** is deleted and the cart stays intact.
- **FR-REV-6** Partial failures are reported item by item. The cart keeps the failed items.

### 5.8 Space-freed summary (`FR-SUM`), part of the core flow
- **FR-SUM-1** After cleaning: the bytes freed (animated count-up), items removed per category, a Recently Deleted reminder with an **Open Photos** button, and a contacts backup share link if one applies.
- **FR-SUM-2** Keep a running lifetime total (“Keeproll has freed 12.4 GB”) in local storage, shown on the dashboard.

## 6. Bonus features (only after §5 passes on a real device)

Priority order, chosen for demo value relative to cost and how much already-built code each one reuses:

| # | Feature | Why this rank | Reuses |
|---|---|---|---|
| B1 | **Swipe to keep or delete** | High demo value; about a day's work | Cart, thumbnails, Review |
| B2 | **Blurry photos** | Nearly free, since the scan already computes sharpness | Sharpness score, grid |
| B3 | **TestFlight build** | Asked for in submission; needs a paid developer account | — |
| B4 | **Compress large videos** | Real space win, and the loop stays safe (the compressed copy is saved first, then the original goes through Review) | Video list, Review |
| B5 | **Home Screen storage widget** | Small; needs an App Group | StorageService |
| B6 | PIN / Face ID private vault | Large, with separate security concerns | — (likely skip) |
| B7 | Calendar cleanup | Off-theme for storage | — (likely skip) |

## 7. Non-functional requirements

- **Platform:** iPhone, **iOS 17.0+**, portrait. Built with Xcode 27 and Swift 6.
- **Privacy:** no network entitlement is used, and the code has no `URLSession` or analytics/crash SDKs. Photos and contacts never leave the device. Logs never contain names, phone numbers, emails or image content.
- **Performance:** see §4. The scan is cancellable, resumes from the cache and pauses cleanly when the app goes to the background.
- **Accessibility:** Dynamic Type up to AX5, full VoiceOver labels, 44 pt touch targets, Reduce Motion honoured, and colour is never the only signal.
- **Localization:** English only for v1, but every string goes through `Localizable.xcstrings`.
- **Reliability:** no crash in any permission state, with an empty library, or while the library changes during a scan (via `PHPhotoLibraryChangeObserver`).

## 8. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| The asset file size API (`PHAssetResource` `fileSize` via KVC) is undocumented | Wrong or missing sizes | Wrap it in `AssetSizeService`, fall back to a pixel-count estimate, and cache the results |
| Feature-print thresholds vary by Vision revision | Bad groups | Named constants in `SimilarityConfig`, calibrated on the real device on Day 2 |
| Similarity chaining (A≈B≈C but A≉C) | Oversized groups | Check each new member against the group's anchor (complete linkage), and cap group size |
| Deleted photos stay in Recently Deleted | User sees “no space freed” | Honest copy on Review and Summary, and an Open Photos button |
| Contact deletion is permanent | Data loss | vCard backup before every mutation, plus the Review gate |
| Reading `CNContactNoteKey` needs an entitlement | Fetch throws | Never request the note key; build the vCard from explicit keys (verify on device on Day 3) |
| The simulator has almost no photos | Can't test at scale | `xcrun simctl addmedia` with a fixture set; performance tested on the real device only |
| Private photos appear in the demo recording | Privacy | Record in **Limited Access** mode with a curated set, which also demos FR-PERM-5 |

## 9. Milestones (5 days, brief assumed received 2026-09-24)

Build one thin vertical slice first (Screenshots → Cart → Review → Delete), then widen.

- [ ] **Day 1, Thu 24 Sep — Foundations and the first full loop.** Planning docs ✅. XcodeGen scaffold (iOS 17, Swift 6, fix the trailing-space names), design tokens and core components, onboarding and permissions (every state), StorageService and dashboard shell, PhotoLibraryService, **Screenshots → Cart → Review → Delete → Summary working end to end on the device.**
- [ ] **Day 2, Fri 25 Sep — Sizes, videos, similarity engine.** AssetSizeService and its cache, Large Videos (list, preview, filters), SimilarityEngine v1 (dHash plus time-windowed feature prints, union-find), thresholds calibrated on the real library, signposts added.
- [ ] **Day 3, Sat 26 Sep — Similar UI and contacts.** Similar Photos UI (groups, Best, Smart select, compare view), performance pass in Instruments on the large library, duplicate contacts (dedupe, merge preview, backup, cart integration).
- [ ] **Day 4, Sun 27 Sep — Polish and bonuses.** Empty, error, limited and denied states, accessibility pass, dark mode, app icon, motion and haptics. Bonus B1 (swipe) and B2 (blurry).
- [ ] **Day 5, Mon 28 Sep — Ship.** B3–B5 if there's time, a bug bash on the device, the 2–3 minute screen recording, the <150-word note, and the email submission. **Submit by the end of Day 5**; don't wait for the deadline.

## 10. Submission checklist

- [ ] Public (or shared) Git repo containing the Xcode project and a README
- [ ] TestFlight link (paid account confirmed; upload by Day 5 morning so external review has time)
- [ ] 2–3 minute screen recording on a real iPhone, with no private photos (use Limited Access)
- [ ] Note under 150 words: tools used, what works, what's missing, the hardest problem solved (likely: fast, accurate similar-photo grouping without O(n²) comparisons)
- [ ] Sent to the address given in the brief

## 11. Open questions

1. ~~Is a paid Apple Developer account available?~~ **Yes (confirmed 2026-09-24)**, so TestFlight (B3) is in scope.
2. The exact date the brief was received. The plan assumes 2026-09-24.
3. Is the name “Keeproll” approved?
