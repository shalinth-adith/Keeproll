# Keeproll — QA and Security Report, build 5 candidate

**Build:** 1.0 (4) plus Accidental Shots and Smart Trim, commit `0e6f5cc` · **Date:** 18 Oct 2026 · **Devices:** iPhone 17 Pro simulator (iOS 26); Release build compiled for device.

**Method:** three tracks.

1. **Automated checks.** Release build, 135 unit tests, the privacy grep gates, and a scan of the Release binary for DEBUG code and bundled fixtures.
2. **Hands-on walk.** Home, Results, both new screens, the trim sheet, Review, delete and Summary. The walk also covered dark mode, the largest text size, and Hindi. Deletions were checked against the Photos database. Extra test images were added for look-alikes: a portrait with an orange top, and two starfields.
3. **Code audit.** Three read-only reviews: Smart Trim, Accidental Shots, and a security pass over everything since the last review (`070025f`).

---

## Verdict

**Fix the High items before shipping build 5.**

Nothing deletes outside Review, there is no network code, and the Release binary is clean. The two features work end to end:

- Exactly the right items moved to Recently Deleted (51 → 48 live).
- The trimmed copies are exactly 12.0 s long.

But both detectors have look-alikes that real photos will hit. Smart Trim can also lose content that the confirmation copy promises to keep.

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 5 |
| Low | 8 |

---

## High

**A1. Portraits in red or orange clothes are filed as "Finger over the lens".** *Confirmed in the simulator.*

- **Where:** `AccidentalShotEngine.swift`, `fingerScore`.
- **Cause:** "smooth" is measured on a 32 × 32 render, where almost any surface is smooth. The finger rule never checks that the photo is out of focus.
- **Effect:** an orange top filling the bottom third covers only the bottom edge, so it passes the one-side rule. Red car doors, red walls and darker skin at one side will match the same way.
- **Fix:**
  - Require the photo to be soft (`sharpness < blurThreshold`).
  - Or measure smoothness on the 160 px greyscale the sharpness pass already builds.
  - Add the red-top portrait as a test.

**T1. A trimmed copy keeps only the first video and first audio track. The original then goes to Review with "same quality, date and place".** *Code audit; device check for Cinematic and spatial audio.*

- **Where:** `SmartTrimService.swift`, `composition(of:keeping:)`.
- **Effect:**
  - Cinematic depth and focus tracks are dropped, so depth edits are gone once the original is deleted.
  - Extra audio tracks (spatial audio / Audio Mix) are dropped.
  - Timed metadata and file-level QuickTime metadata are dropped.
- **Fix:** copy every track and the asset metadata. Or skip Cinematic, spatial and multi-audio videos (`PHAsset.mediaSubtypes`, track count).

---

## Medium

**A2. Starfields and city lights at night are filed as "Too dark to see".** *Confirmed in the simulator.*

- **Cause:** the brightest point is measured after shrinking to 32 × 32, so small stars average away.
- **Fix:**
  - Take the maximum and p98 from the 256 px thumbnail.
  - Bump `exposureVersion`.

**T2. A trimmed original can be hidden from Smart Trim for good.** *Confirmed in the simulator and the Photos database.*

- **Cause:** `trimmedVideos` is saved to UserDefaults, but the cart lives only in memory.
- **Effect:** after a relaunch, or if the user deselects the original in Review, the 42 s original stays in the library next to its 12 s copy. Smart Trim no longer shows it, and the saving is lost.
- **Fix:**
  - Store pending (original, copy) pairs, and show "Trimmed copy saved · remove original" while the copy exists.
  - Drop a pair once the copy is gone.

**T3. Cancelling while the copy is being saved leaves an untracked duplicate.** *Code audit. Too fast to reproduce in the simulator: the lossless export finished before Cancel.*

- **Cause:** the last cancellation check runs before `saveCopy`. If Cancel arrives during the save, the copy is written, but the original is never queued or marked.
- **Same bug:** `CompressVideoSheet`.
- **Fix:** once saving starts, always record the result. Hide Cancel during a short "Saving…" phase.

**T4. Dark video with important sound is cut, or offered as "Nothing worth keeping".** *Code audit, by design gap.*

- **Cause:** only brightness is checked. A baby monitor at night, someone talking in the dark, or a covered-lens voice note all count as dead.
- **Fix:**
  - Measure the audio level in each stretch (the `AVAssetReader` setup is already there), and keep stretches that aren't silent.
  - Reword the all-dark case to "Dark the whole way through · check the sound".

**A3 (device check). The "never the top edge" rule depends on image orientation.** *Code audit.*

- **Cause:** `UIImage.cgImage` drops `imageOrientation`. If PhotoKit ever returns a non-`.up` thumbnail, the protected top edge would be the photo's side, so sunsets could match.
- **Fix:**
  - Log the orientation on a device.
  - If it's ever non-`.up`, draw upright before computing stats.

---

## Low

| ID | Finding | Where |
|---|---|---|
| T5 | Review and Summary count a trimmed original's full size (2.3 MB), but the copy stays, so the net saving was 1.3 MB. Seen in the simulator. | `TrimVideoSheet.swift` cart entry |
| T6 | The 1 MB minimum is checked when offering, not when trimming: a copy 1 byte smaller is accepted. The HighestQuality fallback only runs if creating the session fails, not if the export fails. | `SmartTrimService.trim` |
| T7 | A failed audio insert is ignored (`try?`), so the copy can have silent gaps. | `SmartTrimService.swift:206` |
| T8 | A scan cancelled mid-measurement caches "not measured", so the time-based estimate (which overstates) sticks until the video changes. | `SmartTrimService.evaluate` |
| A4 | The blank rule catches deliberate solid-colour photos (paint swatches, fog, snow). Review protects them, but the label is wrong. | `AccidentalShotEngine.verdict` |
| U1 | At the largest text size, the bottom selection bar covers about 40 % of the screen on every list. | `SelectionBar` |
| U2 | Photos or videos added while the app is open don't appear until a rescan. Smart Trim and Accidental Shots have no pull-to-refresh, so Results' rescan button is the only way. | `ScanStore.isStale` |
| S1 | The privacy policy doesn't list the new on-device data: brightness statistics, video dead-stretch timings, which videos were trimmed. It also doesn't say that compressed and trimmed copies are added to the library. Nothing leaves the phone, so the App Store answers still hold. | `docs/site/privacy.md` |

---

## Passed

- **Release build:** no DEBUG fixtures, launch arguments or dev-only marker strings. No test images or videos bundled. The app target only includes `Keeproll/` and `Shared/`.
- **Tests:** 135 pass, 25 of them for the new features.
- **Privacy gates:**
  - No network code.
  - `deleteAssets`, `CNSaveRequest` and calendar removal appear only in their services.
  - `CleanupPlan` is still built only on Review.
  - Smart Trim only creates assets.
- **Privacy manifest:** still complete. New code reads only file size, and the new UserDefaults key is covered by CA92.1.
- **Logs:** the new log lines carry only counts, durations and sizes.
- **Temp files:** trim and compression outputs are removed on every path.
- **Accidental Shots on fixtures:**
  - The pocket shot, finger and blank frame were flagged.
  - The moonlit night, clear sky and warm-background photos were not.
- **Smart Trim on fixtures:**
  - The noisy pocket tail and the fully dark clip were offered.
  - The pure-black tail (would save about 30 KB) and the clip with a 4-second dark moment were not.
- **Trim result:** 2.3 MB became 962 KB, matching the estimate. The copy is lossless, exactly 12.0 s, and keeps its date and place. The original went to Review under its own header.
- **End to end:** Review → iOS prompt for exactly 3 items → 3 moved to Recently Deleted. Summary splits them by category.
- **Dark mode:** both screens, the timeline and Review look right.
- **Hindi:** every new string shows in Hindi. "Live Photos" stays in English as Apple's product name. An earlier English sighting was a stale install, not a bug.
- **Cache:** new sections are versioned, corrupt counts are bounded, and a mismatched version drops only that section.

## Not covered in this pass

- **Real device:** real fingertip and pocket photos, real night shots, Cinematic, spatial and slow-motion videos, HDR, a 30,000-photo library's one-time stats read, and battery and heat during the first Smart Trim scan.
- **VoiceOver:** not walked this pass. Labels exist in code.

## Fix order

1. A1 and T1: a wrong label on real photos, and possible content loss after Review.
2. A2, T2, T3, T4, A3.
3. The Low items, and the privacy policy wording (S1) before the App Store update.
