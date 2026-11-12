#!/usr/bin/env python3
"""Build build/moonpi-intro.crt: a Magic Desk cartridge (CRT hardware type 19) that boots the intro.

Bank 0 is the boot code (src/cart.asm). Banks 1..NB hold build/moonpi-intro.prg without its
two-byte load address; the boot code copies them to $0801 and starts it at 2061 (SYS 2061).
"""
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
BANK = 0x2000


def main():
    prg = (BUILD / "moonpi-intro.prg").read_bytes()
    assert prg[:2] == b"\x01\x08", "expected a program loading at $0801"
    assert b"\x9e2061" in prg[:16], "expected the BASIC line SYS 2061"
    data = prg[2:]
    nb = -(-len(data) // BANK)
    assert 0x0801 + nb * BANK <= 0xD000, "too big to copy below the I/O area"
    subprocess.run(["acme", "-v0", f"-DNB={nb}", "src/cart.asm"], cwd=ROOT, check=True)
    boot = (BUILD / "cart0.bin").read_bytes()
    banks = [boot] + [data[i * BANK:(i + 1) * BANK] for i in range(nb)]

    name = b"PROJECT MOON PI INTRO"
    out = bytearray(b"C64 CARTRIDGE   ")
    out += struct.pack(">IHHBB6x", 0x40, 0x0100, 19, 0, 1)   # header size, version, Magic Desk, EXROM 0, GAME 1
    out += name.ljust(32, b"\0")
    for n, b in enumerate(banks):
        b = b.ljust(BANK, b"\xff")
        out += b"CHIP" + struct.pack(">IHHHH", 0x10 + BANK, 0, n, 0x8000, BANK) + b
    (BUILD / "moonpi-intro.crt").write_bytes(out)
    print(f"cartridge: Magic Desk, {len(banks)} banks ({len(banks) * 8} KB)")


if __name__ == "__main__":
    main()
