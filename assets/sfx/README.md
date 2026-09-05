# Sound effects

Every effect below is synthesised in code at startup by [../../src/ui/sfx.gd](../../src/ui/sfx.gd),
so the game is never silent. Drop a file in here named after an effect and it replaces
the generated one at the next start — no code change, no registration.

    build.ogg        a building goes up
    upgrade.ogg      a building gains a level
    demolish.ogg     a building is torn down
    capture.ogg      you take a cell
    lost_cell.ogg    a cell of yours is taken, by capture or by a landing
    denied.ogg       the rules refused: reloading, no coins, no people
    ship.ogg         a ship leaves its port
    tap.ogg          any button in the interface
    victory.ogg      you won
    defeat.ogg       you lost

`.ogg` is preferred; `.wav` and `.mp3` also work.

Keep them short. `capture` fires as fast as the cooldown allows — a quarter of a second
on open ground — so anything longer than that will pile up on itself. `build`, `upgrade`
and `demolish` are comfortable up to about half a second; `victory` and `defeat` can run
as long as they like.

Only sounds that are yours or free to use commercially. Anything added here goes in
[../../CREDITS.md](../../CREDITS.md).
