# Cleaner edges for the car pictures (v3: smoothed Vision outline, car-coloured edge).
# Vision's subject mask is computed at a lower resolution, so its edge steps and leaves studio grey
# in the soft pixels. Here the edge is re-derived from the photo: in a narrow band around the mask
# edge, alpha comes from how much darker a pixel is than the backdrop next to it, relative to the
# car's own colour next to it (when the two differ enough to tell). Edge pixels take the car's
# colour, and the picture is shrunk premultiplied so no halo appears.
import sys, numpy as np
from PIL import Image
code = sys.argv[1]
src = np.asarray(Image.open(f"{code}.jpg").convert("RGB")).astype(np.float32)
a0 = np.asarray(Image.open(f"lift-{code}.png").convert("RGBA")).astype(np.float32)[..., 3] / 255.0

def box(x, r, axis):
    c = np.cumsum(np.pad(x, [(r + 1, r) if i == axis else (0, 0) for i in range(x.ndim)], mode="edge"), axis=axis)
    hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis); lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
    return (hi - lo) / (2 * r + 1)
def blur(x, r, n=3):
    for _ in range(n): x = box(box(x, r, 0), r, 1)
    return x
def spread(img, mask, r):
    """Colour of `img` where `mask` is set, carried outwards: a normalised blur."""
    den = blur(mask, r)
    return np.dstack([blur(img[..., i] * mask, r) for i in range(3)]) / np.maximum(den, 1e-4)[..., None], den

hard = (a0 > 0.5).astype(np.float32)
soft = blur(hard, 3)
band = (soft > 0.002) & (soft < 0.998)
inside = (blur(hard, 4) > 0.999).astype(np.float32)          # well inside the car
outside = (blur(hard, 4) < 0.001).astype(np.float32)         # well clear of it

F, fden = spread(src, inside, 6)
F2, _ = spread(src, inside, 18)
F = np.where((fden < 0.02)[..., None], F2, F)
B, _ = spread(src, outside, 25)

# Vision's outline with the steps smoothed off, pulled in a touch so no studio grey is left.
smooth = blur(hard, 2)
alpha = np.clip((smooth - 0.4) / 0.45, 0, 1)
alpha = alpha * alpha * (3 - 2 * alpha)                      # smoothstep: soft, not blurry
# The backdrop is lighter than the paint, so whatever it left in an edge pixel made it lighter:
# take the darker of the pixel and the car's colour beside it. (A white car is as light as the
# backdrop; its edge pixels stay as they are.)
dark_car = float(np.mean(F.mean(2)[band])) < float(np.mean(B.mean(2)[band])) - 35
rgb = np.where(band[..., None], np.minimum(src, F) if dark_car else src, src)
# Shrink premultiplied so transparent pixels can't bleed colour into the edge.
s = 593 / (1720 - 676)
W, H = round(src.shape[1] * s), round(src.shape[0] * s)
def shrink(ch): return np.asarray(Image.fromarray(ch.astype(np.float32)).resize((W, H), Image.LANCZOS))
pa = shrink(alpha)
prgb = np.dstack([shrink(rgb[..., i] * alpha) for i in range(3)])
out_rgb = np.clip(prgb / np.maximum(pa, 1e-4)[..., None], 0, 255)
out_a = np.clip(pa, 0, 1)
small = Image.fromarray(np.dstack([out_rgb, out_a * 255]).astype(np.uint8))
canvas = Image.new("RGBA", (1200, 640), (0, 0, 0, 0))
canvas.alpha_composite(small, (round(303 - 676 * s), round(180 - 386 * s)))
canvas.save(f"v3-car-fiat-500e-{code}.png", optimize=True)
print(code, "band px", int(band.sum()), "dark car" if dark_car else "light car")
