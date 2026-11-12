#!/bin/bash
# Build the Project Moon Pi C64 intro: assets -> program -> packed -> PRG -> D64.
# The disk gets two files: "MOON PI INTRO" (packed with Exomizer: smaller, the one to load)
# and "MOON PI INTRO LZ" (our own packer and loader, no third-party code).
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/make_assets.py
acme -v1 -l build/intro.sym $ACMEDEFS src/intro.asm
python3 tools/pack.py
acme -v1 src/loader.asm
files=()
if command -v exomizer >/dev/null; then
  exomizer sfx 0x0800 -q -t64 build/fli.bin@0xc000 build/main.bin@0x0800 -o build/moonpi-intro-exo.prg
  files+=(-write build/moonpi-intro-exo.prg "moon pi intro")
  files+=(-write build/moonpi-intro.prg "moon pi intro lz")
else
  files+=(-write build/moonpi-intro.prg "moon pi intro")
fi
c1541 -format "moon pi intro,mp" d64 build/moonpi-intro.d64 "${files[@]}" >/dev/null
ls -l build/moonpi-intro*.prg build/moonpi-intro.d64
