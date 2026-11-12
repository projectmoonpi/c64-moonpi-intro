#!/usr/bin/env python3
"""Project Moon Pi C64 intro: turn the badge and the website intro's timeline into C64 data.

Writes build/assets.asm (ACME source: labels, constants and !byte tables) for src/intro.asm,
build/fli.bin (the FLI picture: VIC bank 3, $c000-$ffbf) and build/preview-logo.png.

Everything runs on NTSC frames (60 a second). Times come from the website's moonpi-intro.js and
moonpi-splashfx.js, so the C64 version keeps the same rhythm.
"""
import json, math, random, sys
from itertools import combinations
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS, BUILD = ROOT / "assets", ROOT / "build"
BUILD.mkdir(exist_ok=True)

FPS = 60
def F(sec): return int(round(sec * FPS))

# ---- the website timeline (seconds) -> frames ------------------------------------------------
APPEAR, FACE = F(0.35), F(3.3)          # badge appears / lands facing you
FX = FACE + F(0.5)                      # badge light show starts
CREDIT, NAME = F(4.3), F(4.7)           # credit lines fade in
OUT, END = F(7.7), F(8.5)               # fade out, end
LANDON = 8                              # frames of white blank at the landing
TRL = 212                               # frames of the after-landing sprite script

# ---- screen layout ---------------------------------------------------------------------------
# NTSC C64 pixels are about 0.75 as wide as they are tall, so a round badge is 4/3 wider in pixels.
# The landed badge is an FLI picture in character rows 0-21 (176 lines); rows 22-24 are hires credits.
FLI_ROWS = 22
BADGE_H = 172                           # lines
BADGE_W = 232                           # pixels (116 multicolour pixels)
BADGE_X, BADGE_Y = 44, 2                # top-left on screen (FLI-bug columns 0-2 stay empty)
CX, CY = 160, BADGE_Y + BADGE_H // 2    # badge centre (pixels)
SPLIT_ROW = FLI_ROWS
LINE1_ROW, TITLE_ROW = 22, 23
LINE1 = "DESIGNED AND CREATED BY"
TITLE = "PROJECT MOON PI"
SCALE_R = BADGE_H / 300                 # website design units -> rows (its coin is 300 across)
SCALE_X = SCALE_R * 4 / 3               # -> pixels
# sprite blocks for after the landing: the only free 64-byte holes in the FLI bank
# ($x380 in screens 1-7, which hold rows 22-23 nobody displays, and $ff40/$ff80 after the bitmap)
POST_BLOCKS = [30, 46, 62, 78, 94, 110, 126, 253, 254]

# ---- C64 palette (colodore) --------------------------------------------------------------------
PAL = np.array([
    (0, 0, 0), (255, 255, 255), (129, 51, 56), (117, 206, 200), (142, 60, 151), (86, 172, 77),
    (46, 44, 155), (237, 241, 113), (142, 80, 41), (85, 56, 0), (196, 108, 113), (74, 74, 74),
    (123, 123, 123), (169, 255, 159), (112, 109, 235), (178, 178, 178)], dtype=float)
W3 = np.array([2.0, 4.0, 3.0])
LUM = (PAL @ np.array([0.299, 0.587, 0.114]))
DARKER = {0: 0, 1: 15, 2: 9, 3: 14, 4: 2, 5: 11, 6: 0, 7: 15, 8: 2, 9: 0, 10: 8, 11: 0, 12: 11, 13: 5, 14: 6, 15: 12}

fx = json.loads((ASSETS / "moon-pi-logo.fx.json").read_text())
src = Image.open(ASSETS / "moon-pi-logo.png").convert("RGBA")
(FCX, FCY), FR = fx["centre"], fx["radius"]
BOX = (FCX - FR, FCY - FR, FCX + FR, FCY + FR)          # the badge's square in the 512 px picture


GAMMA, SAT, DITHER = 0.72, 1.35, 0.35


def badge(w, h, mirror=False):
    """The badge resized to w x h: RGB array and 0..1 coverage (round, corners cut away)."""
    im = src.crop(tuple(int(round(v)) for v in BOX))
    if mirror:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    n = im.width
    yy, xx = np.mgrid[0:n, 0:n]
    circle = ((xx - n / 2 + .5) ** 2 + (yy - n / 2 + .5) ** 2 <= (n / 2) ** 2).astype(np.uint8) * 255
    a = np.minimum(np.asarray(im)[:, :, 3], circle)
    rgb = np.asarray(im.convert("RGB").resize((w, h), Image.LANCZOS)).astype(float)
    rgb = 255 * (rgb / 255) ** GAMMA                       # lift the deep navy towards C64 blue
    grey = rgb.mean(-1, keepdims=True)
    rgb = np.clip(grey + (rgb - grey) * SAT, 0, 255)
    cov = np.asarray(Image.fromarray(a).resize((w, h), Image.LANCZOS)).astype(float) / 255
    return rgb * cov[:, :, None], cov            # premultiplied on black


def to_screen(px, py):
    """A point in the 512 px picture -> screen pixel (x, y)."""
    return (BADGE_X + (px - BOX[0]) * BADGE_W / (2 * FR), BADGE_Y + (py - BOX[1]) * BADGE_H / (2 * FR))


# =============================================================================================
# 1. The landed badge: a multicolour bitmap (rows 0-18)
# =============================================================================================
def convert_fli():
    """The landed badge as FLI: per 4x8 cell one colour-RAM colour, per line two more, plus black."""
    MW, ROWS = 160, FLI_ROWS * 8
    img = np.zeros((ROWS, MW, 3))
    rgb, _ = badge(BADGE_W // 2, BADGE_H)
    img[BADGE_Y:BADGE_Y + BADGE_H, BADGE_X // 2:BADGE_X // 2 + BADGE_W // 2] = rgb

    def dist(px):
        d = px[..., None, :] - PAL[None, :, :]
        return (d * d * W3).sum(-1)

    twk, flame = set(), set()
    for x, y, _r in fx["stars"]:
        sx, sy = to_screen(x, y)
        twk.add((int(sy) // 8, int(sx) // 8))
    bx, by, bw, bh = fx["flame_box"]
    x0, y0 = to_screen(bx, by); x1, y1 = to_screen(bx + bw, by + bh)
    for r in range(int(y0) // 8, int(y1) // 8 + 1):
        for c in range(int(x0) // 8, int(x1) // 8 + 1):
            flame.add((r, c))

    pairs = np.array(list(combinations(range(1, 16), 2)))          # 105 colour pairs for a line
    c3 = np.zeros((FLI_ROWS, 40), dtype=int)                        # colour RAM per cell
    lp = np.zeros((ROWS, 40, 2), dtype=int)                         # two colours per line per cell
    used = set()
    for r in range(FLI_ROWS):
        for c in range(40):
            blk = img[r * 8:r * 8 + 8, c * 4:c * 4 + 4]            # 8 lines x 4 pixels
            if blk.max() < 8:
                continue
            used.add((r, c))
            d = dist(blk)                                            # 8 x 4 x 16
            cands = range(16)
            if (r, c) in twk or (r, c) in flame:
                cands = [k for k in range(16) if LUM[k] > 150] + [0]
            best = None
            for k in cands:
                base = np.minimum(d[..., 0], d[..., k])              # 8 x 4
                e = np.minimum(base[None], np.minimum(d[..., pairs[:, 0]], d[..., pairs[:, 1]]).transpose(2, 0, 1))  # 105 x 8 x 4
                per = e.sum(2)                                       # 105 x 8
                tot = per.min(0).sum()
                if best is None or tot < best[0]:
                    best = (tot, k, per.argmin(0))
            _, k, pi = best
            c3[r, c] = k
            lp[r * 8:r * 8 + 8, c] = pairs[pi]

    work = img.copy()
    idx = np.zeros((ROWS, MW), dtype=int)
    slot = np.zeros((ROWS, MW), dtype=int)
    for y in range(ROWS):
        for x in range(MW):
            c = x // 4
            if (y // 8, c) not in used:
                continue
            pal = [0, int(lp[y, c, 0]), int(lp[y, c, 1]), int(c3[y // 8, c])]
            px = np.clip(work[y, x], 0, 255)
            d = ((PAL[pal] - px) ** 2 * W3).sum(1)
            s_ = int(np.argmin(d))
            idx[y, x] = pal[s_]; slot[y, x] = s_
            err = (px - PAL[pal[s_]]) * DITHER
            for dx, dy, wgt in ((1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < MW and yy < ROWS:
                    work[yy, xx] += err * wgt / 16

    bank = bytearray(0x4000)                                         # $c000-$ffff as the VIC sees it
    col = bytearray(FLI_ROWS * 40)
    for r in range(FLI_ROWS):
        for c in range(40):
            col[r * 40 + c] = c3[r, c]
            for line in range(8):
                y = r * 8 + line
                bank[line * 0x400 + r * 40 + c] = lp[y, c, 0] << 4 | lp[y, c, 1] if (r, c) in used else 0
                b = 0
                for p in range(4):
                    b = b << 2 | int(slot[y, c * 4 + p])
                bank[0x2000 + r * 320 + c * 8 + line] = b
    twk_cells = sorted(r * 40 + c for (r, c) in used if (r, c) in twk and LUM[c3[r, c]] > 150)
    flame_cells = sorted(r * 40 + c for (r, c) in used if (r, c) in flame and LUM[c3[r, c]] > 150)

    prev = PAL[idx].astype(np.uint8)
    Image.fromarray(prev).resize((640, int(ROWS * 2 * 4 / 3)), Image.NEAREST).save(BUILD / "preview-logo.png")
    return bank, col, used, twk_cells, flame_cells


# =============================================================================================
# 2. The flying coin: multicolour sprite frames
# =============================================================================================
H_LEVELS = [3, 5, 8, 12, 16, 21, 28, 36, 44, 54, 64, 74, 84]
W_LEVELS = [1.0, 0.75, 0.5, 0.25, 0.08]


def ease(p):
    p = max(0.0, min(1.0, p)); return p * p * (3 - 2 * p)


def coin_art(art_w, art_h, mirror):
    """Badge at art_w x art_h sprite pixels -> codes 0 transparent, 1 blue (MC0), 2 own colour, 3 light blue (MC1)."""
    rgb, cov = badge(art_w, art_h, mirror)
    lum = rgb @ np.array([0.299, 0.587, 0.114]) / np.maximum(cov, 1e-3)
    out = np.where(lum < 70, 1, np.where(lum < 150, 3, 2))
    out[cov < 0.5] = 0
    return out


def coin_frame(H, wq, back):
    W = max(2, round(H * 4 / 3 * wq))
    if H <= 21 and W <= 48:
        exp, pxw, ph = 0, 2, 1
        nx, ny = math.ceil(W / 24), 1
    else:
        exp, pxw, ph = 1, 4, 2
        nx, ny = math.ceil(W / 48), math.ceil(H / 42)
    assert nx <= 3 and ny <= 2, (H, wq)
    art_w, art_h = max(1, round(W / pxw)), max(1, round(H / ph))
    art = coin_art(art_w, art_h, back)
    gw, gh = nx * 12, ny * 21
    ox, oy = (gw - art_w) // 2, (gh - art_h) // 2
    grid = np.zeros((gh, gw), dtype=int)
    grid[oy:oy + art_h, ox:ox + art_w] = art
    data = bytearray()
    for sy in range(ny):
        for sx in range(nx):
            blk = grid[sy * 21:sy * 21 + 21, sx * 12:sx * 12 + 12]
            for row in blk:
                for b in range(3):
                    v = 0
                    for p in range(4):
                        v = v << 2 | {0: 0, 1: 1, 2: 2, 3: 3}[int(row[b * 4 + p])]
                    data.append(v)
            data.append(0)
    xc = ox * pxw + art_w * pxw / 2              # art centre within the grid (screen pixels)
    yc = oy * ph + art_h * ph / 2
    return dict(data=data, n=nx * ny, nx=nx, exp=exp, dx=24 * (1 + exp), dy=21 * (1 + exp),
                xbase=int(round(24 + CX - xc)), yc=yc)


def make_coin():
    frames, keys, sched = [], {}, []
    T_APPEAR, T_FACE = APPEAR / FPS, FACE / FPS
    for f in range(APPEAR, FACE):
        t = f / FPS
        p = ease((t - T_APPEAR) / (T_FACE - T_APPEAR))
        sz = 4 + 296 * p ** 1.8                                   # website design units
        q = min(1.0, (t - T_APPEAR) / (T_FACE - T_APPEAR))
        turn = (1 - q) ** 2 * 46 * math.pi
        H = 2 + 82 * (sz - 4) / 296                               # grows to 84 rows (6 sprites), then the flash
        Hq = min(H_LEVELS, key=lambda h: abs(math.log(h / max(H, 1))))
        w = abs(math.cos(turn))
        wq = min(W_LEVELS, key=lambda v: abs(v - w))
        back = math.cos(turn) < 0 and wq > 0.08
        key = (Hq, wq, back)
        if key not in keys:
            keys[key] = len(frames); frames.append(coin_frame(Hq, wq, back))
        fr = frames[keys[key]]
        yoff = 40 * (1 - p) * SCALE_R
        sched.append((keys[key], int(round(50 + CY + yoff - fr["yc"])), int(back)))
    return frames, sched


# =============================================================================================
# 3. Hires sprites for after the landing: sparks, flare, halo, burst
# =============================================================================================
def sprite_from(grid):           # 21 x 24 of 0/1 -> 64 bytes (hires)
    out = bytearray()
    for row in grid:
        for b in range(3):
            v = 0
            for p in range(8):
                v = v << 1 | int(row[b * 8 + p])
            out.append(v)
    return out + b"\0"


def spark_frames():
    rng = random.Random(7)
    pts = [(rng.uniform(-1, 1), rng.uniform(-1, 1)) for _ in range(7)]
    res = []
    for k, spread in enumerate((3, 6, 10)):
        g = np.zeros((21, 24), dtype=int)
        for x, y in pts:
            g[int(round(10 + y * spread * .8)), int(round(12 + x * spread))] = 1
        res.append(sprite_from(g))
    return res


def flare_core():
    g = np.zeros((21, 24), dtype=int)
    for i in range(-11, 12):
        if abs(i) <= 3 or (abs(i) <= 11 and abs(i) % 2 == 0):
            g[10, 12 + i] = 1
    for i in range(-10, 11):
        if abs(i) <= 2 or (abs(i) <= 8 and abs(i) % 2 == 0):
            g[10 + i, 12] = 1
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            g[10 + dy, 12 + dx] = 1
    return sprite_from(g)


def glow(radius, rays=0, seed=1):
    """Expanded sprite (shown 48 x 42): a dithered soft glow, with rays if asked."""
    g = np.zeros((21, 24), dtype=int)
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16
    for y in range(21):
        for x in range(24):
            dx, dy = (x - 11.5), (y - 10) * 1.0
            d = math.hypot(dx, dy)
            v = max(0.0, 1 - d / radius) ** 1.6
            if rays:
                a = math.atan2(dy, dx)
                beam = max(0.0, math.cos(a * rays)) ** 24 * max(0.0, 1 - d / (radius * 2.2))
                v = max(v, beam)
            g[y, x] = v > bayer[y % 4, x % 4]
    return sprite_from(g)


def make_post_sprites():
    blocks = spark_frames() + [flare_core(), glow(7)] + [glow(r, 4) for r in (3, 5, 7, 9)]
    return blocks          # sparks x3, core, halo, burst x4 -> POST_BLOCKS


P_SPARK, P_CORE, P_HALO, P_BURST = 0, 3, 4, 5                       # indexes into POST_BLOCKS


def path_points():
    pts = [to_screen(x, y) for x, y in fx["path"]]
    seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    total = sum(seg)
    def along(u):
        d = u * total
        for i, s in enumerate(seg):
            if d <= s:
                t = d / s if s else 0
                return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
            d -= s
        return pts[-1]
    return along


def make_track():
    """Per frame after landing (idx = frame - FACE): every sprite's pointer, x/2, y, colour; enable and expand bytes."""
    ptr = np.zeros((8, TRL), dtype=int); xh = np.zeros((8, TRL), dtype=int)
    yy = np.zeros((8, TRL), dtype=int); cc = np.zeros((8, TRL), dtype=int)
    en, xe, ye = [0] * TRL, [0] * TRL, [0] * TRL
    along = path_points()
    tip = to_screen(*fx["tip"])
    rng = random.Random(3)
    sparks = [(math.radians(s * 60 + 20 + rng.uniform(-12, 12)), 260 + rng.uniform(0, 360)) for s in range(6)]

    def put(s, i, p, x, y, c, big=False):
        ptr[s, i] = POST_BLOCKS[p]; xh[s, i] = max(0, min(255, int(round(x / 2)))); yy[s, i] = max(0, min(255, int(round(y)))); cc[s, i] = c
        en[i] |= 1 << s
        if big: xe[i] |= 1 << s; ye[i] |= 1 << s

    for i in range(TRL):
        land = (i - LANDON) / FPS
        if False and 0 <= land < 1.8:                         # sparks (now star dots: sprites upset the FLI timing)
            col = [1, 1, 15, 12, 11][min(4, int(land / 1.8 * 5))]
            k = min(2, int(land / 0.6))
            for s, (a, sp) in enumerate(sparks):
                d = 150 + sp * land * (1 - 0.25 * land)        # website units from the centre
                x = CX + math.cos(a) * d * SCALE_X; y = CY + math.sin(a) * d * SCALE_R
                put(s, i, P_SPARK + k, 24 + x - 12, 50 + y - 10, col)
        t = (i - (FX - FACE)) / FPS                             # light-show time
        if 0.3 < t < 2.1 + 0.25:                                # flare along the ring
            u = ease((t - 0.3) / 1.8)
            x, y = along(u)
            k = min(1, (t - 0.3) / 0.25) * (1 if t < 2.1 else 1 - (t - 2.1) / 0.25)
            core = 1 if k > 0.66 else 15 if k > 0.33 else 12
            if t > 0.3 + 2 / FPS:                       # the core 2 frames after the halo: spreads the FLI repatch
                put(7, i, P_CORE, 24 + x - 12, 50 + y - 10, core)
            if t < 2.1:
                put(6, i, P_HALO, 24 + x - 24, 50 + y - 21, 7 if k > 0.66 else 15 if k > 0.33 else 11, big=True)
        if 2.1 <= t < 3.0:                                     # starburst at the tip
            u = (t - 2.1) / 0.9
            b = math.sin(math.pi * u)
            col = 1 if b > 0.7 else 7 if b > 0.45 else 15 if b > 0.25 else 12 if b > 0.1 else 11
            put(6, i, P_BURST + min(3, int(u * 6)) if u < 0.5 else P_BURST + 3, 24 + tip[0] - 24, 50 + tip[1] - 21, col, big=True)
    return ptr, xh, yy, cc, en, xe, ye


def make_flash():
    """idx = frame - FACE: $d011, $d016 x-scroll, border/background colour, for the landing flash and jolt."""
    rows = []
    for i in range(48):
        land = i / FPS
        if i < LANDON:
            rows.append((0x2B, 0, 1)); continue
        a = 0.9 * (1 - land / 0.7)
        c = 1 if a > 0.55 else 15 if a > 0.35 else 12 if a > 0.18 else 11 if a > 0.04 else 0
        j = max(0, 1 - land / 0.45) * 9
        xs = int(round(max(0, min(7, j * SCALE_X * (1 + math.sin(land * 70)) / 2))))
        rows.append((0x3B, xs, c))       # sideways only: FLI sets the vertical scroll on every line
    return rows


# =============================================================================================
# 4. The sound: SID register script, one list of writes per frame
# =============================================================================================
NTSC_CLOCK = 1022727
def fn(hz): return max(1, min(65535, int(round(hz * 16777216 / NTSC_CLOCK))))
def hz(n): return 440 * 2 ** ((n - 69) / 12)


def make_music():
    ev = {}
    def w(f, reg, val): ev.setdefault(f, []).append((reg, val & 0xFF))
    def freq(f, voice, h):
        v = fn(h); w(f, voice * 7, v & 0xFF); w(f, voice * 7 + 1, v >> 8)

    s0, s1 = F(0.2), FACE
    HOLD, STRIKE = FACE + F(1.2), FX + F(2.1)
    w(0, 0x18, 0x1F)                         # low-pass on, volume 15
    w(0, 0x17, 0x43)                         # resonance 4, filter voices 1 and 2
    for v, (ad, sr) in enumerate(((0xC0, 0xF9), (0xD0, 0xF9), (0xC0, 0xFA))):
        w(0, v * 7 + 5, ad); w(0, v * 7 + 6, sr)
    last = None
    for f in range(s0, HOLD + 1):            # the glide: C7 down to C3, with a little vibrato
        t = f / FPS
        u = min(1.0, (f - s0) / (s1 - s0))
        base = hz(96) * (hz(48) / hz(96)) ** u
        vib = 2 ** (6 * math.sin(2 * math.pi * 5.2 * t) / 1200)
        freq(f, 0, base * vib)
        freq(f, 1, base * 0.5 * 2 ** (7 / 1200) * vib)
        freq(f, 2, base * 0.25)
        cut = int(round(0x98 * (0x2C / 0x98) ** u))   # darker as it falls
        if cut != last:
            w(f, 0x16, cut); last = cut
    w(s0, 4, 0x21); w(s0, 11, 0x21); w(s0, 18, 0x11)         # gates on: saw, saw, triangle
    w(HOLD, 4, 0x20); w(HOLD, 11, 0x20); w(HOLD, 18, 0x10)   # gates off: release
    # one triangle strike (bell-like, two partials) and one drum, as the sparkle reaches the tip
    w(STRIKE - 2, 0x17, 0x00); w(STRIKE - 2, 0x18, 0x0F)
    for v, (ad, sr) in enumerate(((0x0C, 0x00), (0x0A, 0x00), (0x09, 0x00))):
        w(STRIKE - 2, v * 7 + 4, 0x00); w(STRIKE - 2, v * 7 + 5, ad); w(STRIKE - 2, v * 7 + 6, sr)
    freq(STRIKE, 0, 1320); freq(STRIKE, 2, 1320 * 2.76)
    for f in range(STRIKE, STRIKE + F(0.9) + 1):              # the drum: a pitched thump that drops
        u = (f - STRIKE) / F(0.9)
        freq(f, 1, hz(36) * (hz(29) / hz(36)) ** u)
    w(STRIKE, 4, 0x11); w(STRIKE, 11, 0x11); w(STRIKE, 18, 0x11)
    stream = bytearray()
    regs = {}
    for f in range(0, max(ev) + 1):
        lst = []
        for reg, val in ev.get(f, []):           # only the writes that change something
            if regs.get(reg) != val or reg in (4, 11, 18):
                lst.append((reg, val)); regs[reg] = val
        assert len(lst) < 120
        stream.append(len(lst))
        for reg, val in lst:
            stream += bytes((reg, val))
    stream.append(0xFF)
    return stream, STRIKE


# =============================================================================================
# 5. Write the ACME include
# =============================================================================================
def table(name, data, out):
    data = [int(v) & 0xFF for v in data]
    out.append(f"{name}")
    for i in range(0, len(data), 16):
        out.append("    !byte " + ",".join(f"${v:02x}" for v in data[i:i + 16]))


def screen_codes(s):
    return [32 if ch == " " else ord(ch) - 64 if "A" <= ch <= "Z" else ord(ch) for ch in s]


def main():
    bank, fli_col, used, twk_cells, flame_cells = convert_fli()
    frames, sched = make_coin()
    post = make_post_sprites()
    ptr, xh, yy, cc, en, xe, ye = make_track()
    flash = make_flash()
    music, strike = make_music()
    assert strike == FX + F(2.1) and len(post) == len(POST_BLOCKS)

    # after the landing, stars keep out of: the badge, the FLI-bug columns, the credit text
    mask = bytearray(1000)
    for (r, c) in used: mask[r * 40 + c] = 1
    for r in range(FLI_ROWS):
        for c in range(4): mask[r * 40 + c] = 1
    l1x = (320 - 8 * len(LINE1)) // 2
    line1_cells = list(range(LINE1_ROW * 40 + l1x // 8, LINE1_ROW * 40 + (l1x + 8 * len(LINE1) + 7) // 8))
    tx = (320 - 16 * len(TITLE)) // 2
    assert tx % 8 == 0 and l1x % 8 == 4
    title_cells = [r * 40 + c for r in (TITLE_ROW, TITLE_ROW + 1) for c in range(tx // 8, tx // 8 + 2 * len(TITLE))]
    for c in line1_cells + title_cells: mask[c] = 1
    # screen 0, rows 22-24 (hires): light grey for stars, black for the text until it fades in
    for i in range(FLI_ROWS * 40, 1000):
        bank[i] = 0 if i in line1_cells or i in title_cells else 0xF0
    for blk, data in zip(POST_BLOCKS, post):
        a0 = blk * 64
        assert (a0 & 0x3FF) == 0x380 and a0 >= 0x400 or a0 >= 0x3F40, hex(a0)
        bank[a0:a0 + 64] = data
    (BUILD / "fli.bin").write_bytes(bytes(bank[:0x3FC0]))            # $c000-$ffbf

    rng = random.Random(11)
    NST = 32
    stars = [(rng.randrange(64), rng.randrange(0, 170), round((0.35 + rng.random() * 0.9) * 64),
              int(rng.random() > 0.5), rng.randrange(256)) for _ in range(NST)]
    tv = [max(0, round(88 * (1 - (i / 36) ** 2))) if i <= 36 else 0 for i in range(END - OUT + 1)]

    out = ["; generated by tools/make_assets.py -- do not edit", ""]
    consts = dict(APPEAR=APPEAR, FACE=FACE, FX=FX, CREDIT=CREDIT, NAME=NAME, OUT=OUT, END=END, LANDON=LANDON,
                  TRL=TRL, NST=NST, NTWK=len(twk_cells), NFLAME=len(flame_cells), NCOIN=len(sched),
                  FLASHLEN=len(flash), CY=CY, SPLITY=SPLIT_ROW * 8, NLINE1=len(LINE1), NTITLE=len(TITLE),
                  LINE1_BMP=0xE000 + LINE1_ROW * 320 + (l1x // 8) * 8, TITLE_BMP=0xE000 + TITLE_ROW * 320 + tx,
                  NLINE1C=len(line1_cells), NTITLEC=len(title_cells), TVLEN=len(tv))
    for k, v in consts.items():
        out.append(f"{k} = {v}")
    out.append("")
    table("fli_col", fli_col, out)
    table("mask", mask, out)
    blob = bytearray(); offs = []
    for fr in frames:
        offs.append(len(blob)); blob += fr["data"]
    table("coin_data", blob, out)
    out.append("coin_src_lo"); out.append("    !byte " + ",".join(f"<(coin_data+{o})" for o in offs))
    out.append("coin_src_hi"); out.append("    !byte " + ",".join(f">(coin_data+{o})" for o in offs))
    table("coin_n", [fr["n"] for fr in frames], out); table("coin_nx", [fr["nx"] for fr in frames], out)
    table("coin_exp", [0xFF if fr["exp"] else 0 for fr in frames], out)
    table("coin_dx", [fr["dx"] for fr in frames], out); table("coin_dy", [fr["dy"] for fr in frames], out)
    table("coin_xlo", [fr["xbase"] & 0xFF for fr in frames], out); table("coin_xhi", [fr["xbase"] >> 8 for fr in frames], out)
    table("sch_fid", [s[0] for s in sched], out); table("sch_y", [s[1] for s in sched], out); table("sch_back", [s[2] for s in sched], out)
    table("tr_ptr", ptr.flatten(), out); table("tr_x", xh.flatten(), out); table("tr_y", yy.flatten(), out); table("tr_col", cc.flatten(), out)
    table("tr_en", en, out); table("tr_xe", xe, out); table("tr_ye", ye, out)
    table("fl_d011", [r[0] for r in flash], out); table("fl_xs", [r[1] for r in flash], out); table("fl_col", [r[2] for r in flash], out)
    table("s_ang", [s[0] for s in stars], out); table("s_dhi", [s[1] for s in stars], out)
    table("s_spd", [s[2] for s in stars], out); table("s_bri", [s[3] for s in stars], out); table("s_ph", [s[4] for s in stars], out)
    cm, cs, sm, ss = [], [], [], []
    for a in range(64):
        c, s = math.cos(2 * math.pi * a / 64), math.sin(2 * math.pi * a / 64)
        cm.append(round(abs(c) * 127)); cs.append(int(c < 0)); sm.append(round(abs(s) * 127 * 0.75)); ss.append(int(s < 0))
    table("cmag", cm, out); table("csgn", cs, out); table("smag", sm, out); table("ssgn", ss, out)
    table("rtab", [(d * d >> 7) if (d * d >> 7) <= 254 else 255 for d in range(256)], out)
    bl = [(y >> 3) * 320 + (y & 7) for y in range(200)]               # + the bitmap's base
    table("bmplo", [v & 255 for v in bl], out); table("bmphi", [v >> 8 for v in bl], out)
    table("row40lo", [(r * 40) & 255 for r in range(25)], out); table("row40hi", [(r * 40) >> 8 for r in range(25)], out)
    table("twk_lo", [c & 255 for c in twk_cells], out); table("twk_hi", [0xD8 + (c >> 8) for c in twk_cells], out)
    table("twk_ph", [rng.randrange(64) for _ in twk_cells], out)
    table("flm_lo", [c & 255 for c in flame_cells], out); table("flm_hi", [0xD8 + (c >> 8) for c in flame_cells], out)
    table("line1_txt", screen_codes(LINE1), out); table("title_txt", screen_codes(TITLE), out)
    table("line1_cells", [c & 255 for c in line1_cells], out); table("line1_cellh", [0xC0 + (c >> 8) for c in line1_cells], out)
    table("title_cells", [c & 255 for c in title_cells], out); table("title_cellh", [0xC0 + (c >> 8) for c in title_cells], out)
    table("tvh", tv, out)
    # the rest goes above bank 2's screen, sprites and font ($8c00-$9fff: CPU-only RAM)
    out += ["low_end", "    * = $8c00"]
    sq = [n * n // 4 for n in range(512)]
    table("sqlo", [v & 255 for v in sq[:256]], out); table("sqhi", [v >> 8 for v in sq[:256]], out)
    table("sqlo2", [v & 255 for v in sq[256:]], out); table("sqhi2", [v >> 8 for v in sq[256:]], out)
    table("music", music, out)
    warp = []
    for f in range(END + 1):
        t = f / FPS
        wv = 0.4 + 1.6 * min(1, t / 3.3) if t < 3.3 else max(0.15, 2 - (t - 3.3) * 1.2)
        warp.append(round(wv * 32))
    table("warp_lo", warp[:256], out); table("warp_hi", warp[256:] + [warp[-1]] * (256 - len(warp[256:])), out)
    table("rnd", [rng.randrange(256) for _ in range(256)], out)

    (BUILD / "assets.asm").write_text("\n".join(out) + "\n")
    print(f"coin frames {len(frames)}, ring-star cells {len(twk_cells)}, flame cells {len(flame_cells)}; "
          f"bytes coin {len(blob)}, track {4 * 8 * TRL}, music {len(music)}")


if __name__ == "__main__":
    main()
