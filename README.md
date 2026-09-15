# Regions :Beta Edition

Notebook-style 2D grid strategy for two to eight players over a local network, on
Android.

Build houses, factories, banks, barracks, military bases and ports on your cells; spend
power to take a bordering cell, or send a ship straight across open water to land on a
far shore. Last state standing wins, or the larger one after 40 minutes.

Made by [MatyanKass](https://github.com/MatyanKass). All rights reserved - see [LICENSE](LICENSE).

## Download

Builds are on the [Releases page](https://github.com/MatyanKass/regions-game/releases).

* **Windows** - `Regions-windows.zip`. Unpack both files, `Regions.exe` and `Regions.pck`,
  into one folder and run `Regions.exe`. If Windows says "Windows protected your PC",
  click "More info", then "Run anyway".
* **Android** - the `.apk`. Allow installing from unknown sources when the phone asks.

Design notes (Russian): [Notes/Игра Regions.md](Notes/Игра%20Regions.md)

Rules specification (Russian), complete enough to reimplement the game from:
[Notes/MECHANICS.md](Notes/MECHANICS.md)

## Status - the MVP is playable

| Milestone | State |
|---|---|
| M0 — deterministic simulation core, headless tests | done |
| M1 — map rendering, pan/zoom, notebook look | done |
| M2 — build menu, capture, demolition, ports and ships | done |
| M3 — LAN lobby, lockstep, pause on disconnect, desync resync | done |
| M4 — win screen, RU/EN interface, Android build, music | done |
| M5 — action modes, upgrades, barriers, hand-drawn interface | done |
| M6 — app icon, sound effects, more music, Windows build | done |
| M7 — the lobby redrawn, thirteen tracks | done |
| M8 — staffing: a factory with nobody in it earns nothing | done |
| M9 — land pays, so holding ground is worth something | done |
| M10 — world settings, free play, worlds up to 1000 across | done |
| M11 — construction takes time, pause menu, settings | done |
| M12 — saved worlds and a nickname | done |
| M5 — practice match against a bot, three difficulties | done |

Buildings take five to fifteen seconds to go up, depending on what they are. A building
site holds the cell, gives nothing, and shows a bar filling; calling the work off returns
every coin, since nothing was built. The sound of work loops from where the site is,
through an `AudioStreamPlayer2D`, so it comes from that part of the map rather than from
the middle of the screen.

Sound effects are synthesised in code at startup rather than shipped as files, so
retuning one is editing a number. Music is picked at random from
[assets/music](assets/music); calm while the two territories are apart, tense from the
moment they touch.

## Running it on a PC

    powershell -File tools\run.ps1                    # the lobby, same as on a phone
    powershell -File tools\run.ps1 -Practice          # straight into a match against the bot
    powershell -File tools\build_windows.ps1          # a standalone build\Regions.exe
    powershell -File tools\build_windows.ps1 -Share   # build\Regions-windows.zip, to hand out

The desktop build is the same game, mouse instead of finger: drag to pan, wheel to zoom,
click where you would tap. A PC can host a room that phones join, which is the easiest
way to test a match.

## Keeping a world

A world you play alone - free play, or a match against the bot - can be saved from the
pause menu and picked up from the lobby. A save is the simulation's own snapshot, the
same thing the host sends a client that has drifted, so there is one definition of "the
whole state" rather than two that can fall out of step. Half of a match against another
phone is not a world, so those cannot be saved; the button is simply absent.

Your nickname is set in the settings and is what the other player sees, both in the room
list and in the match.

## Choosing a world

The lobby sets up the world before anyone plays in it: how many cells across (25 up to
1000), how much of it is water, and how long a match may run. **Free play** is that same
world with nobody in it - no opponent, no clock, no winning or losing - which is
somewhere to learn the game and somewhere to just build.

A thousand cells across is a million cells. Two things make that possible. The
simulation keeps running totals per player, updated by the handful of places that change
the grid, instead of counting a player's income by walking the map twenty times a
second; `verify_totals()` recounts the slow way and the tests hold the cache to it. And
the map view draws only the cells the camera can see. Neither is an optimisation for its
own sake - without them a big world simply does not run.

## Playing it

Alone, tap **Игра с ботом**, pick a difficulty and you are in a match against the
machine - no network, no second phone.

Against people:

0. Pick where you are playing from. The first run asks; the lobby lets you change it.
   A region is a palette rather than a colour - Africa is yellow, orange or red - and
   which of them your cells come out in is rolled when the match starts, so two people
   from the same continent still get their own pen.
1. Build the APK (below) and install it on the phones, all on the same Wi-Fi.
2. One player sets the number of seats (two to eight), taps **Создать комнату** and
   gets a room code - six characters, like `N50-7W3`. The others either see the room in
   the list and tap it, or type that code into the box below the list. The code is the
   host's address written short, so it works even on the networks that quietly drop the
   broadcast traffic the room list depends on - a phone hotspot, most guest Wi-Fi, and a
   fair few home routers.
3. Everyone who is in shows up in the host's room list, in their own colour. The host
   taps **Начать матч** when the room is full enough; the seats become the player order.
   A match of three or more shows a running scoreline along the top, and one player
   leaving no longer stops the game - their country simply stands there.
4. Pick one of the three modes along the bottom of the screen. In **build** mode a tap
   on your own cell opens the build menu, and a tap on a building offers to upgrade or
   demolish it. In **attack** mode a single tap takes a bordering cell; the rate of fire
   is limited by a cooldown, a quarter of a second on open ground and four tenths on an
   enemy cell. In **info** mode a tap reports who owns a cell and how they are doing.
   The match ends when one country is left, or after the time the host set - and then
   the closing screen is a table of everybody, most ground first.

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

## License

Copyright (c) 2026 MatyanKass. All rights reserved. The source is here to read, and the
released builds are free to download and play; copying, changing or republishing the
game or its code needs the author's written permission. See [LICENSE](LICENSE). The
music belongs to its authors, listed in [CREDITS.md](CREDITS.md).
