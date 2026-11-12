#!/bin/bash
# Build the Project Moon Pi C64 intro: assets -> PRG -> D64.
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/make_assets.py
acme -v1 --cpu 6510 -l build/intro.sym src/intro.a
c1541 -format "moon pi intro,mp" d64 build/moonpi-intro.d64 -write build/intro.prg "moon pi intro" >/dev/null
ls -l build/intro.prg build/moonpi-intro.d64
