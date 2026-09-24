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
