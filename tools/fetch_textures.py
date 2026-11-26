#!/usr/bin/env python3
"""Download the planet textures and derive the extra maps the scene needs.

Textures are from Solar System Scope (https://www.solarsystemscope.com/textures/), licensed
CC BY 4.0, so they are fetched at install time instead of being redistributed in this repo.
Needs only Python 3 and Pillow (python-pillow).
"""
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
    "2k_uranus.jpg", "2k_neptune.jpg", "2k_saturn_ring_alpha.png",
]


def download(name):
    dest = os.path.join(OUT, name)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print("have ", name)
        return
    req = urllib.request.Request(BASE + name, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
        f.write(r.read())
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
