# Keeproll — Design System

> Source of truth for how Keeproll looks, moves and speaks. Code lives in `Keeproll/Core/DesignSystem/`. **Never hard-code a colour, font, spacing or radius in a feature view.** Use a token. If the token you need doesn't exist, add it here first, then in code.
>
> **v3, minimalist (2026-09-25).** After the v2 audit the owner asked for a lighter, less clumpy app. v3 removes every card, border, gradient, glow and shadow from content screens; the dashboard is a plain list with one text headline and one 6 pt storage bar. The reasoning and evidence are in [DESIGN_AUDIT.md](DESIGN_AUDIT.md). Screenshots of the current build: `docs/design-screenshots/`.

---

## 1. Principles

1. **Calm, not alarming.** Many cleaner apps use scare tactics (“Your phone is full of junk!”, red warnings, fake virus scans). Keeproll is the opposite: a tidy desk, not an alarm. Red appears **only** on the final destructive button. Tips are quiet (`HintRow`, no fill); a filled `InlineBanner` is reserved for things that need attention.
6. **Lead with what Keeproll can do.** The biggest number on any screen is the one the user can act on (“3.1 GB can be freed”, “1.3 GB · 4 groups”). Device totals are footnotes.
7. **One surface, one accent, one graphic.** Content sits directly on the canvas, separated by hairlines. No cards, borders, gradients, glows or shadows. Teal appears only on the one primary action of a screen and on quiet hints. The dashboard has exactly one graphic, the storage bar. Status is said in words in secondary grey (“Allow access”, “None”), never in coloured bold text.
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
- **Elevation:** none. Content screens have no cards: sections are separated by a 1 pt `hairline` `Divider`, inset to the text edge under a row symbol (`RowDivider`). The only filled surfaces are the floating **SelectionBar** (`surfaceRaised` + hairline, no shadow), `InlineBanner` (`accentSoft`, attention only), the Swipe card (a photo, so it keeps a soft shadow) and system sheets. Symbols are drawn flat in their category colour; there are no icon tiles.

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

- The **storage bar** fills on first appearance. The **selection check** uses `.symbolEffect(.bounce)`. The **selection bar** slides up from the bottom (`.move(edge: .bottom).combined(with: .opacity)`).
- **Swipe mode (B1):** the card rotates up to ±12° with the drag. Keep shows a teal tint, Delete a neutral grey tint (not red; nothing is deleted until Review).
- **Reduce Motion:** replace springs and rotation with `.opacity` crossfades, and skip count-ups (show the final value).
- **Haptics:** `.sensoryFeedback(.selection, trigger:)` on toggle; `.impact(weight: .light)` when drag-select crosses a cell; `.success` when cleaning completes; `.warning` on a partial failure.

## 8. Components (`Keeproll/Core/DesignSystem/Components/`)

Each component has a `#Preview` showing all of its states, in light and dark.

| Component | Purpose | States / API |
|---|---|---|
| `StorageBar` | The dashboard's one graphic: a 6 pt capsule of the device's storage. Freeable categories are coloured segments at the start, the rest of the used space is `catOther`, free space is the `catFree` track. Fills on first appearance (`Motion.gentle`). | `snapshot`, `segments` |
| `ListRow` | The list row every dashboard entry uses: flat symbol (28 pt column), `body` title, optional trailing value in `metric` + `inkSecondary`, chevron in `inkTertiary`. 56 pt tall. `dimmed` turns everything `inkTertiary` for “nothing here” rows. Value drops under the title at AX sizes. | `symbol`, `tint`, `title`, `dimmed`, `action`, `value` |
| `CategoryRow` | `ListRow` for one cleanup category: value is the bytes or count, a spinner while scanning, “Allow access” when locked, “None” when empty (dimmed). | `.scanning(progress)`, `.ready(bytes, count)`, `.empty`, `.locked`; `refreshing` |
| `RowDivider` | Hairline between rows, inset past the symbol column | — |
| `SectionHeader` | `title` text between groups, optional trailing view | `Text`, `trailing` |
| `KeeprollMark` / `KeeprollMarkTile` | Brand mark (three stacked cards, top one lifted with a check) and the mark on its flat accent tile. Used in onboarding and the Swipe “All sorted” screen only. | `size`, `ink`, `check` |
| `CategoryHeader` | Top of every category screen: `heroNumber` + caption on the left, `SelectedChip` on the right (below the caption at AX sizes), optional scanning line, optional `HintRow` | `hero`, `caption`, `selectedCount`, `hint`, `scanning` |
| `SelectedChip` | “8 selected” accent capsule | `count` |
| `HintRow` | A quiet tip: accent symbol + `caption` in `inkSecondary`, no fill. Used for “drag sideways to select”, “tap to compare”, backup notes. | `systemImage`, `message` |
| `ToolRow` | Full-width row for tools that aren't scan categories (Swipe, Vault): tile, title, two-line subtitle, chevron | `symbol`, `tint`, `title`, `subtitle` |
| `SelectableThumbnail` | A grid cell | `asset`, `isSelected`, `isBest`, `isCloudOnly`, size overlay; 44 pt minimum hit area for the check control |
| `BestBadge` / `CloudBadge` | “Best” pill on a thumbnail; iCloud-only marker | teal fill, `star.fill` + text |
| `GroupHeader` | Similar-group header | date · count · freeable bytes · “Select all but best” button |
| `VideoRow` | A large-videos list row, flat with a hairline under it; `accentSoft` fill only while selected | thumb (16:9), duration overlay, date, size, selection, optional “Save ~X” compress pill |
| `ContactGroupCard` | A duplicate-contact group, a flat section ending in a hairline | match-reason chips, contact rows (primary radio + “Keep”, per-row delete), merged preview (deduped by digits/lowercase), “Merge into one” ↔ “Merge queued” |
| `ContactAvatar` | Initials circle for contacts | `size`, photo indicator dot |
| `SelectionBar` | Sticky bottom bar, the one accent-filled control on a screen | “N items · X GB” + “Review” button; hidden when the cart is empty. Text and button stack, with a full-width button, at AX sizes. No shadow |
| `PrimaryButton` | Capsule, accent fill, full width | `.normal`, `.loading`, `.disabled`; `role: .destructive` switches to the destructive colour (Review only) |
| `SecondaryButton` | Capsule, `accentSoft` fill, accent text | |
| `FilterChips` | Segmented chips (video size, screenshot age) | selected state uses `accent` fill |
| `PermissionPrimer` | Full-screen explainer before the system prompt | `hero: .brandMark | .symbol(name)`, rounded display title, reasons as a plain check list, Allow and Not now buttons; the onboarding container adds page dots |
| `InlineBanner` | Things that need attention: limited access, library changed, Recently Deleted, backups | `.info`, `.warning`; optional action. Not for tips (use `HintRow`) |
| `EmptyState` | Nothing found / all clean | plain `inkTertiary` symbol, title, message, optional action |
| `ScanProgressView` | Linear progress + “1,204 of 9,860 photos” | determinate or indeterminate |

## 9. Screen blueprints

**Dashboard (v3).** System large title “Keeproll”, Rescan as a bare symbol in the bar (plus pull-to-refresh). Then, on the canvas with no cards: the headline “213 MB **can be freed**” (`heroNumber` + `title`; “Photo access needed”, “Looking for things to clean…” or “Nothing to clean right now” as the other states) → one `caption` line “18 GB free of 494 GB · 440 KB freed so far · checking 42 %” → `StorageBar` → any attention banners → the category list (`CategoryRow`s between hairlines; categories with findings first, empty ones dimmed at the bottom) → a gap → the tools list (`ListRow`s “Swipe to sort”, “Private vault”) → the DEBUG calibrate link in `inkTertiary`. The SelectionBar is pinned to the bottom. All six categories and both tools fit on one 6.1″ screen.

**Category screens (Similar / Screenshots / Blurry / Videos / Contacts / Calendar / Vault).** Inline nav title, with Select all / Smart select / Merge all on the right. Then `CategoryHeader` (total, caption, selected chip, one `HintRow`), a filter row where one exists, and the grid or list. Groups and rows sit on the canvas and end in a hairline; nothing is boxed. The SelectionBar is pinned. When nothing is found: an `EmptyState`.

**Similar Photos.** A vertical list of groups. Each group has a GroupHeader and a horizontal row (or wrapping grid) of SelectableThumbnails, with Best first. **Smart select** sits at the top right. Tapping a thumbnail opens the Compare view: a full-screen pager with Best and size, a Keep/Select toggle at the bottom, and “Make best” in the toolbar.

**Swipe to sort (B1).** Progress row (kept · n of N · to remove) + bar, a 3:4 card stack (next card peeks beneath), KEEP/REMOVE stamps that fade in with the drag, round Remove/Keep buttons, Undo in the toolbar. The global selection bar is hidden here and on Compare.

**Contacts.** A list of ContactGroupCards. Each card lists its contacts (name, phones and emails in `caption`), a match-reason chip, a “Merged result” preview row, and **Merge** / **Delete selected** actions that add to the cart.

**Review.** Title “Review”. The total as plain text (“You'll free up to / 110 MB / 2 items…”), then sections by category, each headed by the category symbol in its colour and the title: compact media grids (tap to remove an item) and contact / event rows between hairlines. A total card reads “You'll free 3.1 GB”. The Recently Deleted and contact-backup InlineBanner sits above the only destructive PrimaryButton: “Delete 42 items”.

**Summary.** A single light-weight check symbol that scales in, then “3.1 GB cleaned up” (count-up), per-category rows (symbol, title, count) between hairlines, the Recently Deleted banner with an **Open Photos** button, backup share (if any), and a **Done** button.

**Calendar.** Duplicate groups show the kept copy first (green check, “Keep” pill, calendar name), then the extra copies with selection circles. Old events are grouped by year in disclosure cards with a “Select year” shortcut.

**Onboarding.** Three screens: Welcome (privacy promise) → Photos primer → Contacts primer (skippable).

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
