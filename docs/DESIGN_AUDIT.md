# Keeproll — Design Audit & Redesign (v2 → v3 minimalist)

> Date: 2026-09-25. Every screen was walked in the iPhone 17 Pro simulator, in light and dark mode, with seeded fixtures (22 photos, 6 videos, 6 calendar events, contacts locked). Findings are ordered by impact. Each one names the screen, the evidence, the fix, and its status. Screenshots of the result live in `docs/design-screenshots/`.

Severity: **P1** = hurts the core loop or first impression · **P2** = visible polish gap · **P3** = consistency / nice to have.

---

## 1. Findings

### Dashboard (first impression; the screen the reviewer sees first)

| # | Sev | Finding | Evidence | Fix |
|---|---|---|---|---|
| D1 | P1 | **Inverted hierarchy.** The hero is a 220 pt ring whose big number is *free space of total* (device trivia). Keeproll's actual value, "Up to 214 MB can be freed", is a pill underneath, and the six actionable cards start below the fold. | Hero card is ~1,000 px tall on a 2,622 px screen; "Ready to clean" header lands at y ≈ 1,550. | `StorageHero` v2: a horizontal layout. A 116 pt ring on the left (free % in the centre), and on the right the freeable amount as the hero number, with "free of total" as a footnote. Card height roughly halves; the first row of cards is above the fold. |
| D2 | P1 | **Redundant legend.** The six-item legend repeats every number that the cards directly below already show, and adds "Used 476 GB", which Keeproll can do nothing about. | Legend + cards show the same four values twice. | Legend removed. The ring's coloured segments stay; the cards carry the numbers. |
| D3 | P2 | **Uneven cards with dead space.** "Duplicate Contacts" and "Old Calendar Events" wrap to two lines, so their row is taller and the neighbours have blank bottoms; numbers sit at different heights across cards. | Rows 2–3 of the grid. | Cards use a short title (`CleanupCategory.cardTitle`: Similar, Screenshots, Blurry, Videos, Contacts, Calendar) and a horizontal layout: 36 pt tile on the left, title → number → caption on the right. Cards drop from ~160 pt to ~100 pt tall, every card in a row is the same height, and all six fit on the first screen with the hero. |
| D4 | P2 | **Chevron-in-a-circle noise.** Each card has a 28 pt chevron button that duplicates the card's own tap affordance. | Every card. | Chevron removed. State moved into the number line instead of a corner badge: “Locked” with a lock in `warning`, “All clear” with a check in `success`, “Scanning” with a spinner. |
| D5 | P2 | **No brand presence.** The home screen is a plain "Keeproll" large title; the mark that anchors onboarding and the app icon never appears again. | Dashboard nav bar. | A brand header: `KeeprollMarkTile` + "Keeproll" wordmark, with Rescan as a 44 pt icon button on the right. The system nav bar is hidden on the dashboard only. |
| D6 | P3 | **Unlabelled tools.** Swipe and Vault rows float after the category grid with no section header, and the debug "Calibrate" link sits between them and the "freed so far" line. | Below the grid. | "More tools" section header. "Freed so far" moves directly under the hero. The debug link is last, tertiary, and DEBUG-only as before. |
| D7 | P3 | **Two tools, one colour.** Swipe and Vault tiles are both accent teal, so they read as the same thing. | Tool rows. | Vault uses `catVault` (slate); Swipe keeps the accent. |

### Category screens (Similar, Screenshots, Blurry, Videos, Contacts, Calendar, Vault)

| # | Sev | Finding | Evidence | Fix |
|---|---|---|---|---|
| C1 | P2 | **Six hand-rolled headers.** Each screen re-implements hero number + caption + "N selected" chip with small drifts (spacing, animation, chip transitions). | Compare `SimilarPhotosView.header` with `LargeVideosView.header`. | New `CategoryHeader` component used by every category screen. One place to tune. |
| C2 | P2 | **Heavy tip banners.** Similar, Blurry, Contacts and Calendar each open with a full-width teal `InlineBanner` used for a *tip*, the same weight as a *warning*. On a calm design the loudest element on the screen shouldn't be a hint. | Screens 05, 07, 10 and Calendar. | New `HintRow`: icon + footnote, no fill. `InlineBanner` is kept for things that need attention (limited access, library changed, Recently Deleted). |
| C3 | P2 | **Broken "keep" row in Calendar duplicates.** The kept event renders as a seal icon and the text "Keep · Calendar" with no event title, unlike the contact rows where the kept contact shows its name and a "Keep" pill. | Calendar → Duplicate events. | The kept row shows the title, a "Keep" pill and the calendar name, matching the contacts pattern. |
| C4 | P3 | **Empty states are bare.** A lone symbol over text. | Any empty list. | Symbol sits in a 72 pt `accentSoft` circle; title and message unchanged. |
| C5 | P3 | **Best/selection chrome density.** In Similar groups a cell carries Best pill + size pill + check + border. Acceptable, unchanged; noted for a future pass. | Screen 05. | — |

### Review & Summary

| # | Sev | Finding | Evidence | Fix |
|---|---|---|---|---|
| R1 | P3 | Section headers use a 10 pt colour dot, while Dashboard and Summary use icon tiles for the same categories. | Review sheet. | 24 pt icon tile in the section header, same tile as the Summary rows. |
| R2 | — | The total card, thumbnails with "keep" minus buttons, the Recently Deleted note and the single red button are right. | Screen 08. | Unchanged. |
| S1 | — | Summary count-up, rings and per-category rows are right. | Screen 09. | Unchanged. |

### Global

| # | Sev | Finding | Fix |
|---|---|---|---|
| G1 | P3 | Card numbers use `title` (title2 semibold, default design) while hero numbers use rounded bold; two number voices. | New `Font.keeproll.display` (title2, rounded, bold, monospaced digits) for card and section numbers. |
| G2 | — | Tokens, Dynamic Type, Reduce Motion, VoiceOver labels, 44 pt targets, light/dark parity: all present and kept. | — |

### Found while verifying at AX5 (largest accessibility text size)

| # | Sev | Finding | Fix |
|---|---|---|---|
| A1 | P1 | **Selection bar unusable at AX5** (pre-existing): the Review button was squeezed to one letter per line next to the wrapped count. | `SelectionBar` stacks the text above a full-width Review button at accessibility sizes. |
| A2 | P2 | The new ring's centre “4 % free” grew past the ring; the selected chip squeezed the category header; the Rescan glyph outgrew its circle. | Centre text is capped to the ring's inner width; `CategoryHeader` puts the chip under the caption at AX sizes; the Rescan circle scales with its glyph up to 64 pt. |
| A3 | P3 | With the system bar hidden, dashboard content scrolled under the status bar with no fade. | A canvas-coloured scrim (solid over the status bar, 20 pt fade below) sits over the dashboard. |

---

## 1b. Second audit: the v2 dashboard judged as “minimalist, light, not clumpy” (owner request)

The v2 dashboard fixed the hierarchy but was still busy in chrome. Counted on the screenshot:

| # | Finding | Fix (v3) |
|---|---|---|
| M1 | **Nine boxes on one screen.** Hero card, six category cards, two tool rows, all white-filled with a hairline border. Content in containers reads as a wall of tiles. | No cards anywhere on content screens. The dashboard is a plain list on the canvas; rows are separated by `RowDivider` hairlines. |
| M2 | **Decoration carrying no information.** Brand tile glow, gradient icon tiles with coloured drop shadows, ring segments with glow. | All gradients, glows and shadows removed (dashboard, Review, Summary, onboarding, brand tile, badges, selection bar). Symbols are flat in their category colour. |
| M3 | **Three text lines and four colours per card.** “Locked” in bold orange, “All clear” in bold green competed with the numbers. | One line per row. Status in secondary grey words: “Allow access”, “None”. Empty rows dimmed and moved to the bottom. |
| M4 | **Two headings for one list, forced two-column grid, short titles.** | One column, full titles, no section headings; a gap and a hairline separate tools from categories. |
| M5 | **Hero with six parts and a ring that is 96 % grey on most phones.** | Text headline “213 MB can be freed”, one caption line, and a 6 pt `StorageBar` as the only graphic. |
| M6 | **Rescan twice** (bordered circle button and pull-to-refresh). | Bare symbol in the system bar; pull-to-refresh kept. Custom brand header and status-bar scrim removed; the system large title returns. |
| M7 | Elsewhere: bordered group cards on Similar, Calendar, Contacts, Videos; bordered total card and record list on Review; bordered rows and expanding rings on Summary; reason card and glow on onboarding; circle behind empty-state symbols. | All flattened to hairline-separated sections. Summary uses one light check symbol. |

Verified again in light, dark and AX5 (`01`, `05`, `06`); AX5 surfaced two more fixes: the caption fragments are one wrapping `Text`, and the row symbol column uses `minWidth` so large glyphs don't spill past the margin.

---

## 2. What was deliberately kept

- Onboarding (brand tile, glow, reason cards, page dots).
- Swipe to sort and Compare: their own chrome, selection bar hidden.
- Review: the one red button, the honest Recently Deleted copy, tap-to-keep thumbnails.
- The category colours, on symbols only, introduced once by the storage bar.
- Colour palette: contrast ratios were checked in v1 and are unchanged. (The v2 ring was replaced by the bar in v3.)

## 3. Verification (all done in this pass)

- Build: zero warnings, Swift 6 strict.
- Tests: 59/59 pass (no engine or ViewModel logic changed by this pass).
- Simulator (iPhone 17 Pro) screenshots of the v3 build in `docs/design-screenshots/`:
  `01-dashboard-dark`, `02-similar-light`, `03-videos-light`, `04-calendar-light`, `05-dashboard-light`, `06-dashboard-ax5`, `07-screenshots-ax5`, `08-screenshots-light`, `09-review-light`, `10-summary-light`.
- End-to-end: Screenshots → Select all → Review → Confirm → iOS delete prompt → Summary → dashboard shows “All clear” for Screenshots and “Keeproll has freed 440 KB so far”.
- Grep gates (§5 of CLAUDE.md): clean.

## 4. Files touched (v2 + v3)

- New: `Core/DesignSystem/Components/Headers.swift` (`CategoryHeader`, `SelectedChip`, `HintRow`, `SectionHeader`), `Components/Rows.swift` (`ListRow`, `CategoryRow`, `RowDivider`, `StorageBar`, `StorageSegment`).
- Removed: `Components/CategoryCard.swift`, `Components/StorageRing.swift`.
- Rewritten: `Features/Dashboard/DashboardView.swift` (plain list).
- Edited: `Tokens.swift` (`display`), `Models.swift` (`cardTitle`, unused by v3 but kept for the widget/AX labels), `ByteFormatter.swift` (`rounded`), `SelectionBar.swift` (AX stacking, no shadow), `Feedback.swift` (flat `EmptyState`, flat primer), `KeeprollMark.swift` (no glow), `OnboardingView.swift` (no glow), `MediaComponents.swift` (flat `VideoRow`), `ContactGroupCard.swift` (flat), every category view (headers and hints), `CalendarCleanupView.swift` (kept row, flat), `ReviewView.swift` and `SummaryView.swift` (flat, plain symbols), `SwipeView.swift` (flat round buttons).

## 5. Still to do (not design, listed so nobody assumes it's done)

- Real-device pass for the ring animation and the tile shadows on OLED.
- App Store screenshots at 1179×2556 come from the device, not the simulator.
