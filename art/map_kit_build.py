# Builds the Jungle Juice map kit into art/map_kit.blend (collection MapKit).
# Run inside Blender: exec(open(r"...\art\map_kit_build.py").read())
# 1 Blender unit = 1 stud. Path runs along +Y from y=0, centred on x=0, floor top at z=0.
# Each piece is a collection holding one mesh per palette colour (JJ_<Palette name> materials).
import os
exec(open(os.path.join(os.path.dirname(r"C:\Users\rowan\Desktop\Github\Jungle-Juice\art\map_kit_build.py"), "map_kit_lib.py")).read())
PAL['WaterDeep'] = '1F8E9E'
PAL['Shield'] = '5CD6FF'
root = coll('MapKit')


def piece(name, seed):
    c = coll(name, root)
    clear(name)
    return Acc(name, c), random.Random(seed)


def ashlar(A, rng, x0, x1, y0, y1, z0, z1, mats=('StoneLight', 'StoneMoss', 'StoneShadow'), w=(2.5, 4.5)):
    """Block wall filling the box; blocks run along the longer horizontal axis."""
    alongY = (y1 - y0) >= (x1 - x0)
    A.box('StoneShadow', ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0 - 0.3, y1 - y0 - 0.3, z1 - z0 - 0.2))
    z = z0
    k = 0
    while z < z1 - 0.3:
        ch = min(rng.uniform(1.4, 2.2), z1 - z)
        if z1 - (z + ch) < 0.8:
            ch = z1 - z
        s = (y0 if alongY else x0) - (rng.uniform(0.5, 2) if k % 2 else 0)
        e = y1 if alongY else x1
        while s < e - 0.2:
            l = rng.uniform(*w)
            a = max(s, y0 if alongY else x0)
            b = min(s + l, e)
            if b - a > 0.5:
                r = rng.random()
                m = mats[0] if r < 0.55 else (mats[1] if r < 0.85 else mats[2])
                if alongY:
                    A.box(m, ((x0 + x1) / 2, (a + b) / 2, z + ch / 2), (x1 - x0, b - a - 0.15, ch - 0.15), bevel=0.2, jit=0.04, rng=rng)
                else:
                    A.box(m, ((a + b) / 2, (y0 + y1) / 2, z + ch / 2), (b - a - 0.15, y1 - y0, ch - 0.15), bevel=0.2, jit=0.04, rng=rng)
            s += l
        z += ch
        k += 1


def mosscap(A, rng, cx, cy, sx, sy, z):
    A.box('StoneMoss', (cx, cy, z), (sx, sy, 0.8), bevel=0.25)
    A.box('CanopyMid', (cx, cy, z + 0.45), (sx * 0.92, sy * 0.85, 0.25), bevel=0.1, jit=0.05, rng=rng)


def fern(A, rng, x, y, z, s=1.0):
    for i in range(7):
        a = i / 7 * 6.283 + rng.uniform(-.2, .2)
        L = rng.uniform(1.6, 2.6) * s
        A.box(rng.choice(['CanopyBright', 'CanopyMid']), (x + math.cos(a) * L / 2, y + math.sin(a) * L / 2, z + 0.5 * s), (L, 0.5 * s, 0.08), rot=(0, -0.5, a))


def vine(A, rng, x, y, z, L):
    for i in range(int(L / 0.7)):
        A.box('CanopyMid' if i % 2 else 'CanopyBright', (x + rng.uniform(-.08, .08), y, z - i * 0.7), (0.25, 0.25, 0.75), rot=(0, 0, rng.uniform(0, 3)))
        if rng.random() < 0.5:
            A.box('CanopyBright', (x + 0.25, y, z - i * 0.7), (0.5, 0.08, 0.35), rot=(0, 0.5, rng.uniform(-1, 1)))


# ---------- 1 straights ----------
def straight(name, seed, variant, ox, oy):
    A, rng = piece(name, seed)
    if variant == 'A':
        flagstones(A, rng, -HALF + 1.5, HALF - 1.5, 0, 60)
    elif variant == 'B':
        flagstones(A, rng, -HALF + 1.5, HALF - 1.5, 0, 60, mats=('PathTan', 'StoneLight'), moss=0.22)
        for i in range(10):
            x = rng.uniform(-9, 9)
            y = rng.uniform(2, 58)
            for k in range(4):
                A.box('CanopyBright', (x + rng.uniform(-.4, .4), y + rng.uniform(-.4, .4), 0.25), (0.18, 0.18, rng.uniform(0.5, 1.1)), rot=(rng.uniform(-.4, .4), rng.uniform(-.4, .4), 0))
    else:
        A.box('PathTan', (0, 30, -0.5), (W - 3, 60, 1.0), bevel=0.15)
        y = 1.5
        while y < 58:
            for x in ((rng.uniform(-8, -3), rng.uniform(3, 8)) if rng.random() < 0.5 else (rng.uniform(-6, 6),)):
                A.box('StoneLight', (x, y, 0.02), (rng.uniform(2.5, 4), rng.uniform(2, 3), 0.5), rot=(0, 0, rng.uniform(-.4, .4)), bevel=0.2, jit=0.08, rng=rng)
            y += rng.uniform(3, 5)
    kerbs(A, rng, 0, 60)
    foundation(A, rng, 0, 60)
    A.done((ox, oy, 0))


# ---------- 2 corners ----------
def idol(A, rng, cx, cy, z):
    A.box('StoneMoss', (cx, cy, z), (8, 0.7, 8), bevel=0.3)
    A.box('StoneLight', (cx, cy - 0.5, z + 2.6), (7, 0.6, 1.2), bevel=0.2)
    for ex in (-1.8, 1.8):
        A.box('StoneShadow', (cx + ex, cy - 0.45, z + 1.3), (1.9, 0.4, 1.2), bevel=0.15)
        A.box('UiGold', (cx + ex, cy - 0.62, z + 1.3), (0.7, 0.2, 0.5), bevel=0.08)
    A.box('StoneLight', (cx, cy - 0.6, z + 0.1), (1.4, 0.8, 2.4), bevel=0.25)
    A.box('StoneShadow', (cx, cy - 0.45, z - 2.1), (4.6, 0.4, 1.1), bevel=0.15)
    for tx in (-1.5, -0.5, 0.5, 1.5):
        A.box('StoneLight', (cx + tx, cy - 0.62, z - 1.85), (0.6, 0.3, 0.6))
    A.box('StoneLight', (cx, cy - 0.5, z - 3.4), (8.6, 0.6, 0.8), bevel=0.2)


def corner(name, seed, turn, ox, oy):
    A, rng = piece(name, seed)
    flagstones(A, rng, -HALF + 1.5, HALF - 1.5, 0, W)
    # kerbs on the closed side and the back only; the exit side stays open
    y = 0
    while y < W - 0.01:
        l = min(rng.uniform(3.5, 6), W - y)
        if W - (y + l) < 1.2:
            l = W - y
        A.box('PathTan', (-turn * (HALF - 0.75), y + l / 2, 0.05), (1.5, l - 0.12, 0.9), bevel=0.2, jit=0.03, rng=rng)
        y += l
    A.box('PathTan', (turn * 0.75, W - 0.75, 0.05), (W - 1.5, 1.5, 0.9), bevel=0.2)
    foundation(A, rng, 0, W)
    ashlar(A, rng, -HALF - 2, HALF + 2, W, W + 2, -3, 9)
    mosscap(A, rng, 0, W + 1, W + 4.6, 2.6, 9.35)
    idol(A, rng, 0, W - 0.3, 5)
    ashlar(A, rng, -turn * (HALF + 1) - 1, -turn * (HALF + 1) + 1, 0, W, -3, 5)
    mosscap(A, rng, -turn * (HALF + 1), W / 2, 2.6, W + 0.3, 5.35)
    for x in (-HALF - 1.5, HALF + 1.5):
        ashlar(A, rng, x - 1.5, x + 1.5, W - 0.5, W + 2.5, 0, 11, w=(3, 3))
        A.box('StoneLight', (x, W + 1, 11.4), (3.8, 3.8, 0.8), bevel=0.25)
    for i in range(5):
        vine(A, rng, rng.uniform(-10, 10), W - 0.1, 8.8, rng.uniform(2, 5))
    A.done((ox, oy, 0))


# ---------- 3 stairs (down = the same piece turned round) ----------
def stairs(name, seed, ox, oy, rise=8):
    A, rng = piece(name, seed)
    fa, run, fb = 8, 32, 8
    flagstones(A, rng, -HALF + 1.5, HALF - 1.5, 0, fa)
    kerbs(A, rng, 0, fa)
    foundation(A, rng, 0, fa)
    flagstones(A, rng, -HALF + 1.5, HALF - 1.5, fa + run, fa + run + fb, z=rise)
    kerbs(A, rng, fa + run, fa + run + fb, z=rise)
    foundation(A, rng, fa + run, fa + run + fb, z=rise - 1)
    n = 10
    sl = run / n
    for i in range(n):
        y = fa + (i + 0.5) * sl
        top = rise * (i + 1) / n
        A.box('StoneShadow', (0, y, (top - 3) / 2 - 0.3), (W - 0.2, sl, top + 3 - 0.6))
        xs = [-HALF + 0.1]
        x = xs[0]
        while x < HALF - 3:
            x += rng.uniform(5, 9)
            xs.append(min(x, HALF - 0.1))
        xs[-1] = HALF - 0.1
        for a, b in zip(xs, xs[1:]):
            A.box('PathTan' if i % 2 else 'StoneLight', ((a + b) / 2, y + 0.1, top - 0.35), (b - a - 0.15, sl + 0.2, 0.7), bevel=0.18, jit=0.03, rng=rng)
    # stepped parapets: one ashlar block per two steps
    for sx in (-1, 1):
        for i in range(0, n, 2):
            y0 = fa + i * sl
            y1 = y0 + 2 * sl
            top = rise * (i + 2) / n
            ashlar(A, rng, sx * (HALF + 1) - 1, sx * (HALF + 1) + 1, y0, y1, -3, top + 4.2, w=(2.2, 3.4))
            mosscap(A, rng, sx * (HALF + 1), (y0 + y1) / 2, 2.6, 2 * sl + 0.2, top + 4.55)
        A.box('StoneShadow', (sx * (HALF + 0.9), fa + run / 2, -6), (1.8, run, 12))
        for i in range(3):
            vine(A, rng, sx * (HALF + 0.05), fa + rng.uniform(2, run - 2), rise * 0.6, rng.uniform(1.5, 3))
    A.done((ox, oy, 0))


# ---------- 4 gap end (the far side is the same piece turned round) ----------
def gapend(name, seed, ox, oy):
    A, rng = piece(name, seed)
    L = 26
    flagstones(A, rng, -HALF + 1.5, HALF - 1.5, 0, L - 3)
    kerbs(A, rng, 0, L - 2.5)
    foundation(A, rng, 0, L - 2)
    x = -HALF + 0.5
    while x < HALF - 0.5:
        w = rng.uniform(1.8, 3.4)
        d = rng.uniform(1.2, 3.2)
        A.box(rng.choice(['PathSand', 'PathTan', 'StoneLight']), (x + w / 2, L - 3 + d / 2, -0.45 - rng.uniform(0, 0.4)), (w - 0.15, d, 0.9), rot=(rng.uniform(-0.25, 0.05), rng.uniform(-.1, .1), rng.uniform(-.1, .1)), bevel=0.15, jit=0.15, rng=rng)
        x += w
    A.box('StoneShadow', (0, L - 1.4, -1.6), (W - 0.4, 1.2, 3.2), bevel=0.2, jit=0.12, rng=rng)
    for i in range(7):
        A.ico(rng.choice(['StoneShadow', 'StoneMoss']), (rng.uniform(-10, 10), L - 1 + rng.uniform(0, 2), rng.uniform(-14, -3)), rng.uniform(0.4, 1.1), jit=0.25, rng=rng)
    for i in range(4):
        vine(A, rng, rng.uniform(-11, 11), L - 1.9, -1.2, rng.uniform(2, 5))
    A.done((ox, oy, 0))


# ---------- 5 rope bridge ----------
def bridge(name, seed, ox, oy):
    A, rng = piece(name, seed)
    L = 56
    y = 0
    while y < L:
        A.box('WoodPlank', (rng.uniform(-.2, .2), y + 1.2, -0.5 + rng.uniform(-.05, .05)), (W + rng.uniform(-0.6, 0.6), 2.25, 1), rot=(rng.uniform(-.02, .02), rng.uniform(-.02, .02), rng.uniform(-.02, .02)), bevel=0.15, jit=0.04, rng=rng)
        y += 2.5
    for sx in (-1, 1):
        A.box('Rope', (sx * (HALF - 1.5), L / 2, -1.15), (0.35, L, 0.35))
        posts = list(range(0, L + 1, 14))
        for py in posts:
            A.cyl('Trunk', (sx * (HALF + 0.4), py, -1.5), (sx * (HALF + 0.4), py, 4.2), 0.55, n=8, jit=0.06, rng=rng)
            A.ico('Rope', (sx * (HALF + 0.4), py, 3.2), 0.6, sc=(1, 1, 0.6))
        for a, b in zip(posts, posts[1:]):
            k = 8
            for i in range(k):
                t0, t1 = i / k, (i + 1) / k
                z0 = 3.2 - math.sin(t0 * math.pi) * 0.7
                z1 = 3.2 - math.sin(t1 * math.pi) * 0.7
                A.cyl('Rope', (sx * (HALF + 0.4), a + (b - a) * t0, z0), (sx * (HALF + 0.4), a + (b - a) * t1, z1), 0.18, n=6)
            for i in range(1, 4):
                yy = a + (b - a) * i / 4
                zt = 3.2 - math.sin(i / 4 * math.pi) * 0.7
                A.cyl('Rope', (sx * (HALF + 0.4), yy, zt), (sx * (HALF - 0.3), yy, -0.1), 0.08, n=4)
    A.done((ox, oy, 0))


# ---------- 6 foundation block (stacks under any tile) ----------
def foundtile(name, seed, ox, oy):
    A, rng = piece(name, seed)
    foundation(A, rng, 0, 20, z=0, depth=20)
    A.done((ox, oy, 0))


# ---------- 7 hurdle ----------
def hurdle(name, seed, ox, oy):
    A, rng = piece(name, seed)
    A.box('StoneLight', (0, 0, 1.3), (W - 1, 1.6, 2.6), bevel=0.3, jit=0.06, rng=rng)
    A.box('StoneMoss', (0, 0, 2.55), (W - 1.6, 1.75, 0.3), bevel=0.12)
    for x in range(-10, 11, 4):
        A.box('StoneShadow', (x, -0.8, 1.3), (1.6, 0.12, 1.0), bevel=0.05)
    for sx in (-1, 1):
        A.ico('StoneShadow', (sx * (HALF - 0.6), 0.3, 0.5), 1.2, sc=(1, 1, 0.7), jit=0.2, rng=rng)
        A.box('StoneLight', (sx * (HALF - 0.3), 0, 1.4), (1.2, 1.5, 2.4), rot=(0, rng.uniform(-.2, .2), 0), bevel=0.2, jit=0.2, rng=rng)
    for i in range(6):
        A.box('CanopyMid', (rng.uniform(-10, 10), 0, 2.75), (rng.uniform(1, 2.5), 1.3, 0.3), bevel=0.1, jit=0.06, rng=rng)
    A.done((ox, oy, 0))


# ---------- 8 duck log ----------
def ducklog(name, seed, ox, oy):
    A, rng = piece(name, seed)
    L = W + 4
    r = 1.4
    z = 4.7
    A.cyl('Trunk', (-L / 2, 0, z), (L / 2, 0, z), r, n=14, jit=0.08, rng=rng)
    for x in range(-13, 14, 3):
        a = rng.uniform(0, 6.28)
        A.box('Rope', (x, math.cos(a) * r, z + math.sin(a) * r), (rng.uniform(1.5, 2.8), 0.3, 0.3), rot=(a, 0, 0))
    for sx in (-1, 1):
        A.cyl('WoodPlank', (sx * L / 2, 0, z), (sx * (L / 2 + 0.05), 0, z), r * 0.9, n=14)
    for x in range(-12, 13, 1):
        if rng.random() < 0.75:
            vine(A, rng, x + rng.uniform(-.4, .4), rng.uniform(-0.6, 0.6), z - r + 0.3, rng.uniform(1.4, 3.2))
    for i in range(10):
        A.ico('CanopyMid', (rng.uniform(-12, 12), rng.uniform(-0.8, 0.8), z + r * 0.7), rng.uniform(0.6, 1.1), sc=(1.6, 1, 0.6), jit=0.2, rng=rng)
    for i in range(6):
        A.box('CanopyMid', (rng.uniform(-12, 12), 0, z + r - 0.1), (rng.uniform(1, 2.5), 1.6, 0.35), bevel=0.12, jit=0.06, rng=rng)
    A.done((ox, oy, 0))


# ---------- 9 half walls ----------
def halfwall(name, seed, ox, oy, carved=False):
    A, rng = piece(name, seed)
    ashlar(A, rng, -6, 6, -1.5, 1.5, 0, 8, w=(2.5, 4))
    mosscap(A, rng, 0, 0, 12.6, 3.6, 8.4)
    if carved:
        A.box('UiGold', (0, -1.65, 4.2), (2.2, 0.2, 2.2), rot=(0, 0.785, 0), bevel=0.1)
        A.box('StoneShadow', (0, -1.6, 4.2), (3.4, 0.15, 3.4), rot=(0, 0.785, 0), bevel=0.1)
        for i in range(5):
            A.ico('StoneMoss', (rng.uniform(-6, 6), rng.uniform(-2.5, 2.5), 0.4), rng.uniform(0.5, 1.0), jit=0.3, rng=rng)
    for i in range(3):
        vine(A, rng, rng.uniform(-5, 5), -1.7, 8.2, rng.uniform(1.5, 3.5))
    A.done((ox, oy, 0))


# ---------- 10 tar pit (banner text stays a SurfaceGui in Roblox) ----------
def tarpit(name, seed, ox, oy):
    A, rng = piece(name, seed)
    pw, pl = 17, 22
    A.box('Tar', (0, 0, -0.15), (pw, pl, 0.3))
    for i in range(9):
        A.ico('TarBubble', (rng.uniform(-7, 7), rng.uniform(-9, 9), 0.05), rng.uniform(0.5, 1.2), sc=(1, 1, 0.55), sub=2)
    for i in range(4):
        cx, cy = rng.uniform(-6, 6), rng.uniform(-8, 8)
        for k in range(8):
            a = k / 8 * 6.283
            A.box('TarBubble', (cx + math.cos(a) * 1.2, cy + math.sin(a) * 1.2, 0.02), (0.6, 0.2, 0.08), rot=(0, 0, a + 1.57))
    # chunky broken-stone rim, with a red danger stripe inlaid along it
    for (cx, cy, sx, sy) in ((0, -pl / 2 - 0.8, pw + 3.2, 1.6), (0, pl / 2 + 0.8, pw + 3.2, 1.6), (-pw / 2 - 0.8, 0, 1.6, pl), (pw / 2 + 0.8, 0, 1.6, pl)):
        along = sx > sy
        Ln = sx if along else sy
        t = -Ln / 2
        while t < Ln / 2 - 0.3:
            l = min(rng.uniform(1.6, 2.8), Ln / 2 - t)
            c = t + l / 2
            px, py = (cx + c, cy) if along else (cx, cy + c)
            A.box(rng.choice(['StoneShadow', 'StoneMoss', 'StoneShadow']), (px, py, 0.3 + rng.uniform(-.1, .1)), ((l - 0.12) if along else 1.6, 1.6 if along else (l - 0.12), 0.9), rot=(0, 0, rng.uniform(-.08, .08)), bevel=0.25, jit=0.1, rng=rng)
            t += l
        A.box('UiDanger', (cx, cy, 0.8), ((sx - 0.4) if along else 0.45, 0.45 if along else (sy - 0.4), 0.1))
    by = -pl / 2 - 8
    for sx in (-1, 1):
        A.cyl('Trunk', (sx * (HALF - 1), by, -0.5), (sx * (HALF - 1), by, 12.5), 0.4, n=8, jit=0.04, rng=rng)
    A.box('UiDanger', (0, by, 11), (W - 2, 0.4, 3), bevel=0.12)
    A.box('Trunk', (0, by, 12.65), (W - 1, 0.6, 0.5), bevel=0.1)
    A.done((ox, oy, 0))


# ---------- 11 zipline ----------
def zippost(name, seed, ox, oy):
    A, rng = piece(name, seed)
    flagstones(A, rng, -HALF + 1.5, HALF - 1.5, -7, 7)
    kerbs(A, rng, -7, 7)
    foundation(A, rng, -7, 7)
    for sx in (-1, 1):
        A.cyl('Trunk', (sx * (HALF - 0.5), 0, -0.5), (sx * (HALF - 0.5), 0, 12), 1.0, n=10, jit=0.08, rng=rng)
        A.cyl('Trunk', (sx * (HALF - 0.5), 0, 7), (sx * (HALF - 4), 0, 10.6), 0.45, n=8)
        A.ico('StoneShadow', (sx * (HALF - 0.5), 0, 0.2), 1.6, sc=(1, 1, 0.5), jit=0.2, rng=rng)
    A.box('Trunk', (0, 0, 10.9), (W, 1.2, 1.2), bevel=0.2, jit=0.05, rng=rng)
    for x in (-9, -3, 3, 9):
        A.box('Rope', (x, 0, 10.1), (0.8, 1.4, 0.6), bevel=0.1)
        A.cyl('UiGold', (x, -0.75, 10.1), (x, 0.75, 10.1), 0.35, n=10)
    A.done((ox, oy, 0))


def zipcut(name, seed, ox, oy):
    A, rng = piece(name, seed)
    A.cyl('Rope', (0, -4, 0), (0, 0, 0), 0.22, n=6)
    for i in range(5):
        a = rng.uniform(0, 6.28)
        A.cyl('Rope', (0, 0, 0), (math.cos(a) * 0.5, 0.3, -rng.uniform(0.8, 2.8)), 0.06, n=4)
    A.box('UiDanger', (0, 0.1, -0.6), (1.4, 0.2, 1.4), rot=(0, 0.3, 0), bevel=0.05)
    A.cyl('Rope', (-0.3, 0, -0.1), (0.3, 0, -0.1), 0.32, n=8)
    A.done((ox, oy, 0))


# ---------- 12 edge wall and riverbank ----------
def edgewall(name, seed, ox, oy):
    A, rng = piece(name, seed)
    ashlar(A, rng, -1, 1, 0, 20, -3, 5)
    mosscap(A, rng, 0, 10, 2.6, 20.3, 5.35)
    ashlar(A, rng, -1.5, 1.5, -1.5, 1.5, 0, 9, w=(3, 3))
    A.box('StoneLight', (0, 0, 9.4), (3.8, 3.8, 0.8), bevel=0.25)
    A.box('StoneMoss', (0, 0, 9.95), (3.0, 3.0, 0.4), bevel=0.15)
    for i in range(4):
        vine(A, rng, 1.1, rng.uniform(2, 18), 5.6, rng.uniform(1.5, 4))
    A.done((ox, oy, 0))


def riverbank(name, seed, ox, oy):
    A, rng = piece(name, seed)
    verts = [(0, 0, -1), (34, 0, -30), (34, 20, -30), (0, 20, -1), (0, 0, -30), (0, 20, -30)]
    A.raw('Cliff', verts, [(0, 3, 2, 1), (0, 1, 4), (3, 5, 2), (4, 1, 2, 5), (0, 4, 5, 3)])
    for i in range(26):
        t = rng.uniform(0.05, 0.95)
        y = rng.uniform(1, 19)
        x = t * 34
        z = -1 - t * 29
        if rng.random() < 0.45:
            A.ico('StoneShadow' if rng.random() < 0.5 else 'StoneMoss', (x, y, z + 0.3), rng.uniform(1, 2.4), sc=(1, 1, 0.6), jit=0.18, rng=rng)
        else:
            fern(A, rng, x, y, z + 0.2, rng.uniform(0.8, 1.4))
    A.box('Water', (17, 10, -30.2), (34, 20, 0.4))
    A.done((ox, oy, 0))


# ---------- 16 gem (brilliant cut, matches the HUD gem icon) ----------
def gem(name, ox, oy, R=1.4):
    A, rng = piece(name, 0)
    n = 8
    tz, bz, tr = 0.62 * R, -1.05 * R, 0.55 * R
    tv = [(math.cos(i / n * 6.283 + 0.39) * tr, math.sin(i / n * 6.283 + 0.39) * tr, tz) for i in range(n)]
    gv = [(math.cos(i / (2 * n) * 6.283) * R, math.sin(i / (2 * n) * 6.283) * R, 0) for i in range(2 * n)]
    A.raw('GemGlint', tv, [list(range(n))])
    for i in range(n):
        t0, t1 = tv[i], tv[(i + 1) % n]
        g0, g1, g2 = gv[(2 * i + 1) % (2 * n)], gv[(2 * i + 2) % (2 * n)], gv[(2 * i + 3) % (2 * n)]
        A.raw('Gem', [t0, g0, g1, t1], [(0, 1, 2, 3)])
        A.raw('Shield', [t1, g1, g2], [(0, 1, 2)])
    for i in range(2 * n):
        A.raw('Water' if i % 2 else 'WaterDeep', [gv[i], (0, 0, bz), gv[(i + 1) % (2 * n)]], [(0, 1, 2)])
    A.done((ox, oy, 0))


straight('K01_StraightA', 1, 'A', 0, 0)
straight('K01_StraightB', 2, 'B', 40, 0)
straight('K01_StraightC', 3, 'C', 80, 0)
corner('K02_CornerRight', 4, 1, 0, 100)
corner('K02_CornerLeft', 5, -1, 40, 100)
stairs('K03_StairsUp', 6, 80, 100)
gapend('K04_GapEnd', 7, 120, 100)
bridge('K05_Bridge', 8, 0, 180)
foundtile('K06_Foundation', 9, 40, 180)
hurdle('K07_Hurdle', 10, 80, 180)
ducklog('K08_DuckLog', 11, 120, 180)
halfwall('K09_HalfWallA', 12, 0, 260)
halfwall('K09_HalfWallB', 13, 20, 260, True)
tarpit('K10_TarPit', 14, 60, 270)
zippost('K11_ZipPost', 15, 100, 260)
zipcut('K11_ZipCut', 16, 125, 260)
edgewall('K12_EdgeWall', 17, 0, 320)
riverbank('K12_RiverBank', 18, 20, 320)
gem('K16_Gem', 80, 330)


# Export: one FBX per piece, pivot at the path entry, into the folder Roblox imports come from.
def export_kit(out=r"C:\Users\rowan\Desktop\Roblox Assets\Jungle Juice\Map Kit"):
    os.makedirs(out, exist_ok=True)
    for c in bpy.data.collections['MapKit'].children:
        objs = list(c.objects)
        off = objs[0].location.copy()
        for o in objs:
            o.location -= off
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.fbx(filepath=os.path.join(out, c.name + ".fbx"), use_selection=True, object_types={'MESH'}, apply_unit_scale=True, global_scale=0.01, axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE', bake_space_transform=True)
        for o in objs:
            o.location += off
