# Sift — Full Test Report

**Date:** 2026-09-24 · **Build:** `ec4c591` (main) · **Tester:** Claude (automated + manual on simulator), device data from the owner's iPhone
**Environments:** iPhone 17 Pro simulator (iOS 27, generated fixture library: 22 photos, 8 screenshots, 3 videos, 11 contacts) · iPhone 15 (iOS 27, owner's real library: 7,724 photos)
**Evidence:** `docs/verification-screenshots/01…12`

## Verdict: **PASS WITH FINDINGS — not ready to ship**

The core loop (scan → review → delete → summary) works end to end, the deletion-safety guarantees hold, and performance meets the PRD target. **Two high-severity bugs** found during this pass must be fixed before TestFlight, both in the "is the user looking at / keeping the right photo" area.

| Area | Result |
|---|---|
| Automated tests | ✅ 40/40 pass (10 suites) |
| Release build | ✅ builds; 6.3 MB; DEBUG calibration code fully stripped (0 matches in binary) |
| Safety & privacy gates | ✅ all clean (see §2) |
| Core loop on simulator | ✅ pass |
| Permission states | ✅ denied, full, limited · ⚠ one copy issue |
| Categories (6 screens) | ✅ functional · ❌ 1 high bug (Swipe) |
| Review / Delete / Cancel | ✅ pass · ❌ 1 high bug (Best reset after delete) |
| Accessibility (AX5 text) | ❌ dashboard hero breaks |
| Performance on real iPhone | ✅ 43.5 s cold / 2.0 s warm for 7,724 photos (measured earlier today) |

---

## 1. Findings (fix list, most severe first)

| # | Severity | Finding | Where | Evidence |
|---|---|---|---|---|
| **F1** ✅ fixed | 🔴 High | **Swipe card shows a stale photo.** When the card advances, the image stays on the previous photo if the new one is already in the memory cache; labels (size/date) change but the picture doesn't. A user can Keep/Remove while looking at the wrong photo. Regression from today's thumbnail cache (`ThumbnailView` keeps `@State image` across id changes and the task exits early on a cache hit). | `Core/DesignSystem/Components/Thumbnails.swift` · Swipe to sort | 12-swipe.png: "63 KB · 12 Sep" (a screenshot) and "107 KB · 6 Aug" both render the same mountain photo |
| **F2** ✅ fixed | 🔴 High | **Manual "Make Best" is lost after a rescan — and a delete triggers one.** iOS's delete prompt sends the app inactive→active; the deletion itself marks the library "changed", so the quiet foreground rescan runs and re-ranks Best from scratch. The photo the user chose to keep became the suggested deletion ("168 KB · 1 item"). Two fixes: persist Best overrides across rescans; don't mark the library stale for Sift's own deletions. | `State/ScanStore.swift` (`apply`, `setBest`), `App/RootView.swift` | log: rescan at 16:26:20 immediately after delete; dashboard card after delete |
| F3 ✅ fixed | 🟠 Medium | **AX5 (largest text) breaks the dashboard hero:** free-space number truncates ("24.89…"), "free of 494.33 GB" spills outside the ring, legend labels truncate ("Us…", "Si…"). Category icons overflow their fixed 44 pt tiles. Cards themselves reflow correctly to one column. | `StorageRing.swift`, `CategoryCard.swift` | 11-ax5-dashboard.png |
| F4 | 🟠 Medium | **Blur threshold misses a clearly blurred photo.** At the calibrated 45, 1 of 2 deliberately blurred fixtures is found (the dark scene is missed). The threshold rests on a single "blurry" label from the owner's phone. Needs ~5+ blurry labels, or a contrast-normalised measure. | `SimilarityConfig.blurThreshold` | 07-blurry.png |
| F5 ✅ fixed | 🟡 Low | Copy: **"7 photo or videos will be removed"** — automatic grammar pluralises the wrong word. | `ReviewView.swift` | 08-review.png |
| F6 ✅ fixed | 🟡 Low | Copy: **"1 photo look out of focus"** — verb doesn't agree. | `BlurryPhotosView.swift` | 07-blurry.png |
| F7 ✅ fixed | 🟡 Low | Copy: hero says **"Looking for things to clean…"** when Photos access is denied (nothing is being looked for). Should say access is needed. | `StorageRing.swift` | 02-denied-dashboard.png |
| F8 ✅ fixed | 🟡 Low | Copy: empty totals render as **"Zero KB"** (system formatter). Prefer "0 MB" or hide the number. | `ByteFormatter` | Large Videos with "Over 100 MB" filter |

---

## 2. Automated checks

| Check | Method | Result |
|---|---|---|
| Unit tests | `xcodebuild … test` | ✅ 40 tests / 10 suites: cart, review (incl. cancel keeps cart), screenshots filters, multi-index exactness vs brute force, union-find, best-shot ranking, grouper (bursts, time window, exact dups, anchor drift, size cap, change tracking), 20k-photo scale test, contacts (phone/name/email normalisation, transitive groups, vCard escaping), scan cache (round-trip, edits invalidate, corrupt file), library changes |
| Release build | `-configuration Release`, device | ✅ succeeded, 6.3 MB app |
| Debug-only code stripped | search the Release binary for the calibration log tag | ✅ 0 |
| No networking | search for URLSession / URLRequest / NWConnection | ✅ 0 |
| Deletion only in the deletion service | search for asset/contact delete calls outside `Services/Cleanup`, `Services/Contacts` | ✅ 0 |
| Deletion only after Review | `CleanupPlan(` outside `ReviewViewModel.swift` (init is `fileprivate`) | ✅ 0 |
| Contacts note key never fetched | search for the note key | ✅ 0 |
| No placeholder / fake data | the project's placeholder, lorem-ipsum and fake-name gate | ✅ 0 |
| Size | 6,789 lines app + widget, 637 lines tests, 0 third-party dependencies | — |

## 3. Manual test log (simulator, fresh install)

| # | Scenario | Expected | Actual | Result |
|---|---|---|---|---|
| 1 | Onboarding: welcome → Photos primer | Brand, 3 reasons, page dots | As expected | ✅ |
| 2 | Photos **Don't Allow** → contacts **Not now** | Dashboard with storage, locked banner + Open Settings, locked cards | As expected; hero copy wrong (F7) | ✅ ⚠ |
| 3 | Reinstall, **Allow Full Access** + Share All Contacts | Scan runs, all cards fill | Cold scan 22 photos **0.49 s**, **4 groups** (3 bursts + 1 exact pair) — the exact expected answer | ✅ |
| 4 | Dashboard numbers | Deduplicated freeable total, legend, 5 cards + Swipe | 23.8 MB; all present | ✅ |
| 5 | Similar Photos → **Smart select** | All but Best in every group | 8 of 12 selected, 1.3 MB | ✅ |
| 6 | Compare → **Make Best** on photo 2 | Becomes Best, moves first, auto-deselected | As expected | ✅ |
| 7 | Large Videos, "Over 100 MB" filter | Filter applies; empty state | Correct (fixtures < 100 MB); "Zero KB" (F8) | ✅ ⚠ |
| 8 | Large Videos, "All" | Largest first, durations, dates | 13.6 / 6.1 / 2.1 MB | ✅ |
| 9 | Blurry Photos | Both blurred fixtures | 1 of 2 (F4); grammar (F6) | ⚠ |
| 10 | Review | Exactly the 7 selected items, total, Recently Deleted note | As expected; grammar (F5) | ✅ ⚠ |
| 11 | Confirm → iOS prompt → **Don't Allow** | Nothing deleted, cart intact | 7 items still selected | ✅ |
| 12 | Confirm → **Delete** | Summary, dashboard updates, lifetime total | "1.1 MB cleaned up · 7 items"; "Sift has freed 1.1 MB so far" | ✅ |
| 13 | After delete, Similar Photos | Remaining group keeps user's Best | **Best reset; user's chosen photo now offered for deletion** (F2) | ❌ |
| 14 | Duplicate Contacts | 2 groups (1 pair merged earlier), reasons, merged preview | "Kavya Nair ↔ Nair Kavya" by name; Priya by number + name | ✅ |
| 15 | Swipe: right, left, Undo | Counters update, Undo restores | 1 kept / 1 to remove → Undo → 0 to remove | ✅ |
| 16 | Swipe card image | Card shows the photo it describes | **Stale image** (F1) | ❌ |
| 17 | AX5 text size | Everything readable, no truncation | Hero/legend truncate, icons overflow (F3) | ❌ |

**Tested earlier in this session (same build family), not repeated:** Limit Access path + banner + "Add photos"; drag-to-select range on Screenshots; real contact merge with vCard backup written before the change (file inspected); Home Screen widget (small + medium, live data); library change observer (added photo → banner → 0.08 s rescan; photo deleted in the Photos app → vanished from Sift); video playback sheet; light mode.

## 4. Real-device results (owner's iPhone 15, 7,724 photos, iCloud "Optimize Storage")

Measured earlier today via the device console (Debug build). A fresh re-measurement in this pass could not be taken: the phone locked and the console attach produced no output.

| Metric | Result | PRD target |
|---|---|---|
| Cold scan | **43.5 s** (≈ 56 s per 10k photos) | ≤ 60 s per 10k ✅ |
| Warm rescan | **2.0 s** | ≤ 50 % of cold ✅ |
| Grouping | 1,213 groups, 4,249 photos; thresholds calibrated from owner labels (precision 100 %, recall 95 % on 22 pairs) | ≥ 90 % precision ✅ (small sample) |
| Thumbnails | Fixed (were black on the iCloud-optimised library) | — |

**Not yet verified on the device:** a real delete, Similar Photos group quality by eye, instant dashboard after relaunch, cloud badges, widget, library-change refresh.

## 5. Not covered by this pass

- VoiceOver walkthrough (labels exist in code; no screen-reader run)
- Reduce Motion; light mode at AX sizes
- Release build **on device** / TestFlight
- Memory profiling in Instruments (peak-memory target in PRD §4)
- Contacts limited-access (iOS 18+) path

## 6. Recommended next steps

1. Fix **F1** and **F2** (both about keeping the right photo) and add a regression test for each.
2. Fix **F3** (AX5 hero) and the copy issues **F5–F8** (quick).
3. Collect ~5 more blurry labels on the device, then re-set **F4**.
4. Owner device check: real delete, groups by eye, widget.
5. Release build on the device → TestFlight.

## 7. Re-test after fixes (2026-09-24, later)

| Finding | Fix | Verification | Result |
|---|---|---|---|
| F1 | `ThumbnailView` stores the image together with the id it was loaded for (`LoadedThumbnail`) and never displays an image for a different id | Unit test `thumbnailNeverShowsAnImageLoadedForADifferentPhoto`; on simulator, Swipe cards 1→2→3 show three different photos (mountain, blurred sunset, screenshot) matching their size/date labels; screenshot grid shows each screenshot's own colour | ✅ |
| F2 | User Best choices stored (persisted in UserDefaults) and re-applied to every rescan; one choice per group; removed ids dropped. Sift's own deletions no longer mark results stale (10 s window set just before deleting) | Unit tests `manualBestSurvivesARescan` (incl. relaunch), `choosingAgainInTheSameGroupReplacesTheEarlierChoice`, `siftsOwnDeletionDoesNotTriggerARescan`; on simulator: Make Best on 168 KB → delete a screenshot via Review (no rescan logged) → forced full rescan at 16:36:39 → 168 KB still Best | ✅ (13-f2-best-kept-after-rescan.png) |

Tests: **44/44 pass** (4 new regression tests).

### Re-test of F3, F5–F8

| Finding | Fix | Verified on simulator |
|---|---|---|
| F3 | At accessibility sizes the free-space numbers move below the ring (smaller ring), the legend becomes one column with full labels, the "can be freed" pill becomes a rounded rectangle, and category icon tiles scale with `@ScaledMetric` | AX5: "25 GB · free of 494.33 GB" below the ring, legend "Used / Similar" untruncated, icons inside their tiles; default size unchanged |
| F5 | "N items from Photos will be removed" | "1 item from Photos will be removed" |
| F6 | "N photos out of focus" (no verb to agree) | "1 photo out of focus" |
| F7 | Hero shows a lock and "Photo access needed to scan" when access is denied | Denied state after fresh install |
| F8 | Zero bytes formatted numerically (MB unit, non-numeric formatting off) | "0 MB" on the Over 100 MB filter; unit test `zeroBytesIsNumeric` |

Tests: **45/45 pass**. Remaining open: **F4** (blur threshold needs more device labels).
