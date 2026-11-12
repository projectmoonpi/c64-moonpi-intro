#!/bin/bash
# FLI sprite-timing calibration: build with CAL=1 and the given K6 K7 K67 sets, screenshot the left edge.
# usage: tools/cal.sh OUT.png "K6 K7 K67" ...      (FLI lines 40-69: sprite 6; 70-81: both; 82-90: sprite 7)
cd "$(dirname "$0")/.."
out=$1; shift
tmp=$(mktemp -d)
for v in "$@"; do
  set -- $v
  ACMEDEFS="-DCAL=1 -DK6=$1 -DK7=$2 -DK67=$3" ./build.sh >/dev/null 2>&1 || { echo "build failed for $v"; exit 1; }
  perl -e 'alarm 150; exec @ARGV' x64sc -ntsc -default -warp -sounddev dummy -autostartprgmode 1 \
     -autostart build/moonpi-intro.prg -limitcycles ${CALCYC:-11600000} -exitscreenshot "$tmp/$1$2$3.png" >/dev/null 2>&1
done
python3 - "$out" "$tmp" <<'P'
import sys, glob, os
from PIL import Image, ImageDraw
out, tmp = sys.argv[1:]
files = sorted(glob.glob(f"{tmp}/*.png"))
tiles = []
for fn in files:
    im = Image.open(fn).convert("RGB")
    c = im.crop((0, 35 + 20, 200, 35 + 120)).resize((400, 200), Image.NEAREST)
    d = ImageDraw.Draw(c)
    d.text((4, 2), "K " + os.path.basename(fn)[:-4], fill=(255, 60, 60))
    for y in (40, 70, 82, 91):                       # region marks (FLI lines)
        d.line((380, (y - 20) * 2, 399, (y - 20) * 2), fill=(255, 60, 60))
    tiles.append(c)
sheet = Image.new("RGB", (800, 200 * ((len(tiles) + 1) // 2)))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % 2) * 400, (i // 2) * 200))
sheet.save(out)
P
rm -rf "$tmp"
