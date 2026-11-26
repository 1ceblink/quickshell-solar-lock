#!/usr/bin/env python3
"""Download the planet textures and derive the extra maps the scene needs.

Textures are from Solar System Scope (https://www.solarsystemscope.com/textures/), licensed
CC BY 4.0, so they are fetched at install time instead of being redistributed in this repo.
Needs only Python 3 and Pillow (python-pillow).
"""
import hashlib
import math
import os
import sys
import urllib.request

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Pillow is required: install python-pillow (Arch) or `pip install pillow`.")

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")
BASE = "https://www.solarsystemscope.com/textures/download/"
FILES = [
    "2k_sun.jpg", "2k_mercury.jpg", "2k_venus_atmosphere.jpg", "2k_earth_daymap.jpg",
    "2k_earth_clouds.jpg", "2k_moon.jpg", "2k_mars.jpg", "2k_jupiter.jpg", "2k_saturn.jpg",
    "2k_uranus.jpg", "2k_neptune.jpg", "2k_saturn_ring_alpha.png", "2k_stars.jpg",
    "2k_earth_nightmap.jpg",
]


SHA256 = {
    "2k_earth_clouds.jpg": "fffd7f68d41b37274822150e54a6ef605af1d3ec35624d9f628c3b896bfa42ed",
    "2k_earth_nightmap.jpg": "c16fd1bc096ab91a5c5265c6ff9847c43f489f2e2ee790ccdbcbd03251cf3a5a",
    "2k_earth_daymap.jpg": "767ee1dc6eb3802699bfccf6f264880f8acd0b80de3191cd24984fe279b07b7c",
    "2k_jupiter.jpg": "b0f04d005350252636b0e3396fc592548cbd9e9126b269d32d5c6abd4b0e4f2b",
    "2k_mars.jpg": "2d187f3e77a98eaa8cea5f4cc722f633c122ef170b9e94ace6b5fb6cbc3f8e01",
    "2k_mercury.jpg": "5a5c80607f643496bac9a631e71957def35ed788895f18b678ac849c2b38e48a",
    "2k_moon.jpg": "2764ba6535ea0481a062846ee033cc7a909dae05b31a8fd13f3e98f3a7fd92bd",
    "2k_neptune.jpg": "cb42ea82709741d28b0af44d8b283cbc6dbd0c521a7f0e1e1e010ade00977df6",
    "2k_saturn.jpg": "54a900ca9bf7ab62e70f862852759abdf342e6d6436a95a2fe9ebdb6bcd3bbac",
    "2k_saturn_ring_alpha.png": "4b0644b2f3ef259fd0bfaedd9dc52f9e7d9738f65f50363e8c4dd19f650d7334",
    "2k_stars.jpg": "d19468ddf451851dfa74bfd85637f43533200631319ffa90cc822d4049eee604",
    "2k_sun.jpg": "ff0f076ba65e03b5ab518451bc96699325be38e3ccbdd5869ee1c00f3a0c8816",
    "2k_uranus.jpg": "d15239d46f82d3ea13d2b260b5b29b2a382f42f2916dae0694d0387b1204a09d",
    "2k_venus_atmosphere.jpg": "225012ad4911730605c4e189ca2a3bf674fce50cc48aab4102b936b47d6991ac",
}


def download(name):
    dest = os.path.join(OUT, name)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print("have ", name)
        return
    req = urllib.request.Request(BASE + name, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    if hashlib.sha256(data).hexdigest() != SHA256[name]:
        sys.exit(f"{name}: checksum mismatch, refusing to use it (the upstream file changed, or the download was tampered with)")
    with open(dest, "wb") as f:
        f.write(data)
    print("got  ", name)


def ring_disc():
    """Turn the radial ring strip into a ring-shaped RGBA disc."""
    strip = Image.open(os.path.join(OUT, "2k_saturn_ring_alpha.png")).convert("RGBA")
    sw, sh = strip.size
    row = [strip.getpixel((x, sh // 2)) for x in range(sw)]
    n, inner = 1024, 0.49
    disc = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = disc.load()
    for y in range(n):
        for x in range(n):
            r = math.hypot(x + 0.5 - n / 2, y + 0.5 - n / 2) / (n / 2)
            if inner <= r <= 1.0:
                px[x, y] = row[min(sw - 1, int((r - inner) / (1 - inner) * (sw - 1)))]
    disc.save(os.path.join(OUT, "saturn_ring.png"))
    print("made  saturn_ring.png")


def normal_map(src, dst, blur=1.2, k=2.2):
    """Bump relief derived from surface brightness (Sobel)."""
    h = Image.open(os.path.join(OUT, src)).convert("L").filter(ImageFilter.GaussianBlur(blur))
    gx = h.filter(ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], scale=1, offset=128))
    gy = h.filter(ImageFilter.Kernel((3, 3), [1, 2, 1, 0, 0, 0, -1, -2, -1], scale=1, offset=128))
    boost = lambda v: max(0, min(255, int(128 + (v - 128) * k)))
    Image.merge("RGB", (gx.point(boost), gy.point(boost), Image.new("L", h.size, 215))).save(
        os.path.join(OUT, dst))
    print("made  " + dst)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in FILES:
        download(f)
    ring_disc()
    normal_map("2k_mercury.jpg", "mercury_n.png")
    normal_map("2k_moon.jpg", "moon_n.png")
    normal_map("2k_mars.jpg", "mars_n.png", blur=1.6, k=1.6)
    print("done")
