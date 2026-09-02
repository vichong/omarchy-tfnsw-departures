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
