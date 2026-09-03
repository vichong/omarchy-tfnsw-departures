# Handoff: Transport NSW departures — popup row redesign (variant 2a)

## Overview
Redesign of the Omarchy bar-widget plugin `omarchy-tfnsw-departures` (Quickshell/QML, Tokyo Night). Two screens plus one row variant:

- **1a Popup panel** (460 px, anchored under the bar icon) — hero, leave window, alerts line, departure rows, one row expanded.
- **1b Settings overlay** (600 px centred dialog).
- **2a Journey-chain row** — the chosen replacement for the departure row: line 1 = pictogram · line badge · destination · headsign · pills; line 2 = walk › badge(s) › walk chain with arrival + platform. Expanded state shown on the M1 row.
- **1c Variants sheet** — countdown block states and leave-window fill.

Implement **1a with 2a's rows** (2a supersedes the caption-style rows of 1a) and **1b**.

## About the design files
`TfNSW Departures Mockups.dc.html` is an HTML design reference (opens in a browser; needs `support.js` beside it). It is not code to ship. Recreate it in the plugin's QML using its existing Quickshell components, theme bindings and layout patterns. All styling is inline on each element, so exact values can be read straight from the file — search for the ids `1a`, `1b`, `2a`, `1c`.

## Fidelity
**High-fidelity.** Colours, type sizes, spacing, radii and copy are final. Match pixel-for-pixel at 1x.

## Design priorities (rank; higher wins)
1. Glance: the answer (leave in N min / now / missed) reads in < 1 s. One primary number per row, one urgency cue per screen (the leave window).
2. Transport for NSW visual language: line colours, rounded-square badges, indicator-board words (DEPARTS, PLATFORM), mode pictograms.
3. Omarchy fit: Tokyo Night tokens, JetBrains Mono everywhere, flat controls, no gradients, no colour in the bar itself. **No theme setting** — follow the system theme.

Hard rules: **no red as an urgency cue** (NOW block stays in the line colour; only the `cancelled` pill uses `#f7768e`). Text on a line colour is white or `#16161e` by contrast (see table). Never use a line colour for small text on the dark background. Placeholders never look like values (italic, `#3d4468`).

## Design tokens
Colours
- panel bg `#1a1b26`; input bg `#16161e`; fg `#c0caf5`; fg-2 `#a9b1d6`; muted `#565f89`; placeholder `#3d4468`; accent `#7aa2f7`
- border strong `rgba(192,202,245,.4)` (panel edge); border `rgba(192,202,245,.18)`; divider `rgba(192,202,245,.12)`; hairline `rgba(192,202,245,.1)`
- ok/realtime `#9ece6a`; warn/alerts + medium crowding `#e0af68`; urgent (cancelled pill only) `#f7768e`
- row highlight (expanded) `rgba(122,162,247,.05)`; alerts band `rgba(224,175,104,.05)`; board bg `rgba(0,0,0,.28)`

Line colours → text colour on badge/block
- T1 `#F99D1C` → `#16161e` · T2 `#0098CD` → `#16161e` · T3 `#F37021` → `#16161e` · T4 `#005AA3` → white · T8 `#00954C` → white · T9 `#D11F2F` → white
- M1 `#168388` → white · L1 `#BE1622` → white · L2 `#DD1E25` → white · L3 `#781140` → white
- Bus `#00B5EF` → `#16161e` · Ferry `#5AB031` → `#16161e`

Type (JetBrains Mono)
- place name 16/600 · leave label 15/700 · countdown number 20/700 · destination 13/700 · headsign 11/400 muted · clock 13/600 (AM/PM 10 muted) · caption/chain 10/400 muted · pill 9/500 · board words 8/500, letter-spacing .14–.16em, uppercase, muted · settings labels 9/400 muted · settings section caps 9/500 .18em

Radii: panel 8 · countdown block / cards 6 · badge / buttons / inputs 4 · pill 3.

## Screen 1a — popup panel (460 px)
Border 1 px strong, radius 8, bg panel.

Hero (padding 14 14 12; gap 11; align top)
- TransportMark 28×36 slot (see Assets) · title "Home" 16/600 · under it the place selector: bordered 1 px border colour, radius 4, padding 4 8, bg `rgba(192,202,245,.04)`, content "Sydenham → Wynyard" 11px fg-2 with muted arrow and a 9×6 chevron. Opens a dropdown of places (replaces the old chip row).
- Right: refresh and settings icon buttons 24×24, radius 4, 1 px border, 13 px glyph fg-2.

Leave window (padding 0 14 13; gap 9)
- Walking pictogram 15×20 fg · label "Leave in N min" / "Leave now" 15/700 fg (**never** "Leave in now"; label is fg colour at every state) · sub-line "6 min walk · T4 to Bondi Junction" 10 muted.
- Track: 3 px, radius 2, bg `rgba(192,202,245,.12)`; fill in the **next service's line colour**, width = (10 − minutesLeft)/10, always the line colour. No caption on the right.

Alerts line: padding 9 14, top+bottom divider, bg alerts band; 6 px warn dot; "2 alerts" 11/500 warn; chevron warn on the right. Expands to list alerts.

Departure rows — use **2a** layout (below). Rows separated by dividers. Greyed rows (missed, dominated, cancelled) render at `opacity:.44` with the countdown block outlined instead of filled (1 px `rgba(192,202,245,.3)`, transparent) and the line badge at 35 % alpha of its colour with fg text. Dominated = a later departure arrives earlier (TripView behaviour); its caption says "later arrival".

Footer: padding 8 14, top divider, bg `rgba(192,202,245,.03)`; left "updated 12s ago · realtime", right "Thu 3 Sep · 8:29 AM", 9 muted.

## Row layout 2a (collapsed)
Row: flex, gap 9, padding 10 12, align top.
1. **Countdown block** 52×46, radius 6, padding 0 5, bg line colour. Number 20/700 + "min" 9/500 baseline-aligned (gap 3), "LEAVE" 8/500 .16em at 85 % below (margin-top 3). States: N min · **NOW** (16/700 text "NOW", still line colour) · **MISSED** ("—" 13/600 + "MISSED", outlined, opacity .5) · **CANC** (struck-through minutes in fg, "CANC" 8/500 urgent, outlined, opacity .5).
2. Text column (flex 1, gap 6, padding-top 2):
   - Line 1 (flex, gap 6, align centre): mode pictogram 20×20 muted stroke (train / metro-in-tunnel / bus / ferry) · line badge (min-width 24, height 19, padding 0 4, radius 4, 11/700) · destination 13/700 fg, no shrink · headsign 11 muted, shrink + ellipsis, min-width 70 (0 on rows with many pills) · pills · crowding glyphs · expand chevron (margin-left auto, accent) on the expanded row.
   - Pills: padding 2 5, radius 3, 9/500, 1 px border. `RT` ok colour on `rgba(158,206,106,.12)`; `1 change` fg-2 on `rgba(192,202,245,.08)` (no pill for direct); `cancelled` urgent on `rgba(247,118,142,.12)`. Scheduled (non-realtime) = simply no RT pill.
   - Crowding (bus/metro only, optional): three 7×11 person glyphs, filled count = level; low = ok colour, medium/high = warn; unfilled `rgba(192,202,245,.22)`.
   - Line 2 **chain** (flex, gap 6): walk glyph 9×12 + minutes (10/500 fg-2) › badge (17 px tall, 9/700) › [walk glyph + change minutes, muted] › badge … › walk glyph + minutes; separators "›" 10 muted; then a muted caption "· → 9:13 AM · Platform 1" that **shrinks/ellipsizes** (arrival first so truncation eats the platform).
3. **Departs column** width 60, right-aligned, padding-top 3: "DEPARTS" 8/500 .14em muted; clock 13/600 fg with " AM" 10 muted, nowrap. Struck-through and muted on cancelled rows; muted on greyed rows.

Six rows + one expanded row must fit ≈ 900 px.

## Row 2a expanded (indicator board)
Row gets bg row-highlight and chevron rotated up. Beneath it a board: margin 0 12 12 73 (indented under the text column), 1 px hairline border, radius 6, bg board. Rows top-to-bottom, mirroring the chain:
- walk row: walk glyph 10×13 muted, "walk 6 min", right "leave 8:36 AM" — 10 muted, padding 7 11
- leg: badge 19 px · headsign 11/600 fg + departure "8:42 AM" 10 muted · stop list 10 muted line-height 1.5 · right: label-over-value "PLATFORM" / "1" (8/500 caps muted over 12/600 fg); padding 10 11 9
- change row: 5 px hollow circle, "change · 7 min at Central", right "8:51 → 8:58 AM"; hairline top+bottom
- second leg (T4 · Bondi Junction · Platform 18)
- walk row: "walk 4 min", right "arrive 9:13 AM"

## Screen 1b — settings (600 px)
Header: padding 15 18, bottom divider; TransportMark 28×36; "Transport NSW settings" 14/600; close 24×24 button.
Body padding 16 18 18, column gap 14:
- **CONNECTION** (section caps): card 1 px border radius 6 bg `rgba(192,202,245,.03)`, padding 11 12; **connected state collapses to one line**: 6 px ok dot · "Connected · key in keyring" (dot-part muted) · "Remove" button (5 9, 10/500 fg-2, 1 px border). Disconnected state: API-key input + Connect button (not mocked).
- **PLACES** + "Add place" button. List in one bordered card; each place row padding 11 12: name 12/600 + summary 10 muted ("Sydenham → Wynyard · 6 min walk · T4, T8"; empty filters read "All services") + chevron. Selected place highlighted `rgba(122,162,247,.07)` with inline editor below (bg `.04`, padding 4 12 14, gap 11):
  - Name | Walk minutes (112 px stepper "6  − +")
  - Leaving from | Going to (optional) — station inputs 30 px tall, 1 px border `.2`, radius 4, bg input, 11 fg
  - Wi-Fi SSID input (placeholder italic `#3d4468` "e.g. home-5g — optional") + "Use current" button
  - **Filter services** disclosure (1 px hairline card): header 9 10 with chevron, title 10/500 fg-2, summary right "2 lines · all modes" muted. Body: Lines (badge chips with ×, placeholder "add a line…") | Destination contains (empty reads **"All"** as placeholder style); Modes segmented chips: All (selected: accent border, `rgba(122,162,247,.14)` bg, fg) · Train · Metro · Light rail · Bus · Ferry (unselected: border .16, muted).
  - Footer row: "Delete place" 10 urgent text-left; right "Cancel" (bordered) + "Save place" (accent bg, `#16161e` text, 10/600). Buttons nowrap.
- **Demo mode** card: title 11/500, description 10 muted ("A live-looking Sydenham board, no keyring or network calls."), toggle 34×18 radius 9, knob 12 muted (on: accent track, fg knob).
- Footer caption row directly under Demo mode: left "Transport NSW for Omarchy v0.5.2" 9 muted; right link "github.com/vichong/omarchy-tfnsw-departures" 9 muted, underline on hover. **No theme setting, no "Quickshell · Tokyo Night" text.**

## Interactions & state
- Place selector: dropdown of configured places; selection re-queries. Auto-select by Wi-Fi SSID when set.
- Leave window: derived from the first non-greyed row; `minutesLeft = departure − now − walkMinutes`; label "Leave in N min" for N ≥ 1, "Leave now" for N ≤ 0 until departure, then row becomes MISSED. Track fill = clamp((10 − N)/10).
- Rows: tap toggles expanded (one at a time). Dominated/missed/cancelled rows are kept in place, greyed.
- Refresh: manual + polling; footer shows age.
- Settings: connection card collapsed when a key is in the keyring; place editor inline; filter disclosure collapsed by default; empty filters show "All".
- Data: TfNSW Trip Planner API departures + trip (for destination journeys); realtime flag → RT pill; occupancy → crowding glyphs where provided.

## Assets
- **TransportMark**: the Transport for NSW swoosh (orange body, blue arc, green leg, blue dot) is a trademark and is NOT included — the mock shows a labelled 28×36 placeholder. Use the official asset from the repo/brand kit in that slot.
- Mode pictograms, walking figure, crowding persons, chevrons: simple stroked SVGs in the mock (viewBox 14 or 15×20); copy paths from the HTML or use the equivalent TfNSW pictograms.

## Files
- `TfNSW Departures Mockups.dc.html` — the design (open in a browser; ids `1a`, `1b`, `1c`, `2a`, `2b`, `2c`; `2b`/`2c` are rejected alternatives).
- `support.js` — runtime needed to view the HTML; not part of the design.
