# Regions

Notebook-style 2D grid strategy for two players over a local network.
Build factories, houses, banks, barracks, military bases and ports on your cells;
spend power to take neighbouring cells or to land a ship on a far shore. Last state
standing wins, or most cells after 40 minutes.

Design notes (Russian): [Notes/Игра Regions.md](Notes/Игра%20Regions.md)

## Status

| Milestone | State |
|---|---|
| M0 — project skeleton, deterministic simulation core, headless tests | done |
| M1 — grid rendering, pan/zoom, notebook look | not started |
| M2 — build menu, capture, ships in the UI | not started |
| M3 — LAN lobby, lockstep, desync detection | not started |
| M4 — win screen, sound, balance pass | not started |

## Layout

    src/sim/   simulation core - pure data, no nodes, no rendering, no networking
    src/net/   LAN transport (M3)
    src/ui/    rendering and input (M1)
    tests/     headless tests for the simulation
    tools/     dev scripts
    Notes/     design documents

## Running the tests

    powershell -File tools\run_tests.ps1

No editor and no phone needed. Set `GODOT_BIN` if Godot is not on `PATH`.

## Why the simulation looks the way it does

Both devices run the same tick loop over the same command stream and must reach a
bit-identical state, otherwise the two screens quietly disagree. So `src/sim` uses
integers only (coins and power are stored in hundredths), derives every player figure
from the grid instead of caching it, and exposes `state_hash()` for the host to compare
against each client.

## Balance

Every tunable number lives in [src/sim/balance.gd](src/sim/balance.gd). Nothing else
hardcodes a value, so retuning the match is a single-file edit.
