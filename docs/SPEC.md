# omarchy-tfnsw-departures — build spec (v0.1)

An Omarchy 4 (Quickshell) shell plugin: *when is my next train leaving?* Live
departures from Transport for NSW's Trip Planner API in the bar, so the user
can close the laptop and go and catch it.

Plugin id `io.github.vichong.tfnsw-departures`, IPC target `tfnsw`, MIT.

## Reference implementation to copy patterns from

`/home/vic/Projects/omarchy-gorelo` is a finished plugin by the same author on
the same shell. **Copy its structure and its hardening verbatim where the
problem is the same**; do not re-derive it:

| Gorelo file | Reuse as | Notes |
|---|---|---|
| `LiveBackend.qml` | `LiveBackend.qml` | One serialized curl worker: `--proto =https`, no `-L`, any 3xx rejected, `--max-filesize`, `-K -` config on stdin, generation-gated callbacks, deadline → SIGTERM → SIGKILL. Drop the upload machinery entirely. Auth header is `Authorization: apikey <key>` (not X-API-Key). Origin check against `Api.BASE_URL`. |
| `CredentialManager.qml` | `CredentialManager.qml` | Same serialized `secret-tool` adapter via `scripts/tfnsw-bounded`. Keyring attributes must be exactly `service tfnsw-departures account apikey` (a key is already stored under those attributes on this machine). No region dimension. |
| `Service.qml` | `Service.qml` | Config FileView + `mkdir -p`, credentials → connect → poll loop, backoff, reconnect timer, notifications via `omarchy-notification-send`, `statusLine()` for bug reports. |
| `Panel.qml` / `ListRow.qml` | `Panel.qml` / `DepartureRow.qml` | Bar `WidgetButton` + `KeyboardPanel` popup, `PanelHero`, cursor/keys via `PanelKeyCatcher`, IpcHandler owning the `tfnsw` target with `manageIpc: false`. |
| `Overlay.qml` | `Overlay.qml` | Full-screen `PanelWindow` overlay on `WlrLayer.Overlay`, settings tab layout, `controlHeight` trick, `FieldLabel/Caption/SectionTitle` components. |
| `DemoBackend.qml` | `DemoBackend.qml` + `Demo.js` | In-memory backend with the same method signatures as LiveBackend. |
| `GoreloIcon.qml` | `ModeBadge.qml` | Native vector mark; here a TfNSW mode roundel. |
| `manifest.json`, `README.md`, `.gitignore`, `tests/` | same | |

The shell's UI kit is at `/usr/share/omarchy/shell/Ui` (`Panel`, `WidgetButton`,
`KeyboardPanel`, `PanelKeyCatcher`, `PanelHero`, `PanelActionButton`,
`PanelSeparator`, `PanelSectionHeader`, `ButtonGroup`, `Button`, `TextField`,
`Toggle`, `Dropdown`, `SearchableDropdown`, `NumberField`, `MultiSelect`,
`CursorSurface`, `PanelToolTip`, `BorderSurface`) and `/usr/share/omarchy/shell/Commons`
(`Style`, `Color`, `Border`). Plugin docs: `/usr/share/omarchy/shell/README.md`
and `/usr/share/omarchy/shell/plugins/README.md`. The first-party weather widget
(`/usr/share/omarchy/shell/plugins/panels/weather`) shows a settings form and a
debounced search picker.

## Already written — do not change without a reason, keep tests green

`Api.js`, `Model.js`, `ConfigStore.js` and `tests/*.js` (`node tests/test_api.js`
etc.). Fixtures in `tests/fixtures/` are real API payloads. Read these first;
their exported functions are the contract for the QML layer:

- `Api.stopFinderPath(text)`, `Api.departuresPath(stopId, excludeModeIds, whenMs)`,
  `Api.tripPath(originStopIdOr{lat,lon}, destStopId, count, whenMs)`,
  `Api.connectionProbePath()`, `Api.parseResponse(status, body)` → `{ok, kind, error, data}`
  (`kind` ∈ credential | ratelimit | network | protocol | api),
  `Api.parseLocations(data)`, `Api.parseDepartures(data)`, `Api.parseJourneys(data)`,
  `Api.MODES` / `Api.modeById(id)` (`{id,label,letter,color}`), `Api.MAX_RESPONSE_BYTES`, `Api.BASE_URL`.
- `Model.boardFor(departures, place, nowMs)`, `Model.buildRows(board, place, nowMs)`,
  `Model.pillText/pillMode/urgency(board, place, nowMs)`, `Model.collectAlerts(board)`,
  `Model.notificationFor(board, place, nowMs, sentMap)`, `Model.projectJourney(journey, nowMs)`,
  `Model.placeForSsid(places, ssid)`, `Model.glyphFor(modeId)`, `Model.escapeMarkup`, `Model.notificationTag`.
- `ConfigStore.parse/merge/serialize`, `ConfigStore.KEYS`, `POLL_*`, `MAX_PLACES`, `newPlaceId(places)`.
  Config shape: `{ demoMode, places: [{id,name,stopId,stopName,lines[],destination,modes[],walkMinutes,ssid}], activePlaceId, autoPlace, pollSeconds, notify, colorful }`
  at `~/.config/omarchy/tfnsw-departures/config.json`.

## Behaviour

### Service (`Service.qml`, kind `service`)
- Phases: `idle | connecting | connected | error`. Connect = store/lookup key, then
  probe with `Api.connectionProbePath()`; a `credential` error means bad key.
- **Poll loop**: every `pollSeconds` (default 60; ×2 backoff on ratelimit/network,
  cap 10 min) fetch `departuresPath(activePlace.stopId, excludedModes, now)` where
  `excludedModes` = every mode id not in `place.modes` when `place.modes` is non-empty,
  else `[]`. Keep `departures` (parsed), rebuild `rows` ListModel + `alerts` +
  `pillText/pillMode/urgency` from `Model.*` with `nowMs = Date.now()`.
- **Clock tick**: a 15 s timer re-projects rows/pill from cached departures without
  a network call, so the countdown moves between polls. Poll faster (30 s) while
  the popup is open.
- **Places**: `activePlace` from config. `setActivePlace(id)` saves and re-polls.
  `autoPlace`: a 30 s `Process` runs `nmcli -t -f active,ssid dev wifi` (bounded via
  `scripts/tfnsw-bounded`), parses the `yes:` line, and if `Model.placeForSsid`
  finds a place, switches to it (only when the user has not manually picked a
  place in the last 30 min).
- **Notifications** (`notify` true): after each projection, `Model.notificationFor`
  with a `sentTripIds` map (reset daily) → `omarchy-notification-send --app-name
  "Transport NSW" -g <glyph> -u critical -r <tag> <headline> <body>`.
- **Stop search** for the settings picker: `searchStops(text, callback)` debounced
  200 ms, superseding the previous search; returns `parseLocations`.
- **Here mode**: `planFrom(location, callback)` — `location` is a parsed stop_finder
  location (stop id or lat/lon) → `tripPath(origin, activePlace.stopId, 4, now)` →
  `parseJourneys` → `Model.projectJourney` rows in `journeyRows`. Not polled;
  refreshed on demand and while the overlay's Here tab is open (every 60 s).
- Demo mode: `DemoBackend` serves a fake Sydenham board (T4/T8/M1, one cancelled,
  one delayed, one timetable-only, one alert), stop search for "Sydenham",
  "Wynyard", "Circular Quay", and a trip. Times are generated relative to now so
  the countdown works. No keyring, no network.
- `statusLine()` redacted: version, phase, demo, key present, place count,
  active place id, rows, backoff, last polled, error kind.
- Disk cache: write the last good board to `~/.cache/omarchy/tfnsw-departures/board.json`
  (bounded, atomic) and load it at startup so a wake-from-sleep shows stale data
  labelled "as of HH:MM" instead of nothing.

### Bar widget (`Panel.qml`, kind `bar-widget`, category "Info")
- Pill: `ModeBadge` (mode of the next catchable departure) + `pillText`
  ("T4 · 6′" = **leave in**, i.e. departure − walk). Colour: theme foreground
  (like stock widgets); `colorful` config paints the badge in the mode colour.
  Weight/colour: urgency `now` → `Color.urgent`, `soon` → `Color.accent`,
  timetable-only → dimmed. Warning glyph `󰀦` after the text while a disruption
  alert is active. Disconnected → dimmed badge, no text.
- Left click toggles the popup, middle click refreshes, right click opens
  settings overlay.
- Popup (`KeyboardPanel`, ~460 wide): `PanelHero` (big `ModeBadge` in colour,
  title = place name, meta = stop name · "as of HH:MM" · realtime/scheduled ·
  errors); trailing buttons: refresh, "Here" (opens overlay tab `here`), settings.
  Then a `ButtonGroup` of places (hidden if ≤1). Then alert banner(s):
  `Color.urgent` text for disruptions, muted for info, click opens `url` or
  `Api.ALERTS_URL` via `xdg-open`-free `Quickshell.execDetached(["gio","open",url])`
  guarded to https. Then the departure list: `DepartureRow` per row —
  `ModeBadge` small + line, destination, platform, `timeText` (+`plannedText`
  struck when delayed), right-aligned **leave** countdown; cancelled rows
  struck through and dim; "Scheduled" tag when not realtime; hover tooltip
  with the alert title. Empty states: not configured → "Add a Transport NSW API
  key" + Open settings; no places → "Add a place"; nothing catchable →
  "No <lines> services in the next 3 hours".
- Keyboard: ↑↓/jk move, ←→ switch place, Enter no-op (rows have no expansion in
  v0.1), Esc close, Tab next panel. Nothing else.
- IpcHandler target `tfnsw`: `open/close/show/hide/toggle`, `status()`,
  `refresh()`, `settings()`, `here()`, `place(id)`: string, `next()`: string
  (the pill text, for scripts).

### Overlay (`Overlay.qml`, kind `overlay`), tabs `settings` | `here`
- **Settings**:
  - Connection: API key `TextField` (password), Connect / Remove key, status
    text, "Get a key" button opening `Api.REGISTER_URL`, caption with the three
    steps (register → Applications → Add application, tick "Trip Planner APIs"
    → copy key). Demo mode `Toggle`.
  - Places: list of places (name · stop · lines · walk); select to edit, "Add
    place", "Remove". Editor: name; stop picker = `TextField` + results list
    from `service.searchStops` (stops only, show modes); lines (comma text,
    e.g. "T4, T8"); destination contains (text); modes `MultiSelect` from
    `Api.MODES`; walk minutes `NumberField` 0..60; Wi-Fi SSID text with a "Use
    current" button (fills from the service's last seen SSID); "Auto-switch by
    Wi-Fi" `Toggle` (global). Saving writes through `service.savePlaces(list)`.
  - Board: poll seconds `NumberField`, notifications `Toggle`, colourful badge
    `Toggle`.
  - About line with version from manifest and repo link.
- **Here** ("I'm somewhere else"): address `TextField` → results from
  `searchStops` (any type) → pick one → `service.planFrom(location)` → journey
  rows (leave in, depart, summary "walk 6′ → T4 → M1", arrive, changes,
  realtime tag, alert). Destination = active place's stop, shown in a caption
  with a place `Dropdown` to change. Button "Save as place" creates a place
  from the nearest **stop** result (the first `isStop` result in the same
  search) with `walkMinutes` = the first journey's walking leg minutes.

### `ModeBadge.qml`
Circle in the mode colour (from `Api.modeById(mode).color`) with the mode
letter in white, bold, JetBrains Mono. Props: `mode`, `size`, `colorful`
(false → circle in `color` prop, letter in the panel background colour — the
monochrome bar look), `dim`.

### `manifest.json`
```json
{ "schemaVersion": 1, "id": "io.github.vichong.tfnsw-departures", "name": "Transport NSW",
  "version": "0.1.0", "author": "Vic Hong", "license": "MIT",
  "description": "Next train, metro, bus, ferry or light rail from Transport NSW, in the Omarchy bar — so you know when to leave.",
  "kinds": ["service", "bar-widget", "overlay"],
  "entryPoints": { "service": "Service.qml", "barWidget": "Panel.qml", "overlay": "Overlay.qml" },
  "barWidget": { "displayName": "Transport NSW", "description": "Leave-in countdown for your next service.",
                 "category": "Info", "allowMultiple": false, "defaultSection": "right" } }
```

## Hard constraints (red-team checklist — these get reviewed)
- API key: keyring only, never in config/logs/statusLine/`Process.command`
  (curl gets it via stdin config, exactly like Gorelo).
- Every network call: curl with `--proto =https`, no redirects, `--max-filesize
  Api.MAX_RESPONSE_BYTES`, `--max-time`, origin check, one worker, generation
  tags, every request completes exactly once, deadline+kill.
- Every subprocess output bounded (`scripts/tfnsw-bounded` or `--max-filesize`).
- No shell string interpolation anywhere; commands are arrays.
- URLs opened externally are `https://` only and come from our own constants
  or `Api.httpsOnly`.
- All times shown in local time (`Date` does this); API is UTC.
- Rows/places bounded (`Model.MAX_ROWS`, `ConfigStore.MAX_PLACES`, `Api.MAX_*`).
- Quota: default polling ≤ 1 call/min per active place; popup-open 30 s; Here
  refresh 60 s only while visible; searches debounced. Nothing polls while
  `phase !== connected`.
- Demo mode makes zero network/keyring calls.
- No letter shortcuts in the popup (Omarchy kit conventions only).
- README: what it is, screenshots table (paths under `docs/screenshots/`, may be
  placeholders), install via `omarchy plugin add`, getting a key (3 steps, Bronze
  plan 60k/day), setup, config file shape, Wi-Fi auto-switch, keyboard, IPC
  scripting, removal, "not affiliated with Transport for NSW" notice, data
  licence note (TfNSW Open Data, CC BY 4.0, attribution).

## Definition of done for this milestone
- `omarchy plugin validate .` passes.
- `node tests/test_*.js` all pass; add `tests/test_demo.js` for `Demo.js`.
- The plugin loads in the running shell (`omarchy-shell shell rescanPlugins`,
  `omarchy plugin list --json` shows it), Demo mode shows a board, the real key
  shows Sydenham departures, and `omarchy-shell tfnsw status` returns a line.
- Report at the end: files written, what was verified by running it, anything
  left undone, with exact commands.

## v0.2 UI round (after the cleanup): TripView-inspired popup

Reference: tripview.com.au screenshots (the most-used NSW transit app). Adopt:
1. **Countdown block** on the left of each `DepartureRow`: a solid block in the
   mode colour (`Api.modeById(mode).color`), ~Style.space(64) wide, full row
   height, with the leave-in number large ("Now" / "6" + small "min") in white.
   Dimmed (0.6 alpha) when timetable-only; `Color.urgent` when leave-in ≤ 2 min;
   grey when cancelled. The right column then shows only the clock time
   (planned struck-through under it when delayed).
2. **Collapsed alerts**: one banner line "󰀦 3 alerts · tap for details" (red if
   any `disruption`, muted otherwise); click toggles the full list. Remember the
   expanded state while the popup stays open.
3. **Hero meta**: "Sydenham Station · realtime · updated 22:41" (add seconds
   only when `stale`).
4. **Places switcher**: keep the `ButtonGroup`, prefix each label with the mode
   roundel letter of the place's first line when `colorful`.
5. **Bar icon** = `TransportMark` (mono, `colorful` config → gradient);
   popup hero and overlay header = `TransportMark { colorful: true }`.
   `ModeBadge` remains on rows and in the countdown block.
Do not add: maps, occupancy, run numbers.

## v0.3: places become trips (origin → destination), with arrival time

Every NSW app labels saved items as trips: Opal Travel's Home/Work buttons are
*destinations* under "Where to?", NextThere's widget reads "North Sydney to
Crows Nest", TripView stacks From/To. A bare "Home" chip is therefore read as
"where I'm going", which is the opposite of our v0.1 meaning. Fix the model and
the labels together:

- **Config**: a place gains optional `destStopId` + `destStopName` (validated
  like `stopId`; both or neither). Existing configs stay valid.
- **Board source**: with a destination, the service polls
  `Api.tripPath(place.stopId, place.destStopId, 6)` instead of `departure_mon`,
  and `Model.boardFromJourneys(journeys, place, now)` turns each journey into a
  board entry (same shape as a departure, plus `arriveMs`, `travelSec`,
  `changes`, `legsSummary`). All existing filters, pill, urgency, alerts and
  notifications then work unchanged. Without a destination, behaviour is v0.2.
- **Rows** (`Model.projectRow`): `arriveText` ("23:27"), `travelText` ("26 min"),
  `changesText` ("1 change"); the row's right column shows depart → arrive on
  one line, travel time under it. Pill gains the arrival: `T4 · 6′ → 23:27`
  when a destination is set (`Model.pillText`).
- **Labels**: place chips read `From Home` when no destination and
  `Home → Wynyard` when one is set (`Model.placeLabel(place)`); hero title is
  the place name, hero meta `Sydenham Station → Wynyard Station · realtime ·
  updated 22:41`. The Here tab's "Plan to" dropdown lists destinations as
  `<name> (<destStopName or stopName>)`.
- **Editor**: a second stop picker "Going to (optional)" under the origin
  picker in the place editor; Save-as-place from Here fills it with the active
  place's stop.
- Poll cost is unchanged: one call per poll either way.

### v0.3 addendum: multi-leg journeys (e.g. Surry Hills L3 → Central → M1 Chatswood)
Verified live (fixture `tests/fixtures/trip_surry_hills_to_chatswood.json`): the
trip API returns both ride legs with realtime, platforms and per-leg alerts;
`Model.boardFromJourneys` already yields `changes`, `legsSummary` ("L3 → M1")
and arrival. Show it the way TripView's trip detail does:
- **Collapsed row**: countdown block in the *first* leg's mode colour; title
  `L3 → M1 · Chatswood`; subtitle `1 change at Central · 26 min`; right column
  `11:28 PM → 11:54 PM`. No change → as before.
- **Expanded row** (click/Enter, one open at a time like the Gorelo queue): one
  line per leg with a small `ModeBadge`, `L3  Surry Hills 11:28 PM → Central
  Chalmers St 11:31 PM · realtime`, then a muted `change · 9 min` line for the
  gap (or `walk 4′` when the API gives a walking leg), then `M1  Central
  11:40 PM · Platform 26 → Chatswood 11:54 PM`. Per-leg alert titles under the
  leg in `Color.urgent` when it is a disruption. The service must expose the
  raw legs per board entry (`legs` on the entry from `Model.boardFromJourneys`,
  or a `legsFor(depId)` lookup) so `DepartureRow` can render them.
- The pill stays `L3 · 9′ → 11:54 PM`; the notification body appends
  `· change at Central`.
- **Direction per leg**: each leg's `destination` is the headsign the platform
  indicator shows ("Tallawong", "Circular Quay"). Collapsed trip row title =
  first leg `line` + headsign, e.g. `L3 towards Circular Quay`, with the
  journey's end only in the right column (arrival) — that is what you need at
  the first stop. Expanded legs: `M1 towards Tallawong · Platform 26 · alight
  Chatswood 11:54 PM`. Plain departure rows keep the headsign as now.

## v0.5: station indicator-board language (TfNSW wayfinding, with the Omarchy twist)

Reference: the platform "Next service" boards. Their hierarchy is: line badge
(rounded square in the *line* colour, white bold code) + destination, large;
a stop list; "Platform 1" large; "Departs 2 min" large; small dark pills for
"8 carriages" / "All stops". We keep that hierarchy and vocabulary but stay in
the Omarchy theme: panel background and foreground from `Color`, mono bar,
`Color.accent`/`Color.urgent` where the board uses orange, JetBrains Mono.

- **Line badge** (`LineBadge.qml`, replaces `ModeBadge` in rows and legs):
  rounded square (radius ≈ 22% of size), fill `Api.lineColor(line, mode)`,
  white bold code text ("T1", "M1", "L3", "333"), auto-width for long bus
  numbers. `ModeBadge` stays for mode-only contexts (place editor results).
- **Countdown block** keeps its role but takes the line colour, not the mode
  colour, and its label becomes the board's wording: big number + "min", or
  "Now". Below the number, small: "Departs" (the board word).
- **Collapsed row** = the board's top line: `LineBadge` + headsign in
  Style.font.body bold; second line `Platform 2 · On time · L3 → M1`.
- **Expanded row** = a mini board:
  ```
  [L3] Circular Quay                              Platform  2
  Surry Hills · Central Chalmers St                Departs 6 min
  ─ change · 5 min at Central ─
  [M1] Tallawong                                  Platform 26
  Central · Chatswood                             12:04 AM
  ```
  Each ride leg: badge + headsign (bold), then its stop sequence from
  `leg.stops` (names joined with " · ", eliding to the first 6 and "… +N" when
  longer; if the API gave no intermediate stops show `from · to`), right column
  "Platform N" (caption label over a bold number, like the board) and, for the
  first leg, "Departs" over the leave-in minutes; for later legs the arrival
  clock. Alerts under their leg as now. Walk legs: `walk 4′ · from → to`.
- **Pills**: a small filled pill (Color foreground at 15% alpha, caption
  text) after the headsign for `realtime`/`scheduled` and `direct`/`1 change`
  — the board's "All stops"/"8 carriages" treatment.
- **Hero**: unchanged (Transport mark, place name, route meta).
- Nothing white: the boards are white/black/orange; ours are theme colours.
- **Walk time must be visible**: the countdown is *leave-in* (departure −
  `walkMinutes`), so (a) hero meta becomes `Surry Hills → Chatswood · 6 min
  walk · realtime`; (b) the countdown block's small label is **"leave"** (not
  "Departs") — the board's "Departs" word goes next to the departure clock in
  the row's right column ("Departs 11:40 PM"); (c) when `walkMinutes` is 0 the
  label is "departs" and the hero omits the walk; (d) the place chips'
  tooltip shows `Surry Hills Light Rail → Chatswood Station · 6 min walk`.

## v0.5.1: bar shows the icon only
The bar widget shows only the Transport mark by default; the countdown text
is opt-in via a per-instance layout setting in `shell.json`
(`{ "id": "io.github.vichong.tfnsw-departures", "showCountdown": true }`,
read with `setting("showCountdown", false)`, mirroring Gorelo's `showCount`).
The icon itself still carries the two quiet cues: `Color.urgent` tint when
urgency is "now", and the warning glyph while a disruption alert is active.
Tooltip keeps the full pill text. README documents the setting.

## v0.5.1 addendum: urgency as a progress underline (no red in the bar)
- The bar mark stays in the theme foreground (or the line colour when
  `colorful`). It never turns `Color.urgent`.
- Under the mark, a hairline (height = the bar's active-underline thickness,
  see how `WidgetButton`/the bar draws the active indicator) in the **line
  colour** of the next catchable service, filling left→right as leave-in runs
  from 10 min to 0: width = clamp(1 − leaveIn/10min, 0, 1) × icon width.
  Hidden when leave-in > 10 min or nothing catchable. Recomputed on the
  15 s clock tick (`Service.leaveInMs` for the next service exposed as a
  property, plus `nextLineColor`).
- In the last 2 minutes only, a small caption number ("2", "1", "now") in the
  line colour appears right of the mark. Not before.
- Disruption glyph unchanged. Tooltip keeps the full pill text.
- `showCountdown: true` still shows the full text pill instead.

## v0.5.2: flat bar, leave window in the popup
None of the stock bar widgets carry colour or animate, so neither do we: the
bar shows only the mono Transport mark (plus the disruption glyph), no
underline, no caption, no colour. `showCountdown` stays as the opt-in.
The urgency cue moves into the popup, directly under the hero: a full-width
track (foreground at 15% alpha, 3 units high) with a fill in the **line
colour** of the next catchable service, width = `underlineFraction`
(1 − leaveIn/10 min, clamped), labelled in caption bold "Leave in 4′ · L2 to
Circular Quay". Hidden when leave-in is over 10 min or nothing is catchable.
`Model.barState` also returns `line` and `destination` (headsign) for the
label; `Service` exposes `nextLine` / `nextDestination`.

## v0.5.2 addendum: colour accuracy and contrast
Line colours are the TfNSW GTFS `route_color` values (verified 2026-09-03
from the light rail and metro schedule feeds: L1 BE1622, L2 DD1E25,
L3 781140, M 168388; trains from transportnsw.info line pages). GTFS gives
`route_text_color` FFFFFF for every line, but white fails WCAG on the light
lines (T1 2.1:1, T3 2.9:1, bus 2.4:1, ferry 2.7:1), so badge and countdown
text pick white or near-black by contrast (`Api.lightTextOn`). The
leave-window label is drawn in the theme foreground; only the track fill
carries the line colour (L3 on the panel background is 1.6:1).

## v0.6: the Claude Design revision (popup + settings)
Source of truth for the look: the Claude Design mockup "Transport NSW
Departures UI" (revision 2 + Vic's tweaks, 2026-09-03) and `docs/DESIGN.md`
priorities. Same dimensions as today (popup 460 wide; overlay as now).
Decisions made in review are marked **(decision)**.

### Popup
- **Hero**: TransportMark (colourful) · place **name** (title) · under the
  name a **place selector**: the Ui kit `Dropdown` (caption font, `showLabel:
  false`) whose text is `Model.placeLabel(place)` ("Sydenham → Wynyard") and
  whose options are `effectivePlaces`; selecting calls
  `service.setActivePlace(id, true)`. Hidden when there is one place. The
  chips `ButtonGroup` is removed. ←/→ keys still switch place. Trailing
  controls unchanged (refresh, Here, settings). No route/walk meta line in
  the hero any more.
- **Leave window** (directly under the hero, above alerts): walking
  pictogram (Nerd "󰖃" or the Ui kit glyph) at the left; heading in
  `Style.font.body` bold: "Leave in 3 min" / "Leave now" / "Leave in 1 min"
  (`Model.leaveHeading(leaveMs)`: <60 s → "Leave now", else "Leave in N
  min"); caption under it: "6 min walk · T4 to Bondi Junction" (walk omitted
  when 0; "· line to destination" from `nextLine`/`nextDestination`); track
  as today (3 units, foreground 15%, fill in `nextLineColor`). Visible
  whenever there is a next catchable service; the fill is 0 beyond 10 min.
  No caption on the right. Heading colour = foreground, never red.
- **Alerts** line unchanged (dot + "2 alerts" + chevron).
- **Row** (two lines tall, countdown block 44 units wide with inner padding,
  clock column fixed 88 units, top-aligned):
  - line 1: mode pictogram (17 units, muted) · LineBadge · **primary
    destination** bold (for trips the place's `destStopName` short form;
    for plain departures the headsign) · headsign muted (trips only; elide
    first) · pills · crowding dots (v2, hidden) · chevron (expanded only).
  - pills **(decision)**: `RT` muted-outline chip when realtime (no green
    fill); `1 change`/`2 changes` only when there are changes; no "direct",
    no "scheduled" pill. Dominated rows show **only** `later arrival`; cancelled
    rows show only `cancelled` (the single permitted use of `Color.urgent`,
    on the pill text/border).
  - line 2 caption: `Platform 6 · On time · 28 min → 8:58 AM` (or `Stand C`,
    `2 min late`). Right column: `DEPARTS` caption over the clock, AM/PM in
    muted.
  - **Countdown block**: line colour; big number + "min" + "LEAVE" caption;
    "NOW" when < 60 s; **(decision)** missed → "—" over "MISSED", cancelled →
    "—" over "CANC" (no minute count), both blocks muted with a 1-unit border.
  - **Dominated** (new): `Model.markDominated(board)` sets `dominated: true`
    on any entry whose `arriveMs` is ≥ the `arriveMs` of a later-departing,
    non-cancelled entry (trips only; plain departures never dominate).
    Dominated rows render like missed (50% opacity), keep their countdown,
    and get the `later arrival` pill. Notifications and the leave window
    still use the first catchable *non-dominated* entry (`nextCatchable`
    skips dominated).
- **Expanded board**: as v0.5 but per-leg rows get the mockup's look:
  badge + headsign bold, stop list, `PLATFORM` label over number at the
  right; change row "○ change · 7 min at Central"; final walk row "walk 4 min"
  with "arrive 9:13 AM" right-aligned.
- **Footer** (new, caption, muted): left "updated 12s ago · realtime"
  (`lastPolledMs` relative, refreshed by the 15 s tick; "scheduled" when
  the first row is not realtime); right the date "Thu 3 Sep · 8:29 AM"
  following the bar clock format. Replaces the refresh tooltip's timestamp.
- Six collapsed rows + one expanded must fit within ~900 units.

### Settings overlay
- Header: TransportMark (colourful) + "Transport NSW settings" + close. The
  Settings/Here tab buttons stay in the header row (mockup omitted them).
- **Connection card**: when connected it collapses to one row: green dot ·
  "Connected" · "key in keyring" muted · `Remove` button right. When not
  connected: key field + Connect + Get a key + the three-step help. Demo
  status shows "Demo connected".
- **Places**: section header "PLACES" with `Add place` right. Each place is a
  card: name bold + summary caption ("Sydenham → Wynyard · 6 min walk · T4,
  T8" / "All services") + chevron; exactly one expanded at a time. Expanded
  editor: Name | Walk minutes (NumberField); Leaving from | Going to
  (optional); Wi-Fi SSID + `Use current`; **Filter services** disclosure
  (collapsed by default, summary "2 lines · all modes" or "All services")
  containing Lines as removable chips + "add a line…" field, Destination
  contains (placeholder "All"), Modes as a toggle row with `All` first;
  then `Delete place` (urgent text, left) and `Cancel` / `Save place`
  (accent) right. Placeholders are italic muted and never look like values.
- Auto-switch, poll interval, notifications, colourful toggle: keep, as a
  compact "Behaviour" group between Places and Demo mode.
- **Demo mode** card, then the **footer row** exactly like Gorelo:
  caption "Transport NSW for Omarchy v0.6.0" left, muted link
  "github.com/vichong/omarchy-tfnsw-departures" right-aligned, underline on
  hover, opens the URL via the bounded opener.
- No theme/light-dark control anywhere.

### Tests
`markDominated` (later-but-earlier-arrival marks the earlier one; ties
mark; cancelled never dominates or is dominated; plain departures
untouched), `leaveHeading`, `nextCatchable` skipping dominated, footer
relative time text. Bump manifest to 0.6.0.

## v0.6.1: type-ahead stop search (bundled station list)
Problem: `stop_finder` is a whole-word match ("chat" → Thai restaurants, no
station until "Chatswood"), and the place pickers only searched on Enter.
- `data/stops.json` (≈460 entries, 43 KB; rebuilt by the developer-only
  `scripts/build-stops` from the GTFS schedule feeds): every train station,
  metro station, Sydney Ferries wharf and light rail stop with its Trip
  Planner stop id, `modes`, lat/lon. Loaded once by the Service through a
  `FileView` (bounded: reject files over 512 KiB, non-arrays, entries
  without a numeric-string `id` and non-empty `name`).
- `Model.matchStops(list, text, limit)`: case-insensitive; ranks
  name-starts-with first, then any-word-starts-with, then contains; ties by
  name; at most `limit` (8). Strips a trailing " Station"/" Light Rail"/
  " Wharf N" for display in the picker but keeps the full name in config.
- Pickers ("Leaving from", "Going to", Here): search on **every text edit**.
  From 1 character the local matches appear instantly in the results list
  (mode pictograms next to each). In parallel, from 3 characters, the
  existing debounced `searchStops` runs and its results (addresses, POIs,
  bus stops; deduped against local ids) are appended under a "More" divider
  once they arrive. Enter picks the first result. Picking fills the field
  with the full stop name and clears the results.
- The Here tab uses the same list for stops; addresses still go live.
- Tests: ranking, limit, empty/short queries, malformed list rejected.

## v0.7: "New trip" replaces "From here" (approved 2026-09-03)
Why: the Here tab plans to the active place's *origin* stop while its
dropdown shows routes, never shows where the trip starts once picked, and
renders results in the pre-board style. Vic's model: a **new trip** — put in
where you are, it finds the nearest station, say where you're going, then
optionally save it as one of your trips (like "Raiz"). One concept only: a
trip/place, saved or not. The words "Here" and "Somewhere else" go away.

Entry points:
- Popup hero: the action button between Refresh and Settings becomes
  **New trip** with a plus glyph ("󰐕", tooltip "New trip"). No drive icon.
- Popup route selector: last option "New trip…".
- Overlay: the second tab is labelled **New trip**; overlay title "New trip".
- IPC: `omarchy-shell tfnsw here` keeps working as an alias; add `newtrip`.

Flow (one pane, steps reveal top-down; the pane reuses SettingsPane
field styling):
1. **Where are you?** type-ahead (v0.6.1; NSW addresses come from the
   TfNSW geocoder). Picked → chip with the full name and ×; the field hides.
2. **Nearest stops**: from the picked coordinate, the bundled list sorted
   by distance (≤ 1.5 km, top 3) shown as chips "Surry Hills Light Rail ·
   6 min walk" (walk = round(distance / 80 m per min), replaced by the
   trip's real walk leg once results arrive). Default = nearest; user may
   pick another. If the pick is itself a stop, this step is skipped.
3. **Going to**: `Dropdown` of *stops* derived from every place's origin
   and destination stops, deduplicated, labelled "Chatswood Station · FH
   Work"; plus "Other stop…" opening a type-ahead. Default: the active
   place's destination if it has one, else its origin.
4. **Results**: the popup board reused (leave window with the real walk
   minutes, `DepartureRow`s, expandable legs). Journeys from `trip` with the
   address coordinate as origin so the API chooses the actual first stop;
   if it differs from the chosen chip, the chip updates.
5. **Actions**: `Use now` (accent) creates an unsaved place
   `{ id: "temp", name: <first segment of the address>, stopId, stopName,
   destStopId, destStopName, walkMinutes, lines: [], modes: [] }`, sets it
   active (manual, so Wi-Fi auto-switch does not override it for 30 min),
   closes the overlay; the popup selector lists it as "New trip · 123
   George St → Chatswood" above saved places; picking a saved place
   discards it. `Save as trip` opens the Settings place editor prefilled
   with the same values (name = first segment of the address), where Vic
   names it and saves. Nothing is written to config.json until saved.
- **Journey strip** under each expanded result (reused in the popup): walk
  figure "12 min" → LineBadge "Surry Hills → Central" → change dot →
  LineBadge → "Chatswood". No map (Qt Location is not installed; tiles
  would add an external host).
- Remove "Plan to <stop>." caption, the route dropdown and the old result
  rows.
- Tests: nearest-stops distance ranking and walk estimate; temp place
  shape; selector listing with a temp place; destination list derivation.

## v0.7.1: New trip — nearby stops that never come up empty, destination addresses
Approved 2026-09-03. Vic: "nothing came up for an address" (1.5 km cap, no
bus stops) and "going to: stations, search and/or address search, then pick
the closest station and the walk time from the destination station to the
destination address".

### Nearest stops (step 2)
- Bundled list radius 3000 m, top 3, chips show "· N min walk"
  (round(m / 80)).
- **Bus and other stops from the API**: `Api.coordPath(lat, lon, radiusM)` →
  `/v1/tp/coord?outputFormat=rapidJSON&coord=<lon>:<lat>:EPSG:4326&
  coordOutputFormat=EPSG:4326&inclFilter=1&type_1=BUS_POINT&radius_1=<r>&
  PoisOnMapMacro=true&version=10.2.1.42`. Response `locations[]` are
  platforms: `{ id, name ("The Star, Pirrama Rd, Pyrmont"), type:
  "platform", coord [lat, lon], parent: { id, name }, properties:
  { distance (m) } }`. `Api.parseNearby(data)` → `[{ id: parent.id || id,
  name: parent.name || name (first segment before the comma + ", suburb"),
  metres, walkMinutes, modes: [] }]`, deduplicated by id, sorted by metres,
  bounded to 12. Radius 800 m. Runs through the serialized worker like any
  request; results merge with the bundled ones (bundled entry wins on the
  same id; else by distance), still top 3 chips **plus** a fourth chip
  "More…" that expands to the next 5 when there are more.
- **Never empty**: if both are empty, plan from the address coordinate
  (`planFrom` with the location, walk from the journey's first walk leg —
  the existing code path) and show the API's first stop as the single chip
  with its real walk leg. Caption under the chips in that case: "No stops
  within 3 km — planned from your address".
- Chip selection replans from the chosen stop (as v0.7).

### Going to (step 3): stations, search, or an address
- The `Dropdown` keeps the stops derived from your places, plus
  "Search…" which opens the type-ahead accepting stops **and addresses**
  (local matches first, live results under "More", as the origin field).
- Stop picked → as v0.7.
- **Address picked** → nearest stops to the destination computed the same
  way as step 2 (bundled ≤ 3 km + coord API ≤ 800 m); the closest is the
  **destination stop** (shown as a chip row "Arrive via · Chatswood Station
  · 6 min walk", selectable like step 2). The trip is planned to the
  address **coordinate** (`Api.tripPath` already accepts `{lat, lon}` for
  the destination) so the API returns the final walking leg; the board's
  arrival is at the door; the leave-window caption becomes "1 min walk ·
  L1 to Chatswood · 6 min walk at the end"; the journey strip ends with
  the walk figure and minutes; row caption "37 min → 2:43 PM" is to the
  door.
- Temporary place / Save as trip: `destStopId/destStopName` = the chosen
  destination stop; `destination` (the free-text filter) is left empty;
  the address is kept in a new optional place field `destAddress`
  (ConfigStore: cleanText 120) shown in the editor as the "Going to" value
  when present, and used by Panel/Service to plan to the coordinate when
  the place is active (`destLat/destLon` stored alongside, numbers,
  validated). Tests for ConfigStore and the nearest merge.

## v0.8: crowding (people icons) from GTFS-Realtime vehicle positions
Approved 2026-09-03; same API key, no new registration (verified: the
key already returns the feeds).
- Feeds (`Api.vehiclePosPath(mode)`): buses `/v1/gtfs/vehiclepos/buses`,
  metro `/v2/gtfs/vehiclepos/metro`, trains `/v2/gtfs/vehiclepos/
  sydneytrains`, light rail (none — skip), ferries `/v1/gtfs/vehiclepos/
  ferries/sydneyferries` (check for occupancy; skip if absent). Protobuf
  (gtfs-realtime `FeedMessage`): entity(2) → vehicle(4) → trip(1).trip_id
  (1, string) and occupancy_status(9, enum: 0 EMPTY, 1 MANY_SEATS_AVAILABLE,
  2 FEW_SEATS_AVAILABLE, 3 STANDING_ROOM_ONLY, 4 CRUSHED_STANDING_ROOM_ONLY,
  5 FULL, 6 NOT_ACCEPTING_PASSENGERS).
- **Binary transport**: the curl worker collects text, so binary feeds go
  through `scripts/tfnsw-bounded` with a new first argument mode
  `fetch-b64 <url>` that runs `curl --proto =https --max-filesize … -H
  "Authorization: apikey …" (key via stdin config as today) | base64 -w0`;
  stdout is base64 text bounded by the existing head cap (raise the cap for
  this call to 4 MiB of base64 ≈ 3 MiB binary). Decode in JS
  (`Model.fromBase64` — no `Qt.atob` reliance; hand-rolled table) into a
  byte array and parse with a **minimal protobuf walker**
  (`Model.parseOccupancy(bytes)` → `{ tripId: status }`, varint/length-
  delimited only, unknown fields skipped, hard cap 20 000 entities, stop
  parsing at the byte bound). Tests with a hand-built fixture of two
  entities.
- **Join** (verified 2026-09-03): the vehicle feeds key on the operator's
  AVMS trip id (Metro "0251-001-121-009:1000", trains
  "C763.1396.159.48.D.4.90987024", buses "1360167"). The Trip Planner's
  **trip legs** carry exactly that value as
  `transportation.properties.RealtimeTripId` (also `AVMSTripID`) when
  `TfNSWTR=true` (already sent), so `Api.parseLeg` must keep it as
  `tripId`. `departure_mon` events do **not** carry it (only `gtfsTripId`
  in the "3001.nsw-3-M1…" scheme and a `tripCode`), so crowding is shown
  for trip boards (a place with a destination, New trip, Use now) and not
  for departure-only boards in v0.8; note that in README. A row's crowding
  = the status of its first ride leg's `tripId`.
- **Polling**: only while the popup or New trip pane is open; one fetch per
  mode present in the visible rows, at most every 60 s per mode (bus feed
  ≈ 380 KB); results cached in memory 90 s; never on the bar tick. Counts
  toward the same quota; skip when `quotaBlocked()`.
- **Rendering** (mockup 7×11 glyphs, three of them, gap 2): filled count =
  1 for MANY_SEATS, 2 for FEW_SEATS, 3 for STANDING_ROOM and above; filled
  glyph colour = foreground (not green/amber); unfilled = foreground at
  22%. Tooltip on hover: "Many seats available" / "Few seats available" /
  "Standing room only" / "Full". Hidden when no status is known. Shown on
  the collapsed row after the pills and on each ride leg in the expanded
  board. Nerd glyph: "󰀉" (nf-md-account) at Style.space(11).
- README: a Crowding paragraph (which modes have it; buses and Metro
  reliable, trains sparse, light rail none).

## v0.8.1: the end of an address trip (Vic, 2026-09-03 afternoon)
"That closest station is [chosen], and it's a ten minute walk from there to
your address." Planning stop-to-stop at the destination end was wrong: from
a bus stop to a bus stop the planner had no service until the next morning.
**Hybrid model:** for an address destination the trip is planned to the
coordinate by default, the planner's actual last ride stop becomes the
highlighted "Arrive via" chip (prepended if it was not among the nearest),
and its final walking leg is the walk shown. A caption under the chips says
it plainly: "Get off at Martin Place · 7 min walk to 1 Bligh St"; the
leave-window caption ends "· then 7 min walk". Clicking another chip
**overrides**: the trip is planned to that stop and the walk from it to the
address (distance estimate) is appended as a final walk leg
(`Model.appendEndWalk`), so the board still arrives at the door. Origin
keeps the v0.7 behaviour (planned from the chosen chip; default nearest).
Saved / temporary places store `destWalkMinutes` with `destAddress` and are
planned to `destStopId` with that walk appended. Scriptable steps:
`omarchy-shell tfnsw newtripFrom "<text>"` / `newtripTo "<text>"` pick the
first search result. Status line reports `journeys=` and `plan=` for
diagnosis. Gotcha recorded: `Array.isArray` fails for arrays that crossed a
QML `property var` — model helpers test `.length` instead.

## v0.9: journey-chain rows (Claude Design variant 2a, Vic, 2026-09-04)
Source of truth: `docs/handoff/2a/README.md` and the `id="2a"` block of
`docs/handoff/2a/TfNSW Departures Mockups.dc.html` (inline CSS; transcribe
the numbers, do not eyeball). 1 CSS px = 1 `Style.space` unit. Colours stay
theme tokens (`Color.foreground` at the mock's alphas), never the mock's
Tokyo Night hexes.

**What changes (collapsed row, `DepartureRow.qml`):** line 2 under the
destination is no longer the caption ("Platform 1 · on time · 24 min →
9:13 AM"). It becomes the **chain**: `walk-glyph N › badge › [walk-glyph N
› badge …] › walk-glyph N · → 9:13 AM · Platform 1`.
- Chain row: flex, gap 6, align centre. Walk item = glyph 9×12 + minutes,
  10/500 fg-2 (`fg` at 0.78) for the place walks, muted for a change walk
  (the mock shows the 7-min change in muted). Separator "›" 10 muted.
  Chain badges are `LineBadge` size 17, minimum width 22, font 9/700.
- Trailing caption 10 muted, `elide` right, `flex 0 1 auto`: "· → {arrive}
  · Platform {n}" with the **arrival first** so truncation eats the
  platform (buses: "Stand C"). Cancelled: caption is the status text.
  Dominated rows: caption ends "· later arrival" and the "later arrival"
  pill goes away (the README calls it a caption, not a pill).
- The chain items come from `Model.legRows`: walk → walk item, ride →
  badge, change → walk item with the change minutes (muted). Two rides
  with no change row between them get just "›".
- **Leading walk:** stop-to-stop plans have no walk leg for the place's
  own walk. `Model.legRows(entry, occupancy, walkMinutes)` synthesises a
  leading `walk` row when `walkMinutes > 0` and the first leg is not
  already a walk: `minutes = walkMinutes`, `departText = clock(departMs −
  walk)`, `arriveText = clock(first ride departMs)`. `Service.legsFor`
  passes the active place's `walkMinutes`. Never double a walk that the
  planner already returned (address-origin trips).
- Rows without legs (a plain departure board, no destination): chain is
  `[walk N ›] badge · Platform n` so every row reads the same way.
- Headsign min-width 70 on ordinary rows, 0 on rows with two or more pills
  (mock: the crowded M1 row lets the headsign vanish first).

**Expanded board:** the strip `Flow` at the top of the board is **removed**
(the chain now lives on the collapsed row). Board margin becomes
`0 12 12 73` (indented under the text column), 1 px hairline at fg 0.14,
radius 6, bg background at 0.28. Rows mirror the chain top to bottom:
- walk row (padding 7 11): glyph 10×13 muted, "walk 6 min", right side
  **"leave 8:36 AM"** for the leading walk and **"arrive 9:13 AM"** for the
  final walk (a walk between rides reads "walk 5 min" with "8:51 → 8:56 AM").
- leg row (padding 10 11 9): mode pictogram (kept from v0.8, Vic's request)
  · badge 19 · headsign 11/600 fg with the departure clock 10 muted
  baseline-aligned after it (gap 8) · stop list 10 muted line-height 1.5 ·
  right: PLATFORM label-over-value (8/500 .14em muted over 12/600 fg,
  margin-top 5) and the crowding glyphs beneath as now.
- change row: 5 px hollow circle, "change · 7 min at Central", right side
  "8:51 → 8:58 AM" (previous leg arrive → next leg depart); hairline top and
  bottom. `legRows` change rows need `departText` (arrival of the previous
  ride) and `arriveText` (departure of the next ride) filled in.
- Chevron on the expanded row stays where it is (accent, rotated).

**Not in scope:** hero, leave window, alerts band, footer and settings
already match 1a/1b and stay as they are. TransportMark stays ours.
Tests: extend `tests/test_model.js` for the leading-walk synthesis (no
double walk when the first leg is a walk) and change-row times.

## v0.10: trips, named selector, address-or-stop ends, walk overrides (Vic, 2026-09-04)
Vic's three asks rolled into one round. Vocabulary from here on: **trip**
(the saved thing, formerly "place"), **address** (a door), **stop** (a
platform). Internal config key stays `places`; the `place` IPC stays as an
alias. Only words and the end model change.

### Part A — data model, labels, planning (ConfigStore.js, Model.js, Service.qml, tests)

**Per-end config.** Each trip has two ends. Fields, all optional except
`stopId`:
- origin: `stopId`, `stopName` (as now), **new** `address` (≤120), `lat`,
  `lon` (only kept together with a non-empty address, bounds-checked as for
  dest), `walkMinutes` (0–60, as now), **new** `walkEstimated` (bool; default
  `false` for existing configs, `true` when the app computed it).
- destination: `destStopId`, `destStopName`, `destAddress`, `destLat`,
  `destLon`, `destWalkMinutes` (as now), **new** `destWalkEstimated` (bool).
- Derived, in Model: `endKind(place, "origin"|"dest")` → `"address"` when
  the address is non-empty, else `"stop"`. Missing `walkEstimated` on load →
  `false` (migration rule: whatever Vic saved is his number now).
- `walkMinutes` is allowed on a stop end too (someone who knows their walk),
  so no field is gated on kind except lat/lon on address.

**Labels (Model.js).**
- `tripName(place)`: the nickname; for the temp New trip place (id `temp`)
  or an empty name, fall back to `routeLabel`.
- `routeLabel(place)`: "Sydenham → Wynyard" for stop ends, the address's
  first segment for address ends ("Home" is never repeated here: the route
  uses stop/address names, not the nickname). No destination → "Sydenham
  departures". Drop the "From X" and "New trip · " forms everywhere.
- `routeCaption(place)`: `routeLabel` + " · N min walk" when origin walk >
  0, + " · then M min walk" when dest walk > 0 (the hero caption).
- `placeLabel` is retired; `placeTooltip` keeps its shape but uses
  "departures" instead of "From".
- Settings list summary: `routeCaption` + filter summary as now.

**Planning (Service.qml).** Always stop to stop. The active-place poll
plans `tripPath(stopId, destStopId)` and appends the end walk from
`destWalkMinutes` whenever it is > 0 (not only when there is an address).
`planFrom` for New trip: origin is the chosen origin stop, destination is
the chosen destination stop; the coordinate-destination path and
`actualEndStop`-driven chip prepending go away. Keep `originFallback`
(replan from the origin coordinate once when the chosen stop has nothing in
the horizon; caption as now). `legsFor` / `journeyLegsFor` keep passing the
origin walk. The leave window uses origin `walkMinutes` as now.

**Walk estimate helper.** `Model.walkEstimate(fromLatLon, stop)` → minutes
(`round(metres/80)`), reused by both ends; the nearby lookups already
return `walkMinutes` per stop, so this is just the shared naming.

**Tests.** `test_config`: new fields round-trip, lat/lon dropped without an
address, `walkEstimated` defaults false, legacy place (only `walkMinutes`,
`destAddress`, `destWalkMinutes`) loads unchanged with both estimated flags
false. `test_model`: `tripName`/`routeLabel`/`routeCaption` for the four
combinations (stop/address × with/without destination) and for `temp`.

### Part B — UI (Overlay.qml, SettingsPane.qml, Panel.qml)

**Hero (Panel.qml).** The selector chip shows `Model.tripName` in
`Style.font.title` weight 600 with the chevron; it replaces the "Home"
title Text (delete the title; the chip is the first line beside the
TransportMark). Under the chip: `Model.routeCaption` in `Style.font.caption`
muted, elided. Dropdown options: label = `tripName`, with `routeLabel` as
the secondary text — the kit `Dropdown` only takes `label`, so compose
`tripName + "  " + routeLabel` with the route part after two spaces (the
list is a plain string per row; keep it one line, elide). "New trip…"
stays last. Hero height may grow by the caption line; check the popup
still fits with six rows + one expanded (≈ 900 units).

**Settings wording (SettingsPane.qml).** Section "TRIPS"; buttons "Add
trip", "Save trip", "Delete trip"; empty state "Add your first trip."; the
SSID help text and any other "place" copy say "trip". Row title =
`tripName`, summary = `routeCaption` + filters.

**End editor, shared by New trip and the Settings editor.** Both "Leaving
from" and "Going to (optional)" become an **EndEditor** component
(`EndEditor.qml`, new file) so the two screens cannot drift:
- Row 1: label ("Leaving from" / "Going to (optional)") and, right-aligned,
  a two-way segmented toggle **Address | Stop** (same chip styling as the
  Modes chips: selected = accent border + accent 0.14 fill + fg; unselected
  = fg 0.16 border, muted). Default: Address when the end has an address,
  else Stop; for a brand-new end default Address on origin (the "where are
  you" question) and Stop on destination.
- Row 2: the search field. Stop mode: bundled station type-ahead as now
  (`Dropdown` of matches). Address mode: address search as now (stop_finder
  `type_sf=any`), then the nearby-stop chips with the mode filter row and
  the chosen chip highlighted (reuse the existing `NearbyChips` / New trip
  chip code; move it into the component).
- Row 3: **walk line**. Address mode: `󰖃  [ 6 ] min walk to <chosen stop>
  · [✓] estimate`. The number is a `NumberField` (0–60). While the estimate
  box is ticked the field is read-only-looking (muted) and follows the
  chosen chip; unticking makes it editable and the value is kept (also when
  the chip changes) until re-ticked, which snaps back to the estimate.
  Stop mode: `󰖃  [ 0 ] min walk to this stop` with no estimate box (walk
  is the user's number, default 0). Destination end says "walk from
  <chosen stop>" / "walk from this stop".
- The old "Walk minutes" stepper next to Name is removed. The old
  `WalkStrip` in New trip is replaced by the two walk lines.
- Values exposed by the component: `kind`, `stopId`, `stopName`, `address`,
  `lat`, `lon`, `walkMinutes`, `walkEstimated`, plus `nearby` (for the New
  trip caption "Get off at X · N min walk to <address>", which stays).

**New trip pane.** Uses two EndEditors ("Where are you?" keeps its heading
above the origin editor; "Going to" above the destination). "Use now" and
"Save as trip" build the temp/saved place from both editors' values. The
save dialog asks for the nickname as now (default: origin stop's board
name).

**Settings editor.** Name | Wi-Fi SSID on the top row (the stepper's slot
is freed), then the two EndEditors stacked full-width, then Filter
services, then the footer row. Save writes all per-end fields.

**Hard rules.** No new IPC needed except that `newtripFrom`/`newtripTo`
keep working (they act on the editors). Never write the API key anywhere.
Keep `Array.isArray` out of model helpers (length test). One property
assignment per property. Inline components can't see outer ids: pass
widths in. Kit `Dropdown` face is hidden with `opacity: 0` where a custom
chip is drawn. Heights: buttons `Style.space(30)`, inputs `Style.space(30)`,
chips `Style.space(24)`, as the Gorelo plugin. Run all tests and
`omarchy plugin validate .` before finishing; no restart, no commit.
