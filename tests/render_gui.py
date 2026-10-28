"""Draw an approximate screenshot from a mock GUI dump (tests/lua/roblox_mock.lua M.dump).

Usage: python tests/render_gui.py dump.txt out.png
Only a layout sanity check: fonts and emoji differ from Roblox.
"""
import sys, math
from PIL import Image, ImageDraw, ImageFont

def main(src, out):
    W, H = 1920, 1080
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    draw = ImageDraw.Draw(canvas, "RGBA")
    rows = []
    for line in open(src, encoding="utf-8"):
        p = line.rstrip("\n").split("|")
        if len(p) < 17:
            continue
        rows.append(p)
    rows.sort(key=lambda p: int(p[9]))
    mapimg = None
    try:
        mapimg = Image.open(src + ".ppm").convert("RGB")
    except FileNotFoundError:
        pass
    fonts = {}
    def font(size):
        size = max(6, min(60, int(float(size))))
        if size not in fonts:
            try:
                fonts[size] = ImageFont.truetype("DejaVuSans-Bold.ttf", size)
            except OSError:
                fonts[size] = ImageFont.load_default()
        return fonts[size]
    for p in rows:
        cls, x, y, w, h = p[0], *map(float, p[1:5])
        r, g, b, t = int(p[5]), int(p[6]), int(p[7]), float(p[8])
        text, tr, tg, tb, ts, territory, rot = p[10], int(p[11]), int(p[12]), int(p[13]), p[14], p[15] == "1", float(p[16])
        if territory and mapimg:
            if w > 0 and h > 0:
                scaled = mapimg.resize((max(1, int(w)), max(1, int(h))), Image.NEAREST)
                canvas.paste(scaled, (int(x), int(y)))
            continue
        alpha = int(255 * (1 - t))
        if alpha > 0 and w > 0 and h > 0:
            if rot:
                cx, cy = x + w / 2, y + h / 2
                a = math.radians(rot)
                dx, dy = math.cos(a) * w / 2, math.sin(a) * w / 2
                draw.line([(cx - dx, cy - dy), (cx + dx, cy + dy)], fill=(r, g, b, alpha), width=max(1, int(h)))
            else:
                draw.rectangle([x, y, x + w, y + h], fill=(r, g, b, alpha))
        if text.strip() and cls in ("TextLabel", "TextButton"):
            f = font(ts)
            tw = draw.textlength(text, font=f)
            draw.text((x + (w - tw) / 2 if w > tw else x, y + (h - float(ts)) / 2), text, fill=(tr, tg, tb, 255), font=f)
    canvas.save(out)
    print(out)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
