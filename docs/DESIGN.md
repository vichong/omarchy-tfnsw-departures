# Design brief

This is a **glance widget**. Its one job: tell Vic when to leave so he can
close the laptop and catch the service. Every UI decision is judged against
the three priorities below, in this order. When they conflict, the higher one
wins.

## Priorities, ranked

1. **Least cognitive effort at a glance.** The answer ("leave in 4 min",
   "leave now", "missed, next in 9") must be readable in under a second,
   from across the desk, without reading a sentence. One primary number per
   row, one primary cue per screen. Secondary detail is available on demand
   (expand, hover, tooltip) but never competes with the primary.
2. **Transport for NSW visual language.** Official line colours (GTFS
   `route_color`, verified 2026-09-03), line badges in the wayfinding shape,
   the mode pictograms, the indicator-board vocabulary ("Departs",
   "Platform 2", "All stops"). People already know this language from the
   station; we borrow it rather than invent one. Deviate only for legibility
   (see contrast rule) and say why in the spec.
3. **Omarchy fit.** Theme colours and fonts from `Style`/`Color`, the stock
   panel and overlay components, the same control heights and spacing as
   the built-in widgets, a flat mono mark in the bar that never colours or
   animates. Colour lives in the popup, not the bar.

A change that adds TfNSW authenticity but costs a glance loses. A change that
looks more Omarchy but breaks a TfNSW convention that carries meaning (a line
colour, "Platform") also loses.

## Glance rules

- The **countdown block** is the primary. Its number is the largest text in
  the row. Its colour is the line colour. Its label is a single word.
- The **leave window** strip is the only urgency cue. Label grammar:
  "Leave now", "Leave in 3′", never "Leave in now". A walk pictogram with the
  allocated minutes explains what the window is.
- **Grey means "not your best option"**: cancelled, missed, or *dominated*
  (a later departure arrives earlier or at the same time; TripView greys
  these). Grey rows stay in place so a gap is explained, never hidden.
- **Destination first for trips.** The user's destination is the bold text;
  the vehicle headsign ("Circular Quay") is secondary. For plain departures
  the headsign is the destination.
- No sentence-length text on the board. Pills for status, one caption line
  for platform · status · arrival.
- Placeholders never look like values. Empty filters read as "All".

## Contrast rule

Text on a line colour is white or near-black, whichever measures higher
(`Api.lightTextOn`). Line colours are never used as small text on the panel
background (L3 on the panel is 1.6:1). Minimum 4.5:1 for body, 3:1 for the
large countdown number.

## Patterns borrowed from the NSW apps

- TripView: greyed rows for dominated trips; crowding people-icons on buses
  (GTFS-Realtime `occupancy_status`, available for buses and Metro, sparse
  for trains, absent for light rail); destination-first trip rows; a
  from/to pair as the screen title.
- Station indicator boards: line badge + destination, stop list, platform
  and departure as label-over-value pairs, small dark pills.
- Opal Travel / AnyTrip: alert banner collapsed to a count until tapped.

## Backlog (design, in priority order)

Items 1–6 are specified as v0.6 in `docs/SPEC.md` (mockup: Claude Design
"Transport NSW Departures UI", 2026-09-03).

1. Leave-window label grammar + walk pictogram with allocated minutes.
2. Dominated-trip greying (`Model`: mark entries whose arrival is not
   earlier than a later departure's).
3. Places as a selector (dropdown) in the hero row instead of chips.
4. Hero reduced to place name + status; route moves to the selector.
5. Destination-first trip rows, headsign secondary.
6. Settings: connection card collapses when connected; places as a list
   with per-place editor; filters under a "Filter services" disclosure;
   demo mode and version at the bottom; empty filters show "All".
7. "New trip" pane replacing "From here" (v0.7, approved): address → nearest stops → going to → board → use now / save as trip.
8. Crowding icons (v2, GTFS-Realtime vehicle positions).

## Process

Mock the change (HTML mock or annotated screenshot) → agree → write the
spec section → Codex builds → Fable verifies on the live shell by screenshot
and audits sibling controls for consistency before calling it done.
