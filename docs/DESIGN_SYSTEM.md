# Sift — Design System

> Source of truth for how Sift looks, moves and speaks. Code lives in `Sift/Core/DesignSystem/`. **Never hard-code a colour, font, spacing or radius in a feature view.** Use a token. If the token you need doesn't exist, add it here first, then in code.

---

## 1. Principles

1. **Calm, not alarming.** Many cleaner apps use scare tactics (“Your phone is full of junk!”, red warnings, fake virus scans). Sift is the opposite: a tidy desk, not an alarm. Red appears **only** on the final destructive button.
2. **Show, then ask.** Always show the actual photo, video or contact before asking the user to decide. Numbers (GB) support the decision; they never replace seeing the items.
3. **One obvious next step.** Each screen has one primary action. The selection bar is the thread that leads every screen to Review.
4. **Honest numbers.** Say “up to” when a number is uncertain (iCloud assets). Explain Recently Deleted. Never promise to clear caches or junk.
5. **Thumb-first.** Primary actions sit in the bottom third of the screen. Grids support drag-to-select.

## 2. Brand

- **Name:** Sift. **Tagline:** “Keep what matters.”
- **Logo concept:** a rounded-square app icon in the Sift Teal gradient. Inside, three stacked rounded rectangles (photos) sit slightly offset; the top one is lifted and tilted as if being picked out of the stack, with a small white check in its corner. Flat, and no text. Build it in SF Symbols style (a 2 pt-equivalent stroke) so it matches the in-app iconography.
- **Must not resemble** Cleanup's icon, colours or illustrations.
- The icon needs a 1024×1024 master plus light, dark and tinted variants (the iOS 18+ icon appearances).

## 3. Colour tokens

Defined as asset-catalog colour sets (`Assets.xcassets/Colors/`) with Any and Dark appearances, exposed as `Color.sift.<token>` (the type is `SiftColor`). Contrast ratios below were checked against the matching background.

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
| `accent` | `#0B7A6F` (Sift Teal, 5.2:1 on white) | `#3CC7B5` (9.1:1 on canvas) | Primary buttons, selection, links, Best badge |
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

| Token (`Font.sift.*`) | Definition | Use |
|---|---|---|
| `heroNumber` | `.system(.largeTitle, design: .rounded).weight(.bold)` + `.monospacedDigit()`, scaled 1.4× via `@ScaledMetric` | Dashboard free-space number, Summary bytes freed |
| `title` | `.title2.weight(.semibold)` | Screen titles (in-content) |
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
- **Elevation:** flat by default. Cards get a 1 pt `hairline` border and no shadow. Only the **SelectionBar** and sheets get a shadow: `color: .black.opacity(0.12), radius: 16, y: 4` (none in dark mode, which uses `surfaceRaised` instead).

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

- The **storage ring** fills on first appearance. The **selection check** uses `.symbolEffect(.bounce)`. The **selection bar** slides up from the bottom (`.move(edge: .bottom).combined(with: .opacity)`).
- **Swipe mode (B1):** the card rotates up to ±12° with the drag. Keep shows a teal tint, Delete a neutral grey tint (not red; nothing is deleted until Review).
- **Reduce Motion:** replace springs and rotation with `.opacity` crossfades, and skip count-ups (show the final value).
- **Haptics:** `.sensoryFeedback(.selection, trigger:)` on toggle; `.impact(weight: .light)` when drag-select crosses a cell; `.success` when cleaning completes; `.warning` on a partial failure.

## 8. Components (`Sift/Core/DesignSystem/Components/`)

Each component has a `#Preview` showing all of its states, in light and dark.

| Component | Purpose | States / API |
|---|---|---|
| `StorageHero` | Dashboard hero card: ring (used vs free, category segments with glow) + “Up to X can be freed” pill + legend | `snapshot: StorageSnapshot?`, `segments: [StorageSegment]`; loading spinner |
| `SiftMark` / `SiftMarkTile` | Brand mark (three stacked cards, top one lifted with a check) and the mark on its gradient tile | `size`, `ink`, `check` |
| `CategoryCard` | A dashboard entry per category | `.scanning(progress)`, `.ready(bytes, count)`, `.empty`, `.locked(reason)`, `.limited` |
| `SelectableThumbnail` | A grid cell | `asset`, `isSelected`, `isBest`, `isCloudOnly`, size overlay; 44 pt minimum hit area for the check control |
| `BestBadge` | “Best” pill on a thumbnail | teal fill, `star.fill` + text |
| `GroupHeader` | Similar-group header | date · count · freeable bytes · “Select all but best” button |
| `VideoRow` | A large-videos list row | thumb (16:9), duration overlay, date, size, selection |
| `ContactGroupCard` | A duplicate-contact group | the contacts, match-reason chip, merged preview, primary picker |
| `SelectionBar` | Sticky bottom bar | “N items · X GB” + “Review” button; hidden when the cart is empty |
| `PrimaryButton` | Capsule, accent fill, full width | `.normal`, `.loading`, `.disabled`; `role: .destructive` switches to the destructive colour (Review only) |
| `SecondaryButton` | Capsule, `accentSoft` fill, accent text | |
| `FilterChips` | Segmented chips (video size, screenshot age) | selected state uses `accent` fill |
| `PermissionPrimer` | Full-screen explainer before the system prompt | `hero: .brandMark | .symbol(name)`, rounded display title, reasons in a surface card, Allow and Not now buttons; the onboarding container adds an accent glow and page dots |
| `InlineBanner` | Limited access, Recently Deleted notes | `.info`, `.warning`; optional action |
| `EmptyState` | Nothing found / all clean | illustration symbol, title, message, optional action |
| `ScanProgressView` | Linear progress + “1,204 of 9,860 photos” | determinate or indeterminate |

## 9. Screen blueprints

**Dashboard.** Nav title “Sift”. Below it, the StorageRing (hero) with the free-space `heroNumber`, then the legend, then a 2×2 grid of CategoryCards (a single column at AX sizes), then the lifetime “freed so far” line, and the SelectionBar pinned to the bottom. A limited-access banner goes above the cards when it applies.

**Category screens (Similar / Screenshots / Videos).** The header shows the total freeable space and a filter or smart-select control. The content is a grid or list. The SelectionBar is pinned. When nothing is found: an EmptyState that says “Nothing to clean here 🎉”.

**Similar Photos.** A vertical list of groups. Each group has a GroupHeader and a horizontal row (or wrapping grid) of SelectableThumbnails, with Best first. **Smart select** sits at the top right. Tapping a thumbnail opens the Compare view: a full-screen pager with Best and size, a Keep/Select toggle at the bottom, and “Make best” in the toolbar.

**Contacts.** A list of ContactGroupCards. Each card lists its contacts (name, phones and emails in `caption`), a match-reason chip, a “Merged result” preview row, and **Merge** / **Delete selected** actions that add to the cart.

**Review.** Title “Review”. Sections by category, with category-coloured headers: compact media grids (tap to remove an item) and contact action rows. A total card reads “You'll free 3.1 GB”. The Recently Deleted and contact-backup InlineBanner sits above the only destructive PrimaryButton: “Delete 42 items”.

**Summary.** A large success check, then “3.1 GB freed” (count-up), per-category counts, the Recently Deleted banner with an **Open Photos** button, contact backup share (if any), and a **Done** button.

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
