#!/bin/bash
# Build the Project Moon Pi C64 intro: assets -> program -> packed -> loader PRG -> D64.
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/make_assets.py
acme -v1 -l build/intro.sym $ACMEDEFS src/intro.asm
python3 tools/pack.py
acme -v1 src/loader.asm
c1541 -format "moon pi intro,mp" d64 build/moonpi-intro.d64 -write build/moonpi-intro.prg "moon pi intro" >/dev/null
ls -l build/moonpi-intro.prg build/moonpi-intro.d64
