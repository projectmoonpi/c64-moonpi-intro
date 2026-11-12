<p align="center"><img src="docs/img/project-moon-pi-logo.png" width="220" alt="Project Moon Pi"></p>
<p align="center"><b>Designed and Created by Project Moon Pi</b></p>

# Project Moon Pi intro for the Commodore 64

The animated Project Moon Pi logo intro from ProjectMoonPi.com, rebuilt for a real **NTSC Commodore 64**.
It runs for about 8½ seconds:

1. Stars stream out from the middle of the screen, speeding up.
2. The badge flies in as a speck, flipping like a coin (multicolour sprites), and grows.
3. It lands with a white flash and a jolt. The badge appears as a multicolour bitmap, and sparks fly out.
4. A flare runs round the ring and bursts into a starburst. The ring stars twinkle and the engine flames flicker.
5. **DESIGNED AND CREATED BY** and **PROJECT MOON PI** fade in, drawn in the C64's own character set.
6. Everything fades down and the machine goes back to BASIC.

The sound plays on the SID. A string-and-brass chord glides from C7 down to C3 as the badge flies in. Then
comes one bell-like triangle strike and a drum as the starburst fires.

Any key or the joystick fire button skips the intro.

## Running it

```
LOAD"MOON PI INTRO",8
RUN
```

On the Mac: `./build.sh`, then `./run.sh` (VICE, NTSC C64, in a window). `tools/shots.sh` takes VICE screenshots
for checking.

## How it's built

| Part | File |
|---|---|
| Converter: badge → multicolour bitmap, coin sprite frames, sprite script, star tables, SID script | `tools/make_assets.py` |
| 6502 program (ACME assembler) | `src/intro.a` |
| Build: assets → `build/intro.prg` → `build/moonpi-intro.d64` | `build.sh` |

Memory: the program loads at $0801 and ends below $A000. The display uses VIC bank 3: screen colours at
$C000, sprites at $C400–$C9FF, the bitmap at $E000 (RAM under the KERNAL, with `$01 = $35` while it runs).
Two raster interrupts each frame. Line 202–203 switches to hires for the credit rows. Line 251 switches back to
multicolour, updates the sprites and plays the music. The zero page is saved and restored, so BASIC carries on
afterwards.

## Credits

- **Project Moon Pi badge and intro design.** Project Moon Pi (`assets/moon-pi-logo.png`, `moon-pi-logo.fx.json`
  from the ProjectMoonPi.com intro).
- **Character set.** Read at run time from the C64's own character ROM (© Commodore). It is not included here.
- **ACME** cross-assembler. Marco Baye and contributors (GPL).
- **VICE** emulator and `c1541`. The VICE team (GPL).
- **Python, Pillow, NumPy.** Their authors (PSF / HPND / BSD licences).
- **Palette values.** The "colodore" C64 palette by Philip "Pepto" Timmermann.
- Built with Claude Code (Anthropic).
