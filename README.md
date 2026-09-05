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
| M4 — win screen, RU/EN interface, Android build, music | done |
| M5 — action modes, upgrades, barriers, hand-drawn interface | done |
| M5 — practice match against a bot, three difficulties | done |

Not in yet: an app icon of our own.

## Playing it

Alone, tap **Игра с ботом**, pick a difficulty and you are in a match against the
machine - no network, no second phone.

Against a person:

1. Build the APK (below) and install it on two phones on the same Wi-Fi.
2. One player taps **Создать комнату**. The other sees the room in the list and taps it.
   If the network eats broadcast traffic, type the host's address instead.
3. Pick one of the three modes along the bottom of the screen. In **build** mode a tap
   on your own cell opens the build menu, and a tap on a building offers to upgrade or
   demolish it. In **attack** mode a single tap takes a bordering cell; the rate of fire
   is limited by a cooldown, a quarter of a second on open ground and four tenths on an
   enemy cell. In **info** mode a tap reports who owns a cell and how they are doing.
   The match ends when one side has no cells left, or after 40 minutes.

## Layout

    src/sim/   simulation core - pure data, no nodes, no rendering, no networking
    src/ai/    the practice opponent
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

## The bot

`src/ai/bot_player.gd` is a plain decision function: it is handed the state both players
share and answers with commands. It never touches the simulation, so it cannot do
anything a tap could not, and the host feeds its commands into the very same tick batch
a second phone would have filled - the match loop cannot tell the two apart.

What it understands, roughly in the order it cares:

* a military base pays its own price back in fifteen seconds, so it buys power before
  anything else, one base per five cells;
* a factory needs somebody to work in it, so houses are only bought when a factory is
  waiting for the people;
* storage is bought when income actually starts spilling over the cap, never earlier;
* it takes built-up enemy cells before open ground - capturing levels the building, so
  that one move is worth a cell and a factory at once;
* buildings go as far from the enemy as the territory allows, because a bank on the
  front line is a gift;
* when the border can no longer grow, it builds a port and lands on the far shore.

Difficulty is reaction time, patience with its power, whether it thinks about ships, and
how much jitter is added to every score - an easy bot picks the second-best cell often
enough to be beatable, a hard one never does. Every choice is integer arithmetic over a
seeded generator, so the same seed replays the same match.

`godot --path . -- --practice` drops straight into a match against the hard bot, which
is the quick way to watch it play without tapping through the lobby.

`tests/test_bot.gd` plays whole matches headless: the bot has to win against the greedy
opener the self-play robot uses, outgrow its own easy setting, never have a command
refused, and get off an island it has filled.

## Balance

Every tunable number lives in [src/sim/balance.gd](src/sim/balance.gd). Nothing else
hardcodes a value, so retuning the match is a single-file edit.
