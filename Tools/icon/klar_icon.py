# The Klar app icon: the app's battery gauge, as true to it as an icon allows. Same build as
# ArcGauge: a dark track, the green arc with a wide soft glow and a tight halo, a white knob twice
# the line's width at the end of the fill. Only the line is thicker than the app's, so it holds
# at 40 px.
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, math

GREEN = (74, 222, 128); TRACK = (63, 63, 70); WHITE = (244, 244, 245)

def pts(cx, cy, r, a0, a1, n=1400):
    return [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in np.linspace(a0, a1, n)]

def line(size, p, width, value=255):
    m = Image.new("L", (size, size), 0); d = ImageDraw.Draw(m); r = width / 2
    for x, y in p: d.ellipse((x - r, y - r, x + r, y + r), fill=value)
    return m

def over(img, color, mask): return Image.composite(Image.new("RGB", img.size, color), img, mask)

def icon(fill=0.8, radius=330, line_w=56, knob=1.9, glow=1.0, size=1024):
    S = 3; W = size * S
    grad = np.linspace(1, 0, W)[:, None] ** 2
    base = np.array([9, 9, 11]); top = np.array([20, 20, 24])
    img = Image.fromarray((base + (top - base) * grad[..., None] * np.ones((1, W, 1))).astype(np.uint8))
    # The arc's opening sits at the bottom; nudge it down so the shape sits optically centred.
    cx, cy, r, w = W / 2, W / 2 + radius * 0.12 * S, radius * S, line_w * S
    a0, a1 = 135, 135 + 270 * fill
    # Track, as the app draws it: the outline grey at 70 %.
    img = over(img, TRACK, line(W, pts(cx, cy, r, 135, 405), w).point(lambda v: int(v * 0.7)))
    lit = pts(cx, cy, r, a0, a1)
    # Wide soft glow (the app's blurred 18 pt copy at 75 %), then the tight halo, then the line.
    wide = line(W, lit, w * 2.25).filter(ImageFilter.GaussianBlur(w * 1.6)).point(lambda v: int(v * 0.75 * glow))
    img = over(img, GREEN, wide)
    halo = line(W, lit, w).filter(ImageFilter.GaussianBlur(w * 0.6)).point(lambda v: int(v * 0.9 * glow))
    img = over(img, GREEN, halo)
    img = over(img, GREEN, line(W, lit, w))
    # Knob: white, a green glow round it and a hint of shadow, like ArcKnob.
    kx, ky = cx + r * math.cos(math.radians(a1)), cy + r * math.sin(math.radians(a1))
    kr = w * knob / 2
    kg = Image.new("L", (W, W), 0); ImageDraw.Draw(kg).ellipse((kx - kr * 1.5, ky - kr * 1.5, kx + kr * 1.5, ky + kr * 1.5), fill=200)
    img = over(img, GREEN, kg.filter(ImageFilter.GaussianBlur(kr * 0.6)).point(lambda v: int(v * 0.8)))
    ImageDraw.Draw(img).ellipse((kx - kr, ky - kr, kx + kr, ky + kr), fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    # The chosen one (E): a slightly thicker line and more glow than the app's, for presence.
    icon(radius=320, line_w=66, knob=1.8, glow=1.15).save("icon.png")
