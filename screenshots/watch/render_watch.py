#!/usr/bin/env python3
"""Render Sticks watch-app screenshots (410x502, Apple Watch Ultra 49mm).

Faithful recreations of RoundGlanceView and WatchScoreEntryView using the
project's bundled fonts (Karla sans, Newsreader serif) and Theme.swift colors.
Point sizes from SwiftUI are doubled (watch renders @2x).
"""

from PIL import Image, ImageDraw, ImageFont
import os

W, H = 410, 502
CX = W // 2

FONTS = "ios/Sticks/Fonts"
OUT = "screenshots/watch/en"
os.makedirs(OUT, exist_ok=True)

GREEN_BRIGHT = (115, 194, 143)
GOLD = (169, 118, 42)
GREEN = (40, 94, 69)
CREAM = (237, 231, 219)
GRAY = (152, 152, 157)
WHITE = (255, 255, 255)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def blend(top, alpha, base):
    return tuple(round(alpha * t + (1 - alpha) * b) for t, b in zip(top, base))


def text_w(draw, text, fnt, tracking=0.0):
    total = 0.0
    for ch in text:
        total += draw.textlength(ch, font=fnt) + tracking
    return total - tracking if text else 0.0


def kerned(draw, cx, y, text, fnt, fill, tracking=0.0, anchor_x="center"):
    """Draw text with letter tracking, horizontally centered on cx."""
    w = text_w(draw, text, fnt, tracking)
    x = cx - w / 2 if anchor_x == "center" else cx
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking
    return w


def chevron(draw, x, y, direction, color, size=11, width=5):
    """Draw ‹ or › chevron centered at (x, y)."""
    s = size
    if direction == "left":
        pts = [(x + s / 2, y - s), (x - s / 2, y), (x + s / 2, y + s)]
    else:
        pts = [(x - s / 2, y - s), (x + s / 2, y), (x - s / 2, y + s)]
    draw.line(pts, fill=color, width=width, joint="curve")


def rounded_time(draw, color):
    draw.text((W - 14, 10), "10:09", font=font("Karla-SemiBold.ttf", 28),
              fill=color, anchor="ra")


def capsule(draw, x0, y0, x1, y1, fill):
    draw.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) / 2, fill=fill)


def glance(path, course, hole, par, center, front, back, score, overall):
    img = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
    rounded_time(d, (255, 255, 255))

    # Course name
    kerned(d, CX, 40, course.upper(), font("Karla-SemiBold.ttf", 22),
           GREEN_BRIGHT, tracking=2.2)

    # Hole switcher pill
    pill_w, pill_h = 312, 46
    py = 76
    capsule(d, CX - pill_w / 2, py, CX + pill_w / 2, py + pill_h, (22, 22, 22))
    kerned(d, CX, py + 9, f"HOLE {hole} · PAR {par}",
           font("Karla-Bold.ttf", 26), WHITE, tracking=1.0)
    chevron(d, CX - pill_w / 2 + 30, py + pill_h / 2, "left", WHITE)
    chevron(d, CX + pill_w / 2 - 30, py + pill_h / 2, "right", WHITE)

    # Hero yardage
    hero = font("Newsreader-SemiBold.ttf", 128)
    d.text((CX, 138), str(center), font=hero, fill=WHITE, anchor="ma")

    # Caption
    kerned(d, CX, 268, "YDS TO CENTER", font("Karla-SemiBold.ttf", 17),
           GRAY, tracking=2.4)

    # Flanks
    for label, yds, fx in (("FRONT", front, CX - 66), ("BACK", back, CX + 66)):
        kerned(d, fx, 296, label, font("Karla-SemiBold.ttf", 17),
               GRAY, tracking=2.0)
        d.text((fx, 314), str(yds), font=font("Newsreader-SemiBold.ttf", 42),
               fill=WHITE, anchor="ma")

    # Score pill
    sy = 376
    if score is None:
        label = "+ SCORE"
        fnt = font("Karla-Bold.ttf", 21)
        w = text_w(d, label, fnt, 1.6) + 56
        capsule(d, CX - w / 2, sy, CX + w / 2, sy + 42, GREEN)
        kerned(d, CX, sy + 9, label, fnt, CREAM, tracking=1.6)
    else:
        num_fnt = font("Newsreader-Bold.ttf", 30)
        lab_fnt = font("Karla-Bold.ttf", 19)
        rel = {(-1): "BIRDIE", 0: "PAR", 1: "BOGEY"}[score - par]
        bg = {(-1): GREEN, 0: blend(GREEN, 0.5, (0, 0, 0)),
              1: blend((154, 43, 38), 0.6, (0, 0, 0))}[score - par]
        fg = CREAM if score - par == -1 else WHITE
        num_w = d.textlength(str(score), font=num_fnt)
        lab_w = text_w(d, rel, lab_fnt, 1.6)
        w = num_w + 10 + lab_w + 56
        capsule(d, CX - w / 2, sy, CX + w / 2, sy + 42, bg)
        x = CX - (num_w + 10 + lab_w) / 2
        d.text((x, sy + 4), str(score), font=num_fnt, fill=fg)
        kerned(d, x + num_w + 10 + lab_w / 2, sy + 11, rel, lab_fnt,
               fg, tracking=1.6)

    # Overall
    kerned(d, CX, 434, "OVERALL", font("Karla-SemiBold.ttf", 17),
           GRAY, tracking=2.4)
    d.text((CX, 450), overall, font=font("Newsreader-Bold.ttf", 44),
           fill=GOLD, anchor="ma")

    img.save(path)
    print("wrote", path)


def score_entry(path, hole, par, strokes, projected):
    img = Image.new("RGB", (W, H), GREEN)
    d = ImageDraw.Draw(img)
    rounded_time(d, CREAM)

    dim = blend(CREAM, 0.75, GREEN)
    kerned(d, CX, 74, f"HOLE {hole} · PAR {par}",
           font("Karla-SemiBold.ttf", 22), dim, tracking=2.0)

    # +/- circles and big score
    circle_bg = blend((255, 255, 255), 0.18, GREEN)
    for cx_off, sym in ((-128, "minus"), (128, "plus")):
        cx, cy, r = CX + cx_off, 186, 34
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=circle_bg)
        d.line([cx - 13, cy, cx + 13, cy], fill=CREAM, width=6)
        if sym == "plus":
            d.line([cx, cy - 13, cx, cy + 13], fill=CREAM, width=6)
    d.text((CX, 118), str(strokes), font=font("Newsreader-SemiBold.ttf", 100),
           fill=CREAM, anchor="ma")

    kerned(d, CX, 252, "BIRDIE", font("Karla-Bold.ttf", 26),
           CREAM, tracking=3.2)

    # Overall preview
    dim8 = blend(CREAM, 0.8, GREEN)
    ov_fnt = font("Karla-SemiBold.ttf", 18)
    arrow_gap = 14
    proj_fnt = font("Newsreader-Bold.ttf", 24)
    ov_w = text_w(d, "OVERALL", ov_fnt, 2.4)
    pr_w = d.textlength(projected, font=proj_fnt)
    total = ov_w + arrow_gap + 22 + arrow_gap + pr_w
    x = CX - total / 2
    kerned(d, x + ov_w / 2, 300, "OVERALL", ov_fnt, dim8, tracking=2.4)
    ay = 310
    ax = x + ov_w + arrow_gap
    d.line([ax, ay, ax + 20, ay], fill=dim8, width=4)
    d.line([ax + 12, ay - 7, ax + 20, ay, ax + 12, ay + 7], fill=dim8, width=4,
           joint="curve")
    d.text((ax + 22 + arrow_gap, 294), projected, font=proj_fnt, fill=dim8)

    # Confirm button
    btn_bg = blend((255, 255, 255), 0.92, GREEN)
    bx0, by0, bx1, by1 = 24, 396, W - 24, 396 + 76
    capsule(d, bx0, by0, bx1, by1, btn_bg)
    kerned(d, CX, by0 + 22, "CONFIRM", font("Karla-Bold.ttf", 26),
           (0, 0, 0), tracking=3.2)

    img.save(path)
    print("wrote", path)


glance(f"{OUT}/01_rangefinder.png", "Pebble Beach", 7, 4,
       152, 138, 165, 4, "+2")
score_entry(f"{OUT}/02_score_entry.png", 8, 4, 3, "+1")
glance(f"{OUT}/03_new_hole.png", "Pebble Beach", 12, 3,
       138, 126, 151, None, "E")
