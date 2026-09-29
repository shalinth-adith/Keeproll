# Keeproll — Design System

> Source of truth for how Keeproll looks, moves and speaks. Code lives in `Keeproll/Core/DesignSystem/`. **Never hard-code a colour, font, spacing or radius in a feature view.** Use a token. If the token you need doesn't exist, add it here first, then in code.
>
> **v4, "warm & alive" (2026-09-26).** The v3 flat list read as plain and empty. v4 adds a proper entry screen (Home) between onboarding and the results dashboard, brings back soft elevation and the category gradient tiles, puts the storage ring on a brand-gradient hero, and gives onboarding three illustrated heroes. Depth comes from one soft shadow step and one gradient family, never from borders. The reasoning and evidence are in [DESIGN_AUDIT.md](DESIGN_AUDIT.md) §1c. Screenshots of the current build: `docs/design-screenshots/`.

---

## 1. Principles

1. **Calm, not alarming.** Many cleaner apps use scare tactics (“Your phone is full of junk!”, red warnings, fake virus scans). Keeproll is the opposite: a tidy desk, not an alarm. Red appears **only** on the final destructive button. Tips are quiet (`HintRow`, no fill); a filled `InlineBanner` is reserved for things that need attention.
6. **Lead with what Keeproll can do.** The biggest number on any screen is the one the user can act on (“3.1 GB can be freed”, “1.3 GB · 4 groups”). Device totals are footnotes.
7. **Soft depth, one family.** Content lives on soft-shadowed `surface` cards over the warm canvas (`.card()`); nothing is drawn with a border in light mode. There is one brand gradient (teal → deep teal) for the Home hero and the brand tile, and one tile gradient per category colour for icons. Shadows are one step (`Elevation.card`) except for the floating selection bar and the hero. Dark mode separates surfaces by value and a hairline instead of shadow.
8. **Three-stage entry.** Onboarding (illustrated, three pages) → Home (device storage, one primary action, a glance at what was found) → Results (the full dashboard). Home is calm and always the same shape; Results is where the numbers and the "select recommended" shortcut live.
2. **Show, then ask.** Always show the actual photo, video or contact before asking the user to decide. Numbers (GB) support the decision; they never replace seeing the items.
3. **One obvious next step.** Each screen has one primary action. The selection bar is the thread that leads every screen to Review.
4. **Honest numbers.** Say “up to” when a number is uncertain (iCloud assets). Explain Recently Deleted. Never promise to clear caches or junk.
5. **Thumb-first.** Primary actions sit in the bottom third of the screen. Grids support drag-to-select.

## 2. Brand

- **Name:** Keeproll. **Tagline:** “Keep what matters.”
- **Logo concept:** a rounded-square app icon in the Keeproll Teal gradient. Inside, three stacked rounded rectangles (photos) sit slightly offset; the top one is lifted and tilted as if being picked out of the stack, with a small white check in its corner. Flat, and no text. Build it in SF Symbols style (a 2 pt-equivalent stroke) so it matches the in-app iconography.
- **Must not resemble** Cleanup's icon, colours or illustrations.
- The icon needs a 1024×1024 master plus light, dark and tinted variants (the iOS 18+ icon appearances).

## 3. Colour tokens

Defined as asset-catalog colour sets (`Assets.xcassets/Colors/`) with Any and Dark appearances, exposed as `Color.keeproll.<token>` (the type is `KeeprollColor`). Contrast ratios below were checked against the matching background.

### 3.1 Neutrals

| Token | Light | Dark | Use |
|---|---|---|---|
| `canvas` | `#F6F5F1` (warm paper) | `#0E1113` | App background |
| `surface` | `#FFFFFF` | `#171B1E` | Cards, list rows |
| `surfaceRaised` | `#FFFFFF` | `#1F2427` | Sheets, selection bar |
| `hairline` | `#E4E2DC` | `#2A3035` | 1 pt separators and card borders |
| `inkPrimary` | `#13181B` | `#F2F4F5` | Titles, body |
| `inkSecondary` | `#5B6770` | `#9AA6AE` | Captions, metadata (≥ 4.5:1 on canvas and surface) |
| `inkTertiary` | `#8A949B` | `#6B767D` | Placeholders and disabled text only (not for essential info) |

### 3.2 Brand & semantic

| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#0B7A6F` (Keeproll Teal, 5.2:1 on white) | `#3CC7B5` (9.1:1 on canvas) | Primary buttons, selection, links, Best badge |
| `accentDeep` | `#075A52` | `#126E64` | Far end of the hero gradient; text on the Home status pill |
| `onAccent` | `#FFFFFF` | `#0E1113` | Text and icons on an accent fill |
| `accentSoft` | `#E3F2EF` | `#123430` | Selected-cell tint, chips, banners |
| `destructive` | `#C93A3A` (5.1:1 with white text) | `#FF6B6B` | **Only** the final Delete button and error text |
| `onDestructive` | `#FFFFFF` | `#0E1113` | |
| `warning` | `#B7740A` | `#F2B84B` | Limited-access banner icon, iCloud-only note |
| `success` | `#2E8A57` | `#5CD08F` | Summary screen check, “Done” states |

### 3.3 Category colours (storage bar, card icons, review section headers)

| Token | Light | Dark | Category |
|---|---|---|---|
| `catSimilar` | `#5B6CF0` | `#8A96FF` | Similar photos |
| `catScreenshots` | `#D9891E` | `#F2B24B` | Screenshots |
| `catVideos` | `#D0507A` | `#F17FA3` | Large videos |
| `catContacts` | `#2F93C8` | `#6CC3EE` | Duplicate contacts |
| `catOther` | `#B8C0C6` | `#4A545B` | Used by other apps and the system |
| `catFree` | `#E6E9EB` | `#23292D` | Free space |

Category colours only ever appear on icons, bar segments and small dots, always next to a text label, never as a text colour on their own.

## 4. Typography

The system font (SF Pro) through **Dynamic Type text styles only**. Large numbers use the rounded design with monospaced digits, so byte counts don't jitter while they animate.

| Token (`Font.keeproll.*`) | Definition | Use |
|---|---|---|
| `heroNumber` | `.system(.largeTitle, design: .rounded).weight(.bold)` + `.monospacedDigit()` | Dashboard freeable amount, category-screen totals, Review total, Summary bytes freed |
| `title` | `.title2.weight(.semibold)` | Section titles (“Ready to clean”, “More tools”) |
| `display` | `.system(.title2, design: .rounded).weight(.bold)` + `.monospacedDigit()` | Card numbers and the ring's free %: the hero's voice at a smaller size |
| `headline` | `.headline` | Card titles, group headers |
| `body` | `.body` | Explanations, contact rows |
| `metric` | `.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit()` | “1.4 GB” on cards and bars |
| `caption` | `.footnote` | Dates, durations, match reasons |
| `badge` | `.caption2.weight(.bold)` | Best badge, cloud badge |

Rules: never use fixed point sizes; truncate middle for file names and never for numbers; at accessibility sizes (AX1+), stacks switch from horizontal to vertical (`ViewThatFits` or `dynamicTypeSize.isAccessibilitySize`).

## 5. Spacing, radii, elevation

- **Spacing (`Spacing.*`, 4 pt grid):** `xxs 4 · xs 8 · s 12 · m 16 · l 20 · xl 24 · xxl 32 · xxxl 40`. Screen horizontal margin is `m` (16). Gap between cards is `s` (12).
- **Radii (`Radius.*`):** `thumb 8 · control 12 · card 16 · sheet 24`; buttons use `Capsule()`. Always `.continuous` corners.
- **Grid:** photo grids are 3 columns (4 when `horizontalSizeClass == .regular`; 2 at AX sizes), with a 2 pt gutter and square cells.
- **Elevation (`Elevation.*`):** two steps. `card` = `black 7 %, radius 16, y 6` on every `.card()` in light mode (dark mode swaps it for a hairline). `floating` = `black 14 %, radius 24, y 8` on the SelectionBar; the Home hero uses `accentDeep 35 %` at the same radius. `CategoryTile` and `ToolCard` tiles carry a coloured shadow at 28 % of their own colour. No other shadows.
- **Gradients (`KeeprollGradient.*`):** `hero` (accent → accentDeep, top-leading to bottom-trailing) for the Home hero and the brand tile; `tile(color)` (color → color 72 %) for category tiles. Nothing else is gradient-filled.
- **Cards (`.card(radius:padding:)`):** `surface` fill, `Radius.card` (16) by default, `Radius.sheet` (24) for hero-sized cards, continuous corners, the `card` shadow. Groups, rows, summaries and dashboard entries all use it, so a screen has exactly one card style.

## 6. Iconography

SF Symbols only, `.hierarchical` rendering, tinted with the category colour.

| Concept | Symbol |
|---|---|
| Similar photos | `square.on.square` |
| Screenshots | `camera.viewfinder` |
| Large videos | `video` |
| Duplicate contacts | `person.2` |
| Review | `checklist` |
| Delete | `trash` |
| Keep / selected | `checkmark.circle.fill` |
| Not selected | `circle` |
| Best | `star.fill` |
| iCloud-only | `icloud` |
| Locked (denied) | `lock` |
| Limited access | `photo.badge.exclamationmark` |
| Merge | `arrow.triangle.merge` |
| Backup | `externaldrive.badge.checkmark` |

## 7. Motion & haptics

| Token (`Motion.*`) | Value | Use |
|---|---|---|
| `standard` | `.spring(response: 0.35, dampingFraction: 0.85)` | Selection, card expand, bar appear |
| `gentle` | `.spring(response: 0.6, dampingFraction: 0.9)` | Storage ring fill, progress |
| `countUp` | `.easeOut(duration: 1.2)` + `.contentTransition(.numericText())` | Summary bytes, dashboard totals |

- The **storage ring** and **storage bar** fill on first appearance; Home and Results sections rise in with a 70 ms stagger (`Rise`). Onboarding heroes animate their parts in once. The **selection check** uses `.symbolEffect(.bounce)`. The **selection bar** slides up from the bottom (`.move(edge: .bottom).combined(with: .opacity)`).
- **Swipe mode (B1):** the card rotates up to ±12° with the drag. Keep shows a teal tint, Delete a neutral grey tint (not red; nothing is deleted until Review).
- **Reduce Motion:** replace springs and rotation with `.opacity` crossfades, and skip count-ups (show the final value).
- **Haptics:** `.sensoryFeedback(.selection, trigger:)` on toggle; `.impact(weight: .light)` when drag-select crosses a cell; `.success` when cleaning completes; `.warning` on a partial failure.

## 8. Components (`Keeproll/Core/DesignSystem/Components/`)

Each component has a `#Preview` showing all of its states, in light and dark.

| Component | Purpose | States / API |
|---|---|---|
| `StorageRing` | Home hero graphic, drawn on the hero gradient: translucent white track (free), solid white arc (used), glowing category arcs at the start, free bytes in the centre (free % at AX sizes), and a thin outer arc for scan progress. | `snapshot`, `segments`, `scanProgress`, `size` |
| `StorageBar` | Results summary graphic: a 6 pt capsule of the device's storage with the same segment logic as the ring. | `snapshot`, `segments` |
| `StatTile` | Home metric card: tinted symbol circle, caption label, `metric` value ("Freed so far", "Last scan") | `symbol`, `tint`, `label`, `value` |
| `CategoryTile` | The category's symbol on its gradient tile, any size. The one visual identity of a category (Home checks, Results cards, Review headers, Summary rows, onboarding). | `category`, `side` |
| `CategoryCard` (chats, expired) | Same card; `catChats` and `catExpired` tiles; values are bytes | as above |
| `CategoryCard` | Results entry per category: tile top-left, state badge top-right (lock / check / spinner / chevron), then title, `display` number and caption. Two per row, one per row at AX sizes. | `.scanning(progress)`, `.ready(bytes, count)`, `.empty`, `.locked`; `refreshing` |
| `ToolCard` | Full-width card for Swipe and Vault: gradient tile, title, two-line subtitle, chevron | `symbol`, `tint`, `title`, `subtitle` |
| `SectionHeader` | `title` text between groups, optional trailing view | `Text`, `trailing` |
| `SettingsView` rows | `permissionRow` (tile, name, status line, Allow/Change), `actionRow` (tinted symbol, title, subtitle, chevron), `infoRow` (label · value) inside `.card()` sections | see Settings blueprint |
| `OnboardingHero.Welcome / Access` (+ `Photos`, `Contacts` kept for reuse) | Illustrated onboarding heroes built from the design system's own tiles, mark and badges: satellites popping around the brand tile; the three permission tiles with a shield. Animated with `Motion.standard`, static under Reduce Motion. | — |
| `AccessSetupPage` | Onboarding page 2: permission rows with per-row Allow, “Allow all” sequencing the system prompts, “Start using Keeproll” once all are decided | `scanStore`, `onFinish` |
| `KeeprollMark` / `KeeprollMarkTile` | Brand mark (three stacked cards, top one lifted with a check) and the mark on its gradient tile with a soft glow. Home brand row, onboarding, Swipe “All sorted”. | `size`, `ink`, `check` |
| `SelectableThumbnail` | A grid cell | `asset`, `isSelected`, `isBest`, `isCloudOnly`, size overlay; 44 pt minimum hit area for the check control |
| `BestBadge` / `CloudBadge` | “Best” pill on a thumbnail; iCloud-only marker | teal fill, `star.fill` + text |
| `GroupHeader` | Similar-group header | date · count · freeable bytes · “Select all but best” button |
| `VideoRow` | A large-videos list row as a `.card()`; a 2 pt accent ring while selected | thumb (16:9), duration overlay, date, size, selection, optional “Save ~X” compress pill |
| `ContactGroupCard` | A duplicate-contact group as a `.card()`; accent ring while a merge is queued | match-reason chips, contact rows (primary radio + “Keep”, per-row delete), merged preview, “Merge into one” ↔ “Merge queued” |
| `ContactAvatar` | Initials circle for contacts | `size`, photo indicator dot |
| `SelectionBar` | Floating bottom bar | “N items · X GB” + “Review” button; hidden when the cart is empty. Text and button stack, with a full-width button, at AX sizes. `Elevation.floating` shadow |
| `PrimaryButton` | Capsule, accent fill, full width | `.normal`, `.loading`, `.disabled`; `role: .destructive` switches to the destructive colour (Review only) |
| `SecondaryButton` | Capsule, `accentSoft` fill, accent text | |
| `FilterChips` | Segmented chips (video size, screenshot age) | selected state uses `accent` fill |
| `PermissionPrimer` | Full-screen explainer before the system prompt | `hero: .brandMark | .symbol(name) | .custom(view)`, rounded display title, reasons in a `.card()`, Allow and Not now buttons; the onboarding container adds page dots |
| `InlineBanner` | Things that need attention: limited access, library changed, Recently Deleted, backups | `.info`, `.warning`; optional action. Not for tips (use `HintRow`) |
| `EmptyState` | Nothing found / all clean | accent symbol in an 80 pt `accentSoft` circle, title, message, optional action |
| `ScanProgressView` | Linear progress + “1,204 of 9,860 photos” | determinate or indeterminate |

## 9. Screen blueprints

**Home (v4, the entry screen).** System bar hidden. Brand row (`KeeprollMarkTile` 40 pt, “Keeproll” rounded title, “Keep what matters” caption, circular Rescan and Settings buttons) → the hero: a `Radius.sheet` card on `KeeprollGradient.hero` with a corner light, the `StorageRing`, and a white status pill (“Up to 213 MB can be freed” / “Checking photos · 42 %” / “Photo access needed” / “All tidy”) → one `PrimaryButton` (“Scan my iPhone” before the first scan, “See what to clean” after) → any attention banner → two `StatTile`s (“Freed so far”, “Last scan”) → “What Keeproll checks” with an “All results” link: **one card, one row per category** (36 pt `CategoryTile`, full title, one-line description or “Needs access · tap to allow”, last-known value, chevron). A list, not a tile grid, so it reads correctly wherever the fold falls. Pull to refresh. At AX sizes the ring shows the free %, the pill becomes a rounded rectangle and the tagline hides.

**Results (v4, the dashboard).** Inline title “Results”, Rescan in the bar. A `Radius.sheet` summary card: “UP TO / 213 MB / can be freed · 35 GB free of 494 GB”, the `StorageBar`, and the one-tap **Select recommended · 2.8 MB** `SecondaryButton` (toggles to “Clear recommended”; recommended = non-best similar shots + blurry photos; nothing is pre-selected, D9) with a `HintRow` saying nothing is removed until Review. Then three titled sections: “Photos & videos” (`CategoryCard` grid), “Contacts & calendar” (`CategoryCard` grid), “Tools” (`ToolCard`s for Swipe and Vault), then the DEBUG calibrate link. The SelectionBar is pinned to the bottom. Reached from Home; `finishCleanup()` lands here.

**Category screens (Similar / Screenshots / Blurry / Videos / Contacts / Calendar / Vault).** Inline nav title, with Select all / Smart select / Merge all on the right. Then `CategoryHeader` (total, caption, selected chip, one `HintRow`), a filter row where one exists, and the grid or list. Similar groups, video rows, contact groups and calendar sections are `.card()`s; photo grids sit directly on the canvas. The SelectionBar is pinned. When nothing is found: an `EmptyState`.

**Similar Photos.** A vertical list of groups. Each group has a GroupHeader and a horizontal row (or wrapping grid) of SelectableThumbnails, with Best first. **Smart select** sits at the top right. Tapping a thumbnail opens the Compare view: a full-screen pager with Best and size, a Keep/Select toggle at the bottom, and “Make best” in the toolbar.

**Swipe to sort (B1).** Progress row (kept · n of N · to remove) + bar, a 3:4 card stack (next card peeks beneath), KEEP/REMOVE stamps that fade in with the drag, round Remove/Keep buttons, Undo in the toolbar. The global selection bar is hidden here and on Compare.

**Contacts.** A list of ContactGroupCards. Each card lists its contacts (name, phones and emails in `caption`), a match-reason chip, a “Merged result” preview row, and **Merge** / **Delete selected** actions that add to the cart.

**Review.** Title “Review”. The total in a `Radius.sheet` card (“You'll free up to / 110 MB / 2 items…”), then sections by category, each headed by a 26 pt `CategoryTile` and the title: compact media grids (tap to remove an item) and contact / event rows in a `.card()`.

**Summary.** A success check with three expanding rings, then “3.1 GB cleaned up” (count-up), per-category rows with 32 pt `CategoryTile`s in a `.card()`, the Recently Deleted banner with an **Open Photos** button, backup share (if any), and a **Done** button.

**Calendar.** Duplicate groups show the kept copy first (green check, “Keep” pill, calendar name), then the extra copies with selection circles. Old events are grouped by year in disclosure cards with a “Select year” shortcut.

**Saved from Chats.** `CategoryHeader` (total, "N look like WhatsApp · N look like Telegram", selected chip, a hint explaining the camera-metadata idea), then up to three tiers, **Very likely / Likely / Possible**, each a titled `SelectableMediaGrid` with a one-line note on what the tier means. Toolbar: **Select very likely** (only that tier, D9). Tiles use `catChats` (coral).

**Expired Screenshots.** `CategoryHeader` (total, "N screenshots past their date", a hint that text is read on-device and never stored), then a `.card()` per kind (One-time codes, Boarding passes, Tickets, Deliveries, Coupons, Reservations, Parking) with rows: 56 × 72 thumbnail, a plain sentence ("Flight was on 12 Mar"), size and "% sure", selection check. Toolbar: Select all. Tiles use `catExpired` (ochre).

**Settings.** Reached from the gear on Home; inline title. Three `.card()` sections: **Access** (Photos, Contacts, Calendar rows with a status line in `success`/`warning`/`inkSecondary` and an Allow / Change action: first request through the system prompt, later ones open iOS Settings), a `HintRow` restating the privacy promise, **Data on this iPhone** (Clear scan cache with a confirmation, Reset freed total with a destructive confirmation, Show the welcome again), and **About** (version, purpose, privacy paragraph). No toggles: there is nothing to sync, no account, no analytics.

**Onboarding.** Two screens. **Welcome** (`OnboardingHero.Welcome`: brand tile with category tiles popping in): title “Keep what matters”, three reasons in a card that describe the loop (Scan · Review · Private), button “Okay, let’s go”. **Set up access** (`AccessSetupPage`, `OnboardingHero.Access`: Photos, Contacts and Calendar tiles with a shield): a card with one row per permission (tile, name, one-line reason, then an **Allow** pill → spinner → green check, or “Settings” if it was denied), a primary **Allow all** that walks through the three system prompts in order (Photos first), and “Not now”. Once every prompt has been answered the primary button becomes **Start using Keeproll**. Nothing here blocks entry; anything skipped can be allowed later from Settings or from the category itself.

## 10. Voice & copy

- Plain, warm, specific. Use the second person. No exclamation marks except on the empty state and success.
- Always name the consequence: “Delete 42 items · 3.1 GB”, never just “Clean”.
- Use: *“Keep what matters.”* · *“These look alike. We picked the sharpest one.”* · *“Nothing leaves your iPhone.”* · *“Deleted photos stay in Recently Deleted for 30 days.”*
- Never use: “junk”, “boost”, “virus”, “speed up your phone”, “clear cache”, or anything that promises what iOS doesn't allow.
- Byte formatting: `ByteCountFormatter` with `.file` count style, e.g. “1.4 GB”. Counts: “1 photo / 12 photos” via string-catalog plural variants.

## 11. Accessibility checklist (every screen)

- [ ] Works at AX5 (no clipped numbers; grids reflow)
- [ ] VoiceOver: thumbnails read “Photo, 3 March 2024, 4.2 MB, selected, best in group”; the check control is not a separate element (use `.accessibilityAddTraits(.isSelected)` on the cell)
- [ ] Custom actions on cells: “Select”, “Make best”, “Preview”
- [ ] Every interactive element has a hit area of at least 44×44 pt
- [ ] Selection shown by icon and fill, not colour alone
- [ ] Reduce Motion and Reduce Transparency respected
- [ ] Contrast ≥ 4.5:1 for text and ≥ 3:1 for icons/graphics
