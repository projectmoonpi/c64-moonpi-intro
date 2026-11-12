#!/bin/bash
# Screenshots of the intro in VICE (NTSC), one per cycle count, combined into one contact sheet.
# usage: tools/shots.sh OUT.png CYCLES...     (the intro starts at about 3.2 million cycles; 1 s = 1.02 million)
cd "$(dirname "$0")/.."
out=$1; shift
tmp=$(mktemp -d)
for c in "$@"; do
  ( perl -e 'alarm 150; exec @ARGV' x64sc -default +saveres -ntsc -warp -sounddev dummy -autostartprgmode 1 \
      -autostart build/moonpi-intro-lz.prg -limitcycles "$c" -exitscreenshot "$tmp/$c.png" >/dev/null 2>&1 ) &
done
wait
python3 - "$out" "$tmp" "$@" <<'P'
import sys
from PIL import Image, ImageDraw
out, tmp, cs = sys.argv[1], sys.argv[2], sys.argv[3:]
ims = [Image.open(f"{tmp}/{c}.png").convert("RGB") for c in cs]
w, h = ims[0].size
sheet = Image.new("RGB", (w * 2, h * ((len(ims) + 1) // 2)))
for i, (c, im) in enumerate(zip(cs, ims)):
    ImageDraw.Draw(im).text((4, 2), f"{(int(c) - 3.2e6) / 1.0227e6:+.2f}s", fill=(255, 80, 80))
    sheet.paste(im, ((i % 2) * w, (i // 2) * h))
sheet.save(out)
P
rm -rf "$tmp"
