# Regions

Notebook-style 2D grid strategy for two players over a local network, on Android.

Build houses, factories, banks, barracks, military bases and ports on your cells; spend
power to take a bordering cell, or send a ship straight across open water to land on a
far shore. Last state standing wins, or the larger one after 40 minutes.

Design notes (Russian): [Notes/Игра Regions.md](Notes/Игра%20Regions.md)

## Status - the MVP is playable

| Milestone | State |
|---|---|
| M0 — deterministic simulation core, headless tests | done |
| M1 — map rendering, pan/zoom, notebook look | done |
| M2 — build menu, capture, demolition, ports and ships | done |
| M3 — LAN lobby, lockstep, pause on disconnect, desync resync | done |
| M4 — win screen, RU/EN interface, Android build | done, no sound yet |

Not in yet: sound and music, an app icon, a practice mode against a bot.

## Playing it

1. Build the APK (below) and install it on two phones on the same Wi-Fi.
2. One player taps **Создать комнату**. The other sees the room in the list and taps it.
   If the network eats broadcast traffic, type the host's address instead.
3. Tap your own cell to build, double-tap a bordering cell to take it, tap a port to
   send its ship. The match ends when one side has no cells left, or after 40 minutes.

## Layout

    src/sim/   simulation core - pure data, no nodes, no rendering, no networking
    src/net/   LAN transport, the match clock, and the self-play robot used by tests
    src/ui/    rendering, input, menus
    tests/     headless tests for the simulation
    tools/     dev and build scripts
    Notes/     design documents

## Tests

    powershell -File tools\run_tests.ps1      # simulation rules, headless
    powershell -File tools\run_net_test.ps1   # two real processes play, hashes compared

Neither needs a phone, a window, or the editor. The second one is the important one: it
starts two headless instances, has them host and join over the loopback, plays a scripted
match and fails if the two sides end on different state hashes.

Set `GODOT_BIN` if Godot is not on `PATH`.

## Building the APK

    powershell -File tools\setup_android.ps1   # once per machine
    powershell -File tools\build_apk.ps1       # build\Regions.apk

`setup_android.ps1` installs the Android SDK packages and a debug keystore. It expects
the Android command line tools unpacked into `C:\Android\sdk\cmdline-tools\latest` and
Godot's export templates for the matching engine version installed.

## Why the simulation looks the way it does

The host is the only side with a clock. Each tick it stamps the commands it has received,
applies them, steps the simulation and broadcasts that exact command list; clients step
only when a batch arrives. Both sides therefore run identical input through identical
code, so no rollback is needed and a client can never run ahead of the host.

For that to hold, `src/sim` uses integers only (coins and power are stored in
hundredths), derives every player figure from the grid instead of caching it, and exposes
`state_hash()`. Clients send that hash every five seconds; if it disagrees with the
host's, the host ships a full snapshot rather than arguing about who is right.

## Balance

Every tunable number lives in [src/sim/balance.gd](src/sim/balance.gd). Nothing else
hardcodes a value, so retuning the match is a single-file edit.
