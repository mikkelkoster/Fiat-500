# Unmix the light studio backdrop from the car's soft edges, then place the car on the app's
# 1200×640 canvas exactly where the original black render sat.
import sys, numpy as np
from PIL import Image, ImageFilter
code = sys.argv[1]
src = np.asarray(Image.open(f"{code}.jpg").convert("RGB")).astype(np.float32)
lift = np.asarray(Image.open(f"lift-{code}.png").convert("RGBA")).astype(np.float32)
a = lift[..., 3] / 255.0
# Local backdrop colour: the photo where there's no car, spread inwards by a normalised blur.
bgmask = (a < 0.02).astype(np.float32)
def box(x, r, axis):
    c = np.cumsum(np.pad(x, [(r + 1, r) if i == axis else (0, 0) for i in range(2)], mode="edge"), axis=axis)
    hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis); lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
    return (hi - lo) / (2 * r + 1)
def blur(x, r):
    for _ in range(3): x = box(box(x, r, 0), r, 1)
    return x
den = blur(bgmask, 25) + 1e-4
B = np.dstack([blur(src[..., i] * bgmask, 25) / den for i in range(3)])
edge = (a > 0.02) & (a < 0.98)
C = src.copy()
C[edge] = np.clip((src[edge] - (1 - a[edge, None]) * B[edge]) / a[edge, None], 0, 255)
# Pull alpha in a touch at the fringe so no backdrop glow survives.
a2 = np.clip((a - 0.06) / 0.94, 0, 1)
out = Image.fromarray(np.dstack([C, a2 * 255]).astype(np.uint8), "RGBA")
s = 593 / (1720 - 676)
small = out.resize((round(out.width * s), round(out.height * s)), Image.LANCZOS)
canvas = Image.new("RGBA", (1200, 640), (0, 0, 0, 0))
canvas.alpha_composite(small, (round(303 - 676 * s), round(180 - 386 * s)))
canvas.save(f"car-fiat-500e-{code}.png", optimize=True)
print(code, canvas.getchannel("A").getbbox())
