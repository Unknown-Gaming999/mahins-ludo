import os
import sys
from PIL import Image, ImageDraw

res = sys.argv[1]
COLORS = [(229, 57, 53), (67, 160, 71), (30, 136, 229), (253, 216, 53)]


def draw_logo(size, with_bg):
    s = 1024
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if with_bg:
        for y in range(s):
            r = int(43 + (91 - 43) * y / s)
            g = int(26 + (43 - 26) * y / s)
            b = int(110 + (181 - 110) * y / s)
            d.line([(0, y), (s, y)], fill=(r, g, b, 255))
    m, gap = 190, 24
    half = (s - 2 * m - gap) // 2
    pos = [(m, m), (m + half + gap, m), (m, m + half + gap), (m + half + gap, m + half + gap)]
    for (x, y), c in zip(pos, COLORS):
        d.rounded_rectangle([x, y, x + half, y + half], radius=80, fill=c + (255,),
                            outline=(255, 255, 255, 255), width=10)
    cx = cy = s // 2
    d.rounded_rectangle([cx - 150, cy - 150, cx + 150, cy + 150], radius=60,
                        fill=(255, 255, 255, 255), outline=(40, 40, 60, 255), width=8)
    for dx, dy in [(-80, -80), (80, -80), (0, 0), (-80, 80), (80, 80)]:
        d.ellipse([cx + dx - 28, cy + dy - 28, cx + dx + 28, cy + dy + 28], fill=(40, 40, 60, 255))
    return im.resize((size, size), Image.LANCZOS)


for folder, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    p = os.path.join(res, "mipmap-" + folder)
    os.makedirs(p, exist_ok=True)
    draw_logo(px, True).save(os.path.join(p, "ic_launcher.png"))

dp = os.path.join(res, "drawable")
os.makedirs(dp, exist_ok=True)
draw_logo(320, False).save(os.path.join(dp, "splash_logo.png"))
print("Icons generated")
