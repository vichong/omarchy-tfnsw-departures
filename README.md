# Transport NSW departures for Omarchy

A shell plugin that puts the next catchable Transport for NSW service in the
Omarchy bar. The countdown is **leave in** time: departure time minus your walk
to the stop. The popup shows departures, platforms, realtime delays,
cancellations and disruption alerts; the Here view plans a trip back to your
active place.

| Departures | Settings | From here |
|---|---|---|
| `docs/screenshots/departures.png` | `docs/screenshots/settings.png` | `docs/screenshots/here.png` |

Screenshots are placeholders for the v0.1 release.

## Install

```bash
omarchy plugin add https://github.com/vichong/omarchy-tfnsw-departures.git --enable --yes
```

Plugins run inside the shell process. Review third-party plugin code before
enabling it.

## Get a Transport NSW API key

1. Register for TfNSW Open Data and open **Applications**.
2. Add an application, choose the Bronze plan (60,000 calls/day), and tick
   **Trip Planner APIs**.
3. Copy the API key, open the widget's settings, paste it, and select Connect.

The key is stored in the system keyring under `service=tfnsw-departures` and
`account=apikey`. It is never written to the config file. Demo mode needs no
key and makes no network calls.

## Setup

Add a place, search for its stop, optionally filter lines, destination text and
modes, then set the walking time. An empty line/mode filter shows everything.
The bar badge can remain monochrome with the rest of Omarchy or use TfNSW mode
colours. Leave-now notifications and polling (30–600 seconds) are configurable.

Configuration lives at
`~/.config/omarchy/tfnsw-departures/config.json`:

```json
{
  "demoMode": false,
  "places": [{
    "id": "home",
    "name": "Home",
    "stopId": "204420",
    "stopName": "Sydenham Station",
    "lines": ["T4", "T8"],
    "destination": "City",
    "modes": ["train", "metro"],
    "walkMinutes": 5,
    "ssid": "Home Wi-Fi"
  }],
  "activePlaceId": "home",
  "autoPlace": true,
  "pollSeconds": 60,
  "notify": true,
  "colorful": false
}
```

With Wi-Fi auto-switch enabled, an exact SSID match selects that place unless
you manually selected a place in the previous 30 minutes.

## Keyboard

In the popup, `↑`/`↓` or `j`/`k` moves through departures, `←`/`→` changes
place, `Esc` closes, and `Tab` moves to the next panel. Enter has no action in
v0.1.

## IPC scripting

```bash
omarchy-shell tfnsw status
omarchy-shell tfnsw next
omarchy-shell tfnsw refresh
omarchy-shell tfnsw place home
omarchy-shell tfnsw open
omarchy-shell tfnsw here
omarchy-shell tfnsw settings
```

## Remove

Remove the key in Settings first if desired, then:

```bash
omarchy plugin remove io.github.vichong.tfnsw-departures --yes
```

This project is not affiliated with or endorsed by Transport for NSW. Transport
data is sourced from **TfNSW Open Data** and used under the Creative Commons
Attribution 4.0 International licence (CC BY 4.0); attribution: Transport for
NSW.
