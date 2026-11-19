#!/usr/bin/env python3
"""Builds every Glow logo SVG, including the concept board, from one set of geometry.

Usage: python3 design/logo/generate.py      (writes the SVGs in design/logo)
Then:  swift design/logo/render.swift        (PNGs in design/logo/png, drawn by AppKit from those SVGs)

The mark: a hollow four-point spark, one closed 24-unit line with round joins and an open centre. It is
drawn on the 256 grid Hum, Pulse and Tuck share, centred on their optical line (y 126), and placed in the
app icon with the same transform they use. Change the geometry here, never in a single SVG.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent

# ---------------------------------------------------------------- palette
APRICOT = "#DE8B6D"        # Apricot Terracotta, the intended brand colour (white on it: 2.62:1)
APRICOT_TUNED = "#CF7E60"  # proposal: the same hue and chroma at Tuck Blue's lightness (white on it: 3.09:1)
BRAND = APRICOT            # set to APRICOT_TUNED to adopt the proposal everywhere
INK = "#21170C"
WHITE = "#FFFFFF"
PAPER, CARD, MUTED, RULE = "#F3F1EC", "#FFFFFF", "#6B6154", "#D8D2C8"
SIBLINGS = {"Hum": "#B81D45", "Pulse": "#5B4FE6", "Tuck": "#7299C5"}

# ---------------------------------------------------------------- spark geometry (256 grid)
# A spark is one cubic per side, mirrored on both axes. Each is given by its top-right side: the top tip, the
# handle leaving it, the handle arriving at the right tip, and the right tip, in absolute grid units.
Side = tuple[tuple[float, float], tuple[float, float], tuple[float, float], tuple[float, float]]

# The recommended master: the previous drawing scaled to 88 % about its centre and lifted 2 units, so its
# ink spans x 28-228 (the family's line span) and centres on y 126. Uniform scale keeps every tip angle
# (17° top, 20° side) and the depth of the waist exactly as they were.
MASTER: Side = ((128, 48), (137, 77), (168, 108), (216, 126))
# Small cut, unchanged: stroke 32, centred on y 128 so its tips and 2 px line land on whole pixels at 16 px.
SMALL: Side = ((128, 48), (140, 78), (170, 108), (224, 128))
# Options shown on the board.
PREVIOUS: Side = ((128, 40), (138, 72), (174, 108), (228, 128))   # as shipped before this pass
UPRIGHT: Side = ((128, 38), (146, 86), (177, 117), (206, 126))    # option B: the master turned on its diagonal
SOFT: Side = ((128, 48), (140, 75), (171, 104), (216, 126))       # option C: tip handles opened 7° and 6°

STROKE, SMALL_STROKE = 24, 32
ICON = "translate(512 496) scale(2.48) translate(-128 {cy})"      # Hum's, Pulse's and Tuck's icon transform


def f(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def spark(side: Side) -> str:
    (tx, ty), (ax, ay), (bx, by), (rx, ry) = side
    cx, cy = tx, ry

    def p(x: float, y: float) -> str:
        return f"{f(x)} {f(y)}"

    def mirror(x: float, y: float, sx: int, sy: int) -> str:
        return p(cx + sx * (x - cx), cy + sy * (y - cy))

    return (f"M{p(tx, ty)} C{p(ax, ay)} {p(bx, by)} {p(rx, ry)} "
            f"C{mirror(bx, by, 1, -1)} {mirror(ax, ay, 1, -1)} {mirror(tx, ty, 1, -1)} "
            f"C{mirror(ax, ay, -1, -1)} {mirror(bx, by, -1, -1)} {mirror(rx, ry, -1, 1)} "
            f"C{mirror(bx, by, -1, 1)} {mirror(ax, ay, -1, 1)} {p(tx, ty)} Z")


def line(d: str, colour: str, width: float, extra: str = "") -> str:
    return (f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{f(width)}" '
            f'stroke-linecap="round" stroke-linejoin="round"{extra}/>')


def svg(body: str, title: str, desc: str, w: int = 256, h: int = 256, comment: str = "") -> str:
    note = f"\n  <!-- {comment} -->" if comment else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'role="img" aria-labelledby="title desc">\n  <title id="title">{title}</title>\n'
            f'  <desc id="desc">{desc}</desc>{note}\n  {body}\n</svg>\n')


def write(name: str, content: str) -> None:
    (ROOT / name).write_text(content)


def app_icon(colour: str = BRAND, small: bool = False) -> str:
    side, width, cy = (SMALL, SMALL_STROKE, 128) if small else (MASTER, STROKE, 126)
    return (f'<rect x="100" y="100" width="824" height="824" rx="186" fill="{colour}"/>\n'
            f'  <g transform="{ICON.format(cy=-cy)}">{line(spark(side), WHITE, width)}</g>')


# ---------------------------------------------------------------- masters
MASTER_NOTE = ("Aperture Spark. 256 grid: tips (128 48), (216 126), (128 204), (40 126); ink x 28-228, centred on "
               "y 126, the family's optical line. Stroke 24, round joins. The open interior is intentional.")
write("glow-symbol-orange.svg", svg(line(spark(MASTER), BRAND, STROKE), "Glow symbol",
                                    "A hollow four-point spark drawn as one rounded Apricot Terracotta line.",
                                    comment=MASTER_NOTE))
write("glow-symbol-black.svg", svg(line(spark(MASTER), INK, STROKE), "Glow symbol, one colour",
                                   "A hollow four-point spark drawn as one rounded Ink line.", comment=MASTER_NOTE))
write("glow-symbol-white.svg", svg(line(spark(MASTER), WHITE, STROKE), "Glow symbol, white",
                                   "A hollow four-point spark drawn as one rounded white line, for dark backgrounds.",
                                   comment=MASTER_NOTE))
write("glow-symbol-small.svg", svg(line(spark(SMALL), BRAND, SMALL_STROKE), "Glow symbol, small sizes",
                                   "A compact hollow four-point spark with a bolder line, for 32 pixels and below.",
                                   comment="For 32 px and below: stroke 32, centred on y 128 so the tips and the "
                                           "2 px line fall on whole pixels at 16 px."))
write("glow-symbol-square.svg", svg(f'<g transform="translate(0 2)">{line(spark(MASTER), BRAND, STROKE)}</g>',
                                    "Glow symbol, square", "The Glow spark centred on a transparent square, for avatars.",
                                    comment="Centred on the square for avatars: the symbol moved down 2 units."))
write("glow-app-icon.svg", svg(app_icon(), "Glow app icon",
                               "A white hollow four-point spark on an Apricot Terracotta rounded-square tile.",
                               1024, 1024, "macOS grid: an 824-unit body (inset 100, radius 186) and the white symbol "
                                           "at 62 %, centred 2 % high: the transform Hum, Pulse and Tuck use."))
write("glow-app-icon-small.svg", svg(app_icon(small=True), "Glow app icon, small sizes",
                                     "The Glow app icon drawn with the small-size cut, for 16 and 32 pixel rasters.",
                                     1024, 1024, "16 and 32 px rasters: the small cut (stroke 32) on the same tile "
                                                 "and transform, centred on its own y 128."))

# ---------------------------------------------------------------- lockup
# The wordmark is drawn the way Pulse's is: one 24-unit line with round caps, bowls of radius 40 centred on
# y 128, stems from y 76, the baseline at 180, an ascender from 32 and a descender to 228, and 50 units between
# letters' lines. The w is two u bowls sharing a full-height middle stem.
WORDMARK = ("M24 128 A40 40 0 1 1 104 128 A40 40 0 1 1 24 128 M104 76 V188 A40 40 0 0 1 64 228 "  # g
            "M154 32 V180 "                                                                         # l
            "M204 128 A40 40 0 1 1 284 128 A40 40 0 1 1 204 128 "                                   # o
            "M334 76 V128 A40 40 0 0 0 414 128 V76 M414 128 A40 40 0 0 0 494 128 V76")              # w
LOCKUP_NOTE = ("Symbol at full size, moved down 2 so its centre sits on the middle of the x-height (y 128); gap 40 "
               "to the wordmark, as Hum's and Pulse's lockups have.")


def lockup(word: str) -> str:
    return (f'<g transform="translate(0 2)">{line(spark(MASTER), BRAND, STROKE)}</g>\n'
            f'  <g transform="translate(268 0)">{line(WORDMARK, word, STROKE)}</g>')


write("glow-lockup-horizontal.svg", svg(lockup(INK), "Glow", "The Glow spark beside the word glow in Ink.",
                                        802, 256, LOCKUP_NOTE))
write("glow-lockup-horizontal-reversed.svg", svg(lockup(WHITE), "Glow",
                                                 "The Glow spark beside the word glow in white, for dark backgrounds.",
                                                 802, 256, LOCKUP_NOTE))

# ---------------------------------------------------------------- concept board
# Sibling geometry, copied from their masters for comparison only (hum-symbol-crimson.svg,
# pulse-symbol-violet.svg, Tuck's svg/tuck-symbol.svg). Tuck's line is stored as a filled outline.
HUM = ("M28 126 H48 C64 126 64 100 80 100 C92 100 100 152 112 152 C124 152 132 100 144 100 C156 100 164 152 176 "
       "152 C192 152 192 126 208 126 H228")
PULSE = "M28 170 H62 C88 170 90 82 128 82 C166 82 168 170 194 170 H228"
TUCK = ("M28 80 H68 A12 12 0 0 1 80 92 V124 A24 24 0 0 0 104 148 H152 A24 24 0 0 0 176 124 V92 A12 12 0 0 1 188 80 "
        "H228 A12 12 0 0 1 228 104 H200 V124 A48 48 0 0 1 152 172 H104 A48 48 0 0 1 56 124 V104 H28 A12 12 0 0 1 28 "
        "80 Z")
FONT = 'font-family="Helvetica Neue, Helvetica, Arial, sans-serif"'


def text(x: float, y: float, value: str, size: int = 17, fill: str = MUTED, weight: int = 400,
         spacing: float = 0) -> str:
    track = f' letter-spacing="{f(spacing)}"' if spacing else ""
    return (f'<text x="{f(x)}" y="{f(y)}" {FONT} font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}"{track}>{value}</text>')


def label(x: float, y: float, value: str, fill: str = MUTED) -> str:
    return text(x, y, value.upper(), 13, fill, 500, 1.6)


def card(x: float, y: float, w: float, h: float, fill: str = CARD, outline: str = "") -> str:
    edge = f' stroke="{outline}" stroke-width="3"' if outline else ""
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="24" fill="{fill}"{edge}/>'


def at(x: float, y: float, size: float, body: str) -> str:
    """Places 256-grid artwork with its canvas's top-left at (x, y), `size` px square."""
    return f'<g transform="translate({f(x)} {f(y)}) scale({f(size / 256)})">{body}</g>'


def tile(x: float, y: float, size: float, colour: str, mark: str) -> str:
    """A 1024-grid app icon placed `size` px square; `mark` is 256-grid artwork centred on y 126."""
    body = (f'<rect x="100" y="100" width="824" height="824" rx="186" fill="{colour}"/>'
            f'<g transform="{ICON.format(cy=-126)}">{mark}</g>')
    return f'<g transform="translate({f(x)} {f(y)}) scale({f(size / 1024)})">{body}</g>'


def guides() -> str:
    """The family envelope: ink x 16-240, the optical line y 126 and the vertical axis."""
    return (f'<rect x="16" y="8" width="224" height="240" fill="none" stroke="{RULE}" stroke-width="1.5" '
            f'stroke-dasharray="4 4"/><path d="M8 126 H248 M128 8 V248" stroke="{RULE}" stroke-width="1.5"/>')


def board() -> str:
    out = [f'<rect width="1600" height="1200" fill="{PAPER}"/>',
           text(64, 76, "Glow — Aperture Spark", 40, INK, 500),
           text(64, 112, "Aligned with Hum, Pulse and Tuck: the same drawing at family scale, on their optical "
                         "line and icon grid. One 24-unit line, an open centre.", 18)]

    # In the family: icons, then symbols in brand colour, at one size.
    out.append(card(64, 144, 1472, 316))
    out.append(label(92, 182, "In the family · shared 256 grid, 24-unit line, 62 % icon transform"))
    marks = [("Hum", SIBLINGS["Hum"], line(HUM, WHITE, 24), line(HUM, SIBLINGS["Hum"], 24)),
             ("Pulse", SIBLINGS["Pulse"], line(PULSE, WHITE, 24), line(PULSE, SIBLINGS["Pulse"], 24)),
             ("Tuck", SIBLINGS["Tuck"], f'<path d="{TUCK}" fill="{WHITE}"/>', f'<path d="{TUCK}" fill="{SIBLINGS["Tuck"]}"/>'),
             ("Glow", BRAND, line(spark(MASTER), WHITE, STROKE), line(spark(MASTER), BRAND, STROKE))]
    for i, (name, colour, white, coloured) in enumerate(marks):
        x = 104 + i * 172
        out.append(tile(x - 8, 206, 172, colour, white))
        out.append(text(x + 52 + (8 if name == "Hum" else 0), 418, name, 17, INK, 500))
        out.append(at(816 + i * 176, 222, 160, coloured))
    out.append(f'<path d="M790 214 V420" stroke="{RULE}" stroke-width="1.5"/>')

    # Options.
    options = [("Previous", "as shipped", PREVIOUS, False, "224 wide, centred on y 128: 56–63 %",
                "more ink than its siblings; icon at its own 2.2×."),
               ("A · Family scale", "recommended", MASTER, True, "The same curves at 88 %, lifted 2 units.",
                "Ink spans x 28–228, the family's line span."),
               ("B · Upright", "", UPRIGHT, False, "A turned on its diagonal: a taller glint,",
                "but the only vertical mark in the row."),
               ("C · Soft tips", "", SOFT, False, "A with its tip handles opened 7° and 6°:",
                "softer, wider centre, nearer a generic ✦.")]
    for i, (name, tag, side, best, note1, note2) in enumerate(options):
        x, y = 64 + i * 374, 488
        out.append(card(x, y, 350, 372, "#FFF8F3" if best else CARD, BRAND if best else ""))
        out.append(label(x + 24, y + 38, f"{name}" + (f" · {tag}" if tag else ""), BRAND if best else MUTED))
        out.append(at(x + 24, y + 58, 200, guides() + line(spark(side), BRAND, STROKE)))
        mark = line(spark(side), WHITE, STROKE)
        if side is PREVIOUS:   # the old icon placed (128 128) at (512 496) and scaled 2.2
            body = (f'<rect x="100" y="100" width="824" height="824" rx="186" fill="{BRAND}"/>'
                    f'<g transform="translate(230.4 214.4) scale(2.2)">{mark}</g>')
            out.append(f'<g transform="translate({f(x + 236)} {f(y + 168)}) scale({f(96 / 1024)})">{body}</g>')
        else:
            out.append(tile(x + 236, y + 168, 96, BRAND, mark))
        out.append(text(x + 24, y + 300, note1, 15))
        out.append(text(x + 24, y + 322, note2, 15))

    # Small sizes, drawn at actual pixel size on light and dark.
    out.append(card(64, 888, 860, 268))
    out.append(label(92, 926, "Actual size · small cut (stroke 32) at 32 px and below"))
    x = 92
    for px in (16, 24, 32, 48, 64):
        side, width = (SMALL, SMALL_STROKE) if px <= 32 else (MASTER, STROKE)
        out.append(at(x, 958 + (64 - px) / 2, px, line(spark(side), INK, width)))
        out.append(f'<rect x="{f(x - 8)}" y="1036" width="{f(px + 16)}" height="{f(px + 16)}" rx="6" fill="#1D1915"/>')
        out.append(at(x, 1044, px, line(spark(side), WHITE, width)))
        out.append(text(x, 1136, f"{px}", 14))
        x += px + 36
    x += 16
    out.append(text(x, 1112, "App icon: 16 and 32 use the small cut", 14))
    for px in (16, 32, 64, 128):
        icon = app_icon(small=px <= 32).replace("\n  ", "")
        out.append(f'<g transform="translate({f(x)} {f(958 + (128 - px) / 2)}) scale({f(px / 1024)})">{icon}</g>')
        out.append(text(x, 1136, f"{px}", 14))
        x += px + 24

    # Colour.
    out.append(card(948, 888, 588, 268))
    out.append(label(976, 926, "Colour · white on the tile"))
    for i, (name, colour, ratio, note) in enumerate(((("Intended", APRICOT, "2.62 : 1", "lightest of the four")),
                                                     ("Proposed", APRICOT_TUNED, "3.09 : 1", "Tuck Blue's lightness"))):
        x = 976 + i * 268
        out.append(tile(x - 10, 940, 116, colour, line(spark(MASTER), WHITE, STROKE)))
        out.append(text(x + 116, 980, name, 17, INK, 500))
        out.append(text(x + 116, 1004, colour, 15))
        out.append(text(x + 116, 1028, ratio, 15))
        out.append(text(x + 116, 1052, note, 13))
    for i, (name, colour) in enumerate(list(SIBLINGS.items()) + [("Glow", BRAND)]):
        x = 976 + i * 136
        out.append(f'<circle cx="{f(x + 14)}" cy="1114" r="14" fill="{colour}"/>')
        out.append(text(x + 36, 1110, name, 14, INK, 500))
        out.append(text(x + 36, 1128, colour, 12))
    return "\n  ".join(out)


write("glow-concept-board.svg", svg(board(), "Glow logo concept board",
                                    "The Glow spark beside Hum, Pulse and Tuck, three alignment options, actual-size "
                                    "tests and the colour proposal.", 1600, 1200))
print("wrote", len(list(ROOT.glob("*.svg"))), "SVGs")
