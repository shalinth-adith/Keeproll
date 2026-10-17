# Keeproll — App Store listing

Everything App Store Connect asks for, ready to paste. Character limits in brackets.

## Identity

| Field | Value |
|---|---|
| Name [30] | `Keeproll` |
| Subtitle [30] | `Photo & storage cleaner` (23) |
| Bundle ID | `me.adithyan.shalinth.Sift` (unchanged; invisible to users) |
| SKU | `keeproll-ios-1` |
| Primary category | Utilities |
| Secondary category | Photo & Video |
| Price | Free, no in-app purchases |
| Age rating | 4+ (no objectionable content; answer "No" to every question) |
| Copyright | `© 2026 Shalinth Adithyan` |

## Promotional text [170]

> Find similar photos, screenshots, large videos and duplicate contacts, then approve exactly what goes. Nothing leaves your iPhone. New: photos saved from chats, expired screenshots, Live Photos to stills.

(168 characters)

## Description [4000]

> Keeproll finds what's quietly filling your iPhone and lets you decide what goes. Nothing is deleted until you approve it on a Review screen, and nothing ever leaves your phone.
>
> **What it finds**
> • Similar photos and exact duplicates, with the sharpest shot marked Best
> • Screenshots, old and new
> • Blurry, out-of-focus photos
> • Large videos, with one-tap HEVC compression that keeps the date and place
> • Photos saved from chat apps like WhatsApp and Telegram, told apart from the ones you shot
> • Expired screenshots: one-time codes, boarding passes, tickets, deliveries and coupons that are past their date
> • Live Photos you can turn into stills to drop the motion clip
> • Duplicate contacts, merged without losing a number or an email
> • Old and duplicate calendar events
>
> **Safe by design**
> • Nothing is pre-selected. Every suggestion is one explicit tap.
> • Review shows every item before anything is removed; tap any to keep it.
> • Photos and videos go to Recently Deleted for 30 days, so you can change your mind.
> • Contacts and calendar changes are backed up to a file you can share before they happen.
> • Favourites are never suggested.
>
> **Private by design**
> • No account. No network access. No analytics.
> • Everything is analysed on your iPhone, including the on-device text reading for expired screenshots. Text is read once and never stored.
> • The private vault keeps photos behind Face ID or your passcode, on this phone only.
>
> **Fast**
> • Scans a 7,000-photo library in under a minute the first time, and in a couple of seconds after that.
> • Results appear while the scan is still running.
>
> **Honest**
> • Keeproll never claims to clear caches or "junk": iOS doesn't allow apps to do that, and we won't pretend otherwise.
> • Space in iCloud-only photos is labelled as iCloud space.
> • A storage forecast on Home tells you where your free space is heading, once it has three days of readings.
>
> Also: swipe to sort suggestions one by one, a Home Screen widget with your free space, dark mode, Dynamic Type and VoiceOver throughout.
>
> Keep what matters.

## Keywords [100]

> `storage,cleaner,duplicate,photos,similar,screenshot,video,compress,whatsapp,contacts,live photo,space`

(99 characters; don't repeat words from the name or subtitle)

## URLs

| Field | Value |
|---|---|
| Support URL | `https://shalinth-adith.github.io/Keeproll/support` |
| Privacy policy URL | `https://shalinth-adith.github.io/Keeproll/privacy` |
| Marketing URL (optional) | `https://github.com/shalinth-adith/Keeproll` |

Both pages live in `docs/site/` in the repo; turn on GitHub Pages (Settings → Pages → branch `main`, folder `/docs`) and they're served at the paths above.

## App Privacy (nutrition label)

- Does the app collect data? **No.** (Keeproll has no network access; the privacy manifest declares no collected data types and no tracking.)
- Tracking: **No.**

## Export compliance

`ITSAppUsesNonExemptEncryption` is already `false` in the Info.plist, so the question is answered automatically.

## App Review notes

> Keeproll is fully on-device: no login, no server. To test, grant Photos, Contacts and Calendar access on the "Set up access" page. The Review screen is the only place deletion happens, and iOS shows its own confirmation. Nothing is deleted without that confirmation. Contacts and calendar changes write a backup file first (shared from the Summary screen).

## Screenshots

`store/screenshots/6.9/` holds the 1320 × 2868 set for the 6.9-inch slot (also accepted for 6.5-inch). Order:

1. Home — "See what's filling your iPhone"
2. Results — "Every suggestion, one tap to select"
3. Similar photos — "The sharpest shot is kept for you"
4. Saved from chats — "Know what came from WhatsApp"
5. Expired screenshots — "Codes and passes past their date"
6. Review — "Nothing goes until you say so"
7. Live Photos — "Keep the still, drop the clip"
8. Onboarding — "Private. On your iPhone only."

Raw captures are in `store/screenshots/raw/`; regenerate the framed set with `swift scripts/make_store_screenshots.swift`.

## Version 1.0 "What's new"

> First release.
