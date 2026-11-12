#!/usr/bin/env python3
"""Pack the intro for loading: our own small LZ format, unpacked by src/loader.asm on the C64.

Segments (unpacked in this order):  build/fli.bin -> $c000 (the FLI bank),  build/main.bin -> $0800.
Writes build/packed.bin and build/pack.inc (PSIZE).

Stream: per segment the destination (lo, hi), then tokens, then $ff; a destination of $00xx ends it.
  0nnnnnnn             literals: n+1 bytes follow (1-128)
  10nnnnnn o           copy n+2 bytes (2-65) from o+1 bytes back (1-256)
  11nnnnnn lo hi       copy n+3 bytes (3-65) from (hi,lo) bytes back; n = 63 ($ff) ends the segment
On the C64 the packed data is first moved to end at $c000, then unpacked. Unpacking the program
(to $0800 upwards) runs into that area near the end, so the whole thing is simulated here first
to prove no byte is overwritten before it is read.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
TOP = 0xC000


def compress(data):
    out, lits = bytearray(), bytearray()
    heads = {}                      # 3-byte key -> recent positions
    n, i = len(data), 0

    def flush():
        nonlocal lits
        while lits:
            chunk = lits[:128]; lits = lits[128:]
            out.append(len(chunk) - 1); out.extend(chunk)

    def best(i):
        bl, bo = 0, 0
        if i + 2 < n:
            for p in reversed(heads.get(bytes(data[i:i + 3]), [])[-96:]):
                off = i - p
                if off > 65535:
                    break
                l = 0
                while l < 65 and i + l < n and data[p + l] == data[i + l]:
                    l += 1
                if l > bl or (l == bl and off < bo):
                    bl, bo = l, off
                    if l == 65:
                        break
        if bl < 3 and i + 1 < n:      # a 2-byte match is worth it only close by
            for off in range(1, min(256, i) + 1):
                if data[i - off] == data[i] and data[i - off + 1] == data[i + 1]:
                    return 2, off
        return bl, bo

    def add(j):
        if j + 2 < n:
            heads.setdefault(bytes(data[j:j + 3]), []).append(j)

    while i < n:
        l, off = best(i)
        if l >= 3 or (l == 2 and off <= 256):
            if l >= 3 and l < 65 and i + 1 < n:          # one-step lazy match
                l2, o2 = best(i + 1)
                if l2 > l + 1:
                    lits.append(data[i]); add(i); i += 1
                    continue
            flush()
            if off <= 256 and l >= 2:
                out += bytes((0x80 | (l - 2), off - 1))
            else:
                out += bytes((0xC0 | (l - 3), off & 255, off >> 8))
            for j in range(i, i + l):
                add(j)
            i += l
        else:
            lits.append(data[i]); add(i); i += 1
    flush()
    out.append(0xFF)
    return out


def unpack_sim(mem, src):
    """Run the C64 unpacker on a 64K image; return the segments it wrote."""
    def getb():
        nonlocal src
        b = mem[src]; src += 1; return b
    while True:
        dst = getb() | getb() << 8
        if dst >> 8 == 0:
            return
        while True:
            t = getb()
            if t < 0x80:
                for _ in range(t + 1):
                    mem[dst] = getb(); dst += 1
            elif t == 0xFF:
                break
            else:
                if t < 0xC0:
                    ln, off = (t & 0x3F) + 2, getb() + 1
                else:
                    ln = (t & 0x3F) + 3; off = getb(); off |= getb() << 8
                for _ in range(ln):
                    mem[dst] = mem[dst - off]; dst += 1


def main():
    segs = [(0xC000, (BUILD / "fli.bin").read_bytes()), (0x0800, (BUILD / "main.bin").read_bytes())]
    stream = bytearray()
    for addr, data in segs:
        stream += bytes((addr & 255, addr >> 8)) + compress(data)
    stream += b"\x00\x00"
    P = len(stream)
    mem = bytearray(65536)
    mem[TOP - P:TOP] = stream
    unpack_sim(mem, TOP - P)
    for addr, data in segs:
        assert mem[addr:addr + len(data)] == data, f"unpack check failed at ${addr:04x}"
    (BUILD / "packed.bin").write_bytes(stream)
    (BUILD / "pack.inc").write_text(f"PSIZE = {P}\n")
    raw = sum(len(d) for _, d in segs)
    print(f"packed {raw} bytes into {P} ({100 * P // raw}%); unpack simulated and checked")


if __name__ == "__main__":
    main()
