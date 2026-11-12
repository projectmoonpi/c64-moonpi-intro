#!/bin/bash
# Run the intro in VICE (NTSC C64), in a window.
cd "$(dirname "$0")"
exec x64sc -ntsc -autostart build/moonpi-intro.d64 "$@"
