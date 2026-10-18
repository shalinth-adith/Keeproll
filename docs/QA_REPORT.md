# Keeproll — QA and Security Report

**Build:** 1.0 (4), commit `620d218` · **Date:** 18 Oct 2026 · **Devices:** iPhone 17 Pro and 17 Pro Max simulators (iOS 26); Release build compiled for device.

**Method:** three tracks run together.

1. Automated checks: Debug and Release builds, 91 unit tests, the privacy grep gates, and a scan of the Release binary for DEBUG-only strings.
2. Hands-on UI walk from a fresh install: onboarding with every permission denied, then granted. Then Home, Results, Similar and Compare, Screenshots, Review (keep an item, cancel, confirm), Summary and Share, and Swipe. Deletions were checked against the Photos database, not only the screen.
3. A read-only code audit of the whole codebase for security, privacy and data-loss risks.

---

## Verdict

**Not ready to submit. Fix the 4 High items first.**

The core promise holds:

- There is no network code.
- Nothing is deleted outside Review.
- Cancelling the iOS prompt deletes nothing.
- Backups are written before any contact or calendar change.
- No personal data reaches the logs.
- DEBUG code is absent from the Release binary.

The High items are one UI dead end, one way to view the private vault without unlocking it, and two ways to lose contact data.

| Severity | Count |
|---|---|
| High | 4 |
| Medium | 8 |
| Low | 13 |
| Passed checks | 24 |

---

## High

**H1. Compare screen traps the user. No back button, and the edge swipe doesn't work.** *Found in UI, confirmed in code.*

- **Where:** `Keeproll/Features/SimilarPhotos/CompareView.swift:82-105`.
- **Cause:** The bottom thumbnail strip is a fixed-width row (48 pt per photo) with no scroll view. A group of 12 photos is about 660 pt wide, so the whole screen lays out wider than the phone. That pushes the back button and "Make Best" off both edges, and clips the strip itself.
- **Reproduce:** Open any similar group with more than about 6 photos and tap a photo. There is no back button. Tapping where it should be does nothing, and the left-edge swipe only pages the photo viewer. The only way out is to force-quit the app.
- **Fix:** Wrap the strip in a horizontal `ScrollView` with `.scrollTargetLayout`, and auto-scroll to the current photo.

**H2. The private vault can be viewed without unlocking.** *Code audit.*

- **Where:** `Keeproll/Features/Vault/VaultView.swift:49-54, 101, 121, 145`.
- **Cause:** Two gaps.
  - When the app goes to the background, `lockNow()` clears the vault list but never closes the open item sheet.
  - The privacy cover is drawn under that sheet.
- **Effect:**
  - With a vault photo open, the app-switcher snapshot shows the full private image.
  - On return, the photo is still on screen, and "Save to Photos" works, with no Face ID prompt.
- **Fix:** Close the sheet in `lockNow()` (move `open` into the view model). Put the privacy cover inside the sheet too, or make it cover the whole window.

**H3. Merging contacts silently loses fields, and the backup doesn't contain them.** *Code audit, confirmed in code.*

- **Where:** `Keeproll/Services/Contacts/ContactsService.swift:9-19, 121-162`. The UI promises "Merging keeps every number and email" and "nothing is lost".
- **Cause:** Several fields are never read, merged or backed up: social profiles, instant-message addresses, relations, anniversaries and other dates, department, and phonetic names. The photo is read but left out of the backup file. Notes can't be read at all, because Apple requires a special permission.
- **Effect:** "Merge all" then Confirm permanently deletes those fields from the merged-away cards. Contacts has no Recently Deleted, so they can't be recovered.
- **Fix:**
  - Fetch and merge the missing keys.
  - Write the photo into the vCard.
  - Warn that notes on removed duplicates can't be kept.
  - Remove the "nothing is lost" wording until all of this is true.

**H4. A rescan can make the cart delete both copies of a person.** *Code audit.*

- **Where:** `ContactDeduplicator.swift:66`, `DuplicateContactsViewModel.swift:37-56`, `ReviewViewModel.swift:141`, `ContactsService.swift:88-115`.
- **Cause:** Each scan gives contact groups new IDs. A merge queued before a rescan (which happens automatically when you return to the app after taking photos) stays in the cart. The group then looks un-merged again, so per-contact delete re-enables.
- **Reproduce:**
  1. Queue a merge of A into B.
  2. Rescan.
  3. Queue a delete of A.
  4. Confirm. Both cards can end up deleted.
- **Fix:**
  - Key merges by the member IDs, not a random ID.
  - Drop stale contact actions when contacts reload.
  - Refuse a plan where one contact appears in two actions.

---

## Medium

**M1. "Select recommended" can queue every photo of a moment.**

- **Where:** `DashboardViewModel.swift:25-33`, `SimilarityEngine.swift:123`.
- **Cause:** The blurry list is built separately from the similar groups and includes each group's Best.
- **Effect:** A low-light burst where every frame is soft gets fully selected in one tap.
- **Fix:** Exclude every group's Best from the recommended set.

**M2. Backups can't be reached after you leave the Summary screen, and are never deleted.**

- **Where:** `SummaryView.swift:80-91`, `ContactsService.swift:27-29`, `CalendarService.swift:114-117`.
- **Effect:** The "undo" disappears once you tap Done. The files pile up forever in device backups.
- **Fix:** Add a Backups list in Settings to share or delete each file, with a retention period.

**M3. Moving a Live Photo or RAW photo into the vault keeps only the still image.**

- **Where:** `VaultStore.swift:120-124`.
- **Effect:** The original is then queued for deletion as if it had been "moved", so the motion clip, RAW data and edit history are lost after 30 days.
- **Fix:** Copy every original resource, or don't queue such originals.

**M4. A vault index write failure can orphan the only copies.** *Needs device verification.*

- **Where:** `VaultStore.swift:180-184`.
- **Cause:** The index write uses `try?`, so failure is silent. The likely trigger is the phone locking during a long import.
- **Effect:** The originals still go to the cart. After deletion and relaunch, the vault looks empty.
- **Fix:** Make the write throw and roll back on failure, and keep a background task alive during import.

**M5. Deleting calendar events can notify other people.** *Needs device verification.*

- **Where:** `CalendarService.swift:42-84`, `CalendarCleanupFinder.swift:42-46`.
- **Cause:** Events with attendees aren't excluded, so removing one you organise can send cancellations. Duplicates also match across different calendars, so the "extra" copy may be the shared one.
- **Fix:** Skip events with attendees, and include the calendar in the duplicate key.

**M6. Similar-photo grouping over-merges when Vision is unavailable.** *Seen in UI.*

- **Where:** `SimilarityConfig.swift:22`, `SimilarityGrouper.swift:127`.
- **Effect:** One group of 12 mixed visibly different images.
  - On the simulator, Vision returns no feature prints, so grouping falls back to a coarse hash (distance ≤ 10 × slack), and chaining joins unlike images.
  - On a device this path runs only if Vision times out, but then it affects the whole scan.
- **Fix:** Tighten the fallback hash distance (for example ≤ 6) and keep the anchor check strict. Verify on the device.

**M7. Photo categories don't say they're locked on Home.**

- **Where:** `HomeViewModel.swift` (`checkSubtitle`), `open()`.
- **Effect:** With Photos denied, the Contacts and Calendar rows read "Needs access · tap to allow", but the seven photo rows look normal. Tapping one jumps straight to iOS Settings with no explanation.
- **Fix:** Show the same subtitle on the photo rows, and route the tap to the in-app explanation.

**M8. Compression keeps running after you leave.**

- **Where:** `VideoCompressionService.swift:118-120`.
- **Effect:** Closing the sheet doesn't cancel the export, and the copy is still saved. `exportAsynchronously` is deprecated in iOS 18.
- **Fix:** Cancel the export on task cancellation, and move to the async `export(to:as:)` API.

---

## Low

| # | Finding | Where |
|---|---|---|
| L1 | Onboarding page 2: the page dots are cut off by the bottom edge on a 6.1″ phone. | `AccessSetupView.swift` / `OnboardingView.swift` |
| L2 | The selection circle is almost invisible on white screenshots (white ring on white). | `Thumbnails.swift:95-100` |
| L3 | With Photos denied, Home still shows the primary "See what to clean" button and "Last scan: Just now", even though nothing was scanned. | `HomeView.swift`, `HomeViewModel.lastScanLabel` |
| L4 | The "Saved from Chats" subtitle truncates ("…WhatsApp and Telegr…"). | `HomeViewModel.checkSubtitle` |
| L5 | Saving the share image from the share sheet also closed the Summary sheet, so "Done" never ran and Results wasn't re-shown. Saved cards also land in your library and could later be flagged. | `SummaryView.swift` |
| L6 | The .ics backup records a one-day all-day event with an end date equal to its start date. Re-import may shorten it. Alarms and attendees aren't backed up. | `CalendarCleanupFinder.swift:83-86` |
| L7 | The vCard and ICS writers don't escape a lone `\r` or the Unicode line separators, and vCard lines aren't folded. A malicious contact name could inject fields into a backup. | `ContactDeduplicator.swift:93-120`, `CalendarCleanupFinder.swift:104-110` |
| L8 | A corrupted scan cache can crash every launch (unchecked array index, unbounded `reserveCapacity`). | `ScanCache.swift:196-218, 288-290` |
| L9 | File size and iCloud status are read through private keys (`fileSize`, `locallyAvailable`). If Apple renames them, every scan crashes. There is also a small App Review risk. | `AssetSizeService.swift:91-93`, `LivePhotoService.swift:75` |
| L10 | Vault: an import that finishes after locking reassigns the list in memory; a late progress update can stick "Copying N of N"; removing an item drops it from the index even if the file delete failed. | `VaultView.swift:56-74`, `VaultStore.swift:108-115` |
| L11 | Two diagnostics payloads in the same second overwrite each other. | `DiagnosticsService.swift:33-34` |
| L12 | `photos-redirect://` (Open Photos) is an undocumented URL scheme, so App Review can flag it. | `PermissionService.swift:95` |
| L13 | The vault relies only on the device passcode: no key is bound to unlocking, and it's included in iCloud and Finder backups. Deleting the app deletes the vault, which may hold the only copy. The UI should warn about this. | design |

---

## Passed

**Automated**

- Debug and Release builds have zero warnings.
- All 91 unit tests pass.
- Grep gates are clean: no network APIs, delete calls only in the allowed services, no contact-notes key.
- The Release binary contains none of the seed, calibration or reset strings.

**UI, verified against the Photos database**

- Onboarding: "Allow all" asks for Photos, then Contacts, then Calendar. Each row then shows the right state: denied rows say "Settings", granted rows show a check.
- With all permissions denied, Home and Results show clear locked states ("Photo access needed", "Locked · Tap to allow access") and nothing crashes.
- Recovery: "Allow access" on Home brings up the system prompt, and the scan populates.
- Screenshots: the age filter, Select all, and the selection bar count and size all work.
- Review: tapping an item keeps it (13 became 12).
- Cancelling the iOS prompt deletes nothing (17 screenshots before, 17 after), and the cart stays.
- Confirming deletes exactly 12 (17 became 5), and the kept one survives.
- Summary shows the right count-up, category row and Recently Deleted note.
- Share shows the card with "I freed 851 KB with Keeproll". Save Image wrote a 1440×1440 PNG with no crash.
- Swipe: removing one adds it to the cart, and Undo takes it back out.

**Code audit, with file:line evidence in the auditor's notes**

- Delete happens only through Review: the plan type's initialiser is file-private to the Review view model, and each delete or remove call appears exactly once.
- Contact and calendar backups are written first. If a backup fails, nothing changes; a failed calendar commit is reset.
- Compression, Live Photo conversion and vault import only add the original to the cart.
- Logs contain only counts, sizes and states. Every `print` is inside DEBUG.
- Recognised screenshot text is never stored or logged.
- Temp files from compression and Live Photo conversion are deleted on every exit path.
- The widget's shared container holds only two byte totals and a date.
- Vault, backups and their files use complete file protection. Vault file names are random IDs.
- Every launch-argument seed is DEBUG-only.
- Every async continuation resumes exactly once. Each `@unchecked Sendable` type is lock-guarded or immutable.
- Usage strings cover every permission requested. The privacy manifests match the APIs actually used.
- The one regex is bounded.

---

## Not covered in this pass

- **Real device:** Face ID vault, HEIC Live Photos, iCloud-only originals, a real Exchange calendar, performance at 7,000+ photos. Use the device-pass checklist.
- **Not re-walked this session** (each was verified in the simulator in earlier sessions): Large Videos and compression, Saved from Chats, Expired, Live Photos conversion, Contacts merge, Calendar, Vault, Settings, dark mode and AX5.

## Fix order

1. H1 (Compare dead end) and H2 (vault sheet): small, isolated changes.
2. H3 and H4 (contacts), then M1 (recommended includes Best).
3. M2 (backups list) and M5 (calendar attendees).
4. The rest before build 5.
