"""Fundus-Icon: ein Sortierkasten von oben.

Drei Durchgaenge, und die Korrekturen sagen, worauf es ankam:

1. Rechtecke in Zellen lesen sich als Wireframe. Ein Kasten unterscheidet sich
   davon dadurch, dass die Aussenwand dick ist und die Stege duenn — ein Diagramm
   hat ueberall dieselbe Strichstaerke.
2. Was drin liegt, braucht Form. Kein Dashboard hat runde Kacheln; drei Kreise
   sagen "Schrauben" in einer Weise, die ein gefuelltes Rechteck nie sagt.
3. Vier Faecher statt fuenf, und nur zwei davon belegt — ueber Eck. Bei 60 px
   zerfaellt alles Kleinteilige, und ein leeres Fach ist Luft, kein Mangel.
"""
import pathlib

from PIL import Image, ImageDraw

S, F = 1024, 4
def s(v): return int(round(v * F))

NAVY  = (0x37, 0x45, 0x59)
LIGHT = (0xFD, 0xFD, 0xFE)
SHADE = (0xF1, 0xF3, 0xF7)

X0, Y0, X1, Y1 = 150, 210, 874, 814
RADIUS = 64
FRAME  = 40
WALL   = 18

IX0, IY0 = X0 + FRAME / 2, Y0 + FRAME / 2
IX1, IY1 = X1 - FRAME / 2, Y1 - FRAME / 2
W, H = IX1 - IX0, IY1 - IY0

VS = IX0 + 0.44 * W          # senkrechter Steg
LS = IY0 + 0.45 * H          # links quer, oben das kleinere Fach
RS = IY0 + 0.62 * H          # rechts quer, oben das groessere — ergibt ein Windrad


def ground(dark):
    if dark:
        return Image.new("RGB", (s(S), s(S)), (0, 0, 0))
    img = Image.new("RGB", (s(S), s(S)))
    px, n = img.load(), s(S)
    for y in range(n):
        for x in range(0, n, 8):
            t = (x + y) / (2 * n)
            c = tuple(int(LIGHT[i] + (SHADE[i] - LIGHT[i]) * t) for i in range(3))
            for dx in range(8):
                if x + dx < n: px[x + dx, y] = c
    return img


def draw(dark=False):
    img = ground(dark)
    d = ImageDraw.Draw(img)
    ink = (255, 255, 255) if dark else NAVY

    d.rounded_rectangle([s(X0), s(Y0), s(X1), s(Y1)],
                        radius=s(RADIUS), outline=ink, width=s(FRAME))

    h = WALL / 2
    d.rectangle([s(VS - h), s(IY0), s(VS + h), s(IY1)], fill=ink)
    d.rectangle([s(IX0), s(LS - h), s(VS), s(LS + h)], fill=ink)
    d.rectangle([s(VS), s(RS - h), s(IX1), s(RS + h)], fill=ink)

    # Oben links: Schuettgut, versetzt statt im Raster.
    cx, cy, r = (IX0 + VS) / 2, (IY0 + LS) / 2, 42
    for dx, dy in ((-60, -30), (52, -4), (-14, 54)):
        d.ellipse([s(cx + dx - r), s(cy + dy - r), s(cx + dx + r), s(cy + dy + r)], fill=ink)

    # Unten rechts, ueber Eck dazu: ein laengliches Teil, quer im Fach.
    bx0, bx1 = VS + 62, IX1 - 62
    by, bh = (RS + IY1) / 2, 29
    d.rounded_rectangle([s(bx0), s(by - bh), s(bx1), s(by + bh)], radius=s(bh), fill=ink)

    return img.resize((S, S), Image.LANCZOS)


OUT = pathlib.Path(__file__).resolve().parent.parent \
    / "Fundus/Resources/Assets.xcassets/AppIcon.appiconset"

for name, dark in (("AppIcon1024", False), ("AppIcon1024-dark", True),
                   ("AppIcon1024-tinted", True)):
    draw(dark).save(OUT / f"{name}.png")
    print("geschrieben:", name + ".png")
