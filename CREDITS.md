# Credits

## Music

Both tracks are CC0 (public domain), so no attribution is required. It is listed here
because the people who made them deserve it anyway.

| Track | Author | Source |
|---|---|---|
| Heavenly Loop | isaiah658 | [OpenGameArt](https://opengameart.org/content/heavenly-loop) |
| Space Ranger (seamless loop) | Nostromo | [OpenGameArt](https://opengameart.org/content/music-loop-strong-downtempo-seamless) |
| A Brand New Wisdom, Just Saying Tho, Winter Dust, Swinging Sweet | hernandack | [OpenGameArt](https://opengameart.org/content/short-loops-background-music-pack) |
| Title Screen, Level 1, Level 2, Level 3 (from the Retro Game Music Pack) | Juhani Junkala, published by SubspaceAudio | [OpenGameArt](https://opengameart.org/content/5-chiptunes-action) |
| Cynic Battle Loop | Ferk, from "Battle Theme A" by cynicmusic (Alex Smith, cynicmusic.com / pixelsphere.org) | [OpenGameArt](https://opengameart.org/content/cynic-battle-loop) |
| War Theme | Spring Spring | [OpenGameArt](https://opengameart.org/content/war-theme) |
| Chiptune Battle Music (loop) | pmiller | [OpenGameArt](https://opengameart.org/content/chiptune-battle-music) |

Junkala's tracks arrived as WAV and were re-encoded to Ogg Vorbis to keep the download
small; nothing else about them was changed.

## Sound effects

| File | Effect | Source |
|---|---|---|
| `assets/sfx/build.ogg` | a building goes up | supplied by MatyanKass |

Everything else is synthesised in code at startup by [src/ui/sfx.gd](src/ui/sfx.gd) - a
pitch sweep, a voice and a decay envelope each. Any of them can be replaced by dropping
a file into [assets/sfx](assets/sfx); see the README there.

## Code and art

Everything else in this repository is original. The building glyphs, the map, the app
icon and the interface are all drawn with line primitives at runtime rather than loaded
from image files.
