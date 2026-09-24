# Sift — Decisions Log

> Locked project-wide decisions. Agents read this **before** writing code. Don't silently contradict an entry; if one needs to change, add a dated `### Amendment` under it. The original text is never edited.

---

**D1 — iOS 17.0 minimum, iPhone only, portrait.**
Why: the brief says iOS 17+; `@Observable` needs 17. APIs newer than 17 (limited Contacts access, `ContactAccessButton`) go behind `if #available`.

**D2 — XcodeGen manages the project.**
Why: a widget target (B5) and the Info.plist keys have to be added by agents, and hand-editing `project.pbxproj` is fragile. `project.yml` is the source of truth; `*.xcodeproj` is gitignored. Bundle ID `me.adithyan.shalinth.Sift`, team `649T62WKAQ` (same as the other projects).

**D3 — The folder and project names have no spaces.**
Why: the template was created as `cleaner_storage /` and `cleaner_storage .xcodeproj` (trailing space), which breaks shell scripts and `xcodebuild` arguments. Rename the folder to `Sift` (or at least drop the trailing space) and generate `Sift.xcodeproj`.

**D4 — Swift 6 language mode, default MainActor isolation, no third-party dependencies.**
Why: compile-time data-race safety for a heavily concurrent scanner; zero dependencies keeps review and privacy claims simple.

**D5 — MVVM with protocol-backed services and pure engines.** See ARCHITECTURE §2.
Why: the evaluators will ask “explain what you built”. Clear layers make that easy, and pure engines can be tested without a photo library.

**D6 — Similarity = dHash multi-index (whole library) + feature prints in a 60 s time window + union-find with an anchor check.**
Why: comparing all pairs is O(n²) and fails the “fast on large library” criterion. Near-identical *shots* happen close together in time; exact *duplicates* can be anywhere but hash to near-equal dHashes. Thresholds must be calibrated on the device (Day 2); record the values here as an amendment.

**D7 — Thumbnails never download from iCloud (`isNetworkAccessAllowed = false`).**
Why: speed, the privacy promise, and cellular data. iCloud-only assets without a local thumbnail are skipped in similarity and badged elsewhere. Video *preview* may allow network access: it's an explicit user tap, and the data comes from the user's own iCloud.

**D8 — Screenshots are excluded from Similar Photos.**
Why: they have their own category, and near-identical screenshots (same app UI) would create noisy groups.

**D9 — Nothing is pre-selected. Smart select is one explicit tap.**
Why: the brief evaluates safety. Pre-selection makes the user responsible for *un*-selecting. One tap keeps the speed.

**D10 — A single CleanupCart + a sheet-presented Review is the only path to deletion.** `CleanupPlan` can only be constructed in the Review feature. See ARCHITECTURE §7.
Why: “Nothing is deleted without approval” is evaluation criterion #2; a structural guarantee beats discipline.

**D11 — Contacts get a vCard backup before any merge or delete. `CNContactNoteKey` is never requested.**
Why: contact deletion is permanent (there's no Recently Deleted). The note key needs a special entitlement.

**D12 — Honest space copy.** Review and Summary explain Recently Deleted (30 days). Numbers for iCloud-only assets are labelled. We never mention caches, junk or boosting.
Why: the brief explicitly forbids promising what iOS doesn't allow; trust is the product.

**D13 — Scan cache in SwiftData (`@ModelActor`), keyed by `localIdentifier` + `modificationDate`. Feature prints aren't cached in v1.**
Why: sizes, hashes and sharpness are small and expensive to recompute. Prints are only computed for time-neighbours; revisit if warm rescans exceed 50 % of the cold time.

**D14 — Bonus order: Swipe → Blurry → TestFlight → Compress video → Widget. Vault and Calendar are skipped** unless everything else is done.
Why: demo value relative to cost, and reuse of existing code (see PRD §6). Every bonus feature routes deletions through the cart.

**D15 — No auth, no network, no analytics.** The global “dev-login bypass” convention is **N/A** for this project (there's no auth layer). The auth-bypass verification row in reports reads “N/A — no auth”.

**D16 — The demo is recorded in Limited Photos Access mode with a curated set of photos.**
Why: it keeps private photos out of the recording (a rule in the brief) and demonstrates limited-access handling at the same time.

### Amendment — 2026-09-24 (D14)
A paid Apple Developer account is confirmed. **TestFlight (B3) is committed, not optional.** Upload the first build at the end of Day 4, so any Beta App Review for external testers can finish before submission. Use the internal testing group as a fallback if external review is slow.

### Amendment — 2026-09-24 (D3)
The **outer local folder is kept** as `cleaner_storage ` for now, because renaming it mid-session would break the active Claude Code session. Everything inside has no spaces (`Sift/`, `Sift.xcodeproj`), and the GitHub repo is named `Sift`, so every clone is clean. Rename the local folder by hand between sessions if you want to.

### Amendment — 2026-09-24 (D13)
The scan cache is a **flat binary file** (`ScanCache`, an actor) instead of SwiftData. The cache is a pure key-value lookup keyed by `localIdentifier` + modification date; it needs no queries or relationships. A flat file loads ~10k records (feature prints included) in milliseconds and avoids SwiftData's `@Model`/`@ModelActor` friction under Swift 6 with default MainActor isolation. Feature prints **are** cached (not deferred as first planned), so a warm rescan does no Vision work at all. The file is written atomically with file protection; a corrupt or old-format file is ignored and rebuilt.

### Amendment — 2026-09-24 (D6)
- **Vision runs on one dedicated serial queue with a 4 s watchdog** (`FeaturePrintService`). Running `VNImageRequestHandler.perform` concurrently from the task group deadlocked the scan on the simulator: every cooperative-pool thread was parked in Vision's `dispatchGroupWait`. If Vision ever times out, it's disabled for the rest of the process and similar shots fall back to dHash (distance ≤ 10 inside the time window).
- **Exact duplicates keep the highest-fidelity file** (most pixels, then the largest file, then the earliest), not the "sharpest": JPEG re-compression artefacts inflate the Laplacian score, so the worse copy looked sharper.
- Screenshots are excluded in code, not with a `(mediaSubtypes & …) == 0` fetch predicate, which PhotoKit returned only 1 of 22 photos for.
- Starting thresholds: feature distance 0.45, anchor slack 1.35, duplicate dHash ≤ 3, fallback dHash ≤ 10, blur (Laplacian variance) < 60. **Still to calibrate on the real iPhone library.**

### Amendment — 2026-09-24 (D7, first real-device run: iPhone 15, 7,724 photos, iCloud "Optimize Storage")
- **Thumbnails use opportunistic delivery.** `.highQualityFormat` with network off returned *nothing* for photos whose original lives in iCloud, so grids and the calibration screen showed black squares. Opportunistic delivery shows the local small copy first and upgrades when it can.
- **Single-photo views the user opens (Compare, Calibrate) may load from the owner's iCloud**, like video preview. Grids and the scan never touch the network.
- **The scan asks for `.fastFormat` first** (PhotoKit's cached thumbnail, no decode), falling back to a local `.highQualityFormat` decode when the fast copy doesn't exist (error 3303 on freshly imported media).
- **Sharpness is measured at a fixed 160 px long edge** so scores are comparable whatever size PhotoKit returns. Cache format bumped to v2.
- First device numbers (before these fixes): cold scan 81 s for 7,724 photos (too slow vs. PRD target); at feature threshold 0.45, 39 % of photos were grouped (too loose; distance histogram peaks at 0.45–0.55). Thresholds to be set from on-device labels.

### Amendment — 2026-09-24 (D6, thresholds calibrated on device)
Calibrated with the DEBUG Calibrate screen on the owner's iPhone 15 (7,724 photos). Labels stayed on the device; only aggregate numbers were read from the console.
- **Feature threshold 0.45 → 0.75.** 22 labelled time-window pairs (21 "same moment", 1 "different"). At 0.45: precision 100 %, recall 52 %. At 0.75: precision 100 %, recall 95 % (20 pairs). The single "different" pair sits between 0.75 and 0.80, so 0.75 is the loosest value with no false matches. The tool's own pick (0.85, 95 % precision) was rejected: it rests on one negative example.
- **Anchor slack 1.35 → 1.15** (anchor distance ≤ 0.86), so a looser pair threshold doesn't let chains drift.
- **Blur threshold 60 → 45** on the fixed 160 px scale. 12 labelled photos: blurry at 33, sharp at 57 and above; 45 separates them and flags about the softest 1 % of the library (sharpness p1 = 57, p50 = 601).
- **Caveat:** 22 pairs and 12 photos from one library. Enough to fix gross mis-settings (the old 0.45 missed half of true duplicates), not a benchmark. Nothing is pre-selected (D9), so the cost of a borderline suggestion is one tap.
- **Warm rescan on device: 7,724 photos in 2.04 s** (all features from the cache).

### Amendment — 2026-09-24 (D6, scan speed on device)
Cold scans of the same 7,724-photo library on iPhone 15 (Debug build), each with the cache cleared via the DEBUG `-SiftResetCache` launch argument:

| Change | Cold scan |
|---|---|
| First run (high-quality thumbnails, 1 Vision queue, batches of 48) | 81 s |
| Fast-format thumbnails, calibrated thresholds | 59.5 s |
| 3 Vision lanes | 62 s (no gain: the Neural Engine serialises) |
| Sizes read in parallel in the workers; PHAsset passed, not re-fetched | 50 s |
| Continuous pipeline + reorder buffer instead of batches; emit once a second | **43.5 s** (≈ 56 s per 10k: inside the PRD target) |
| Grouper reports only changed groups to emit | pending measurement |

Vision is now the floor: 4,753 prints, ~98 s of Vision execution across the lanes. Warm rescan: 2.04 s. Group results were identical across all speed changes (1,213 groups, 4,249 photos), and the simulator fixture still yields exactly 4 groups.

### Amendment — 2026-09-24 (blur detection, test report F4)
**Focus score = √(Laplacian variance) ÷ pixel standard deviation** (contrast-normalised), replacing raw Laplacian variance. Raw variance scales with contrast, so a blurred dark photo scored 47.6 and slipped past the 45 threshold, while sharp low-contrast photos (fog, dim rooms) would be flagged. Measured on the fixture library: blurred 0.10–0.14, sharp 0.25–0.33, so a 2× gap. **Threshold 0.18** (between the two). Cache format v4 (scores changed meaning). The Calibrate screen's blur queue now samples mostly the softest 3 % of the library, since even sampling produced only 1 blurry photo in 12 labels. **Still to confirm with owner labels on the device.**

### Amendment — 2026-09-24 (D14, the last three bonus features)
All three follow D10: nothing leaves the library or the calendar except through Review.
- **Compress large videos.** HEVC 1080p export (720p fallback) with `AVAssetExportSession`. The new copy is saved to Photos first, with the original's date, location and favourite flag; only then is the original **added to the cart**, never deleted. It's offered only when the estimated saving is at least 20 MB and 25 % of the file, and the copy is thrown away if it isn't at least 10 % smaller. The export may download an iCloud original: the user started it on a single video.
- **Private vault ("PIN / Face ID").** Unlocked with `.deviceOwnerAuthentication` (Face ID, falling back to the device passcode), so Sift never stores a PIN of its own. Without a passcode the vault is unavailable, not unprotected. Files sit in Application Support/Vault with `.complete` file protection, and the vault re-locks when the app goes to the background and is covered in the app switcher. Adding photos **copies** them in; the originals go to the cart for Review. Removing a vault item is permanent and confirmed in its own dialog, since it's Sift's only copy.
- **Calendar cleanup.** Suggests exact duplicates (same title, start, end and all-day flag; the first is kept) and events that ended over a year ago. It covers only non-recurring events in editable calendars (no birthdays, subscriptions or repeating series), since deleting "this occurrence" of a series is rarely what people mean. It needs full calendar access (iOS 17). An `.ics` backup is written before anything is removed, shared from the Summary like the contacts `.vcf`, and all removals are committed together.
