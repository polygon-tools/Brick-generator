"""Detect brick cells in a regular brick texture and write a BrickGen atlas JSON
(PLAN.md §9). Reference implementation for the web tool (phase 3).

usage: python detect_atlas.py texture.jpg out.json --name "..." [--L 210 --H 50]
       [--overlay check.png]

Method: bed joints = dark rows (row brightness profile). The course pitch gives
the scale (px per mm, joints 12 mm), so the expected stretcher and header
pitches are known. Per course, head-joint candidates are columns that are dark
over the whole course height (85th percentile); a dynamic programme then picks
the chain of candidates whose spacings are stretcher or header pitches and
whose joints are darkest, so dark spots on a brick are not taken for joints.
Cells cut off by the image border are skipped.
"""
import argparse, json, os
import numpy as np
from PIL import Image, ImageDraw


def runs(mask, min_len=1):
    out, s = [], None
    for i, v in enumerate(mask):
        if v and s is None:
            s = i
        if not v and s is not None:
            if i - s >= min_len:
                out.append((s, i - 1))
            s = None
    if s is not None and len(mask) - s >= min_len:
        out.append((s, len(mask) - 1))
    return out


def best_chain(cands, pitches, tol):
    """cands: [(x, strength)] sorted by x. Max-score chain with spacings in pitches."""
    n = len(cands)
    score = [c[1] for c in cands]
    prev = [-1] * n
    for j in range(n):
        for i in range(j):
            d = cands[j][0] - cands[i][0]
            if any(abs(d - p) <= tol for p in pitches) and score[i] + cands[j][1] > score[j]:
                score[j] = score[i] + cands[j][1]
                prev[j] = i
    if not n:
        return []
    j = max(range(n), key=lambda k: score[k])
    chain = []
    while j >= 0:
        chain.append(cands[j][0]); j = prev[j]
    return chain[::-1]


def detect(path, L, H, B=100.0, joint=12.0):
    img = Image.open(path).convert("RGB")
    g = np.asarray(img.convert("L"), float)
    h, w = g.shape
    # bed joints
    row = np.percentile(g, 80, axis=1)
    beds = runs(row < np.percentile(row, 18), 2)
    centres = [(a + b) / 2 for a, b in beds]
    course_px = float(np.median(np.diff(centres)))
    s = course_px / (H + joint)  # px per mm
    pitches = [(L + joint) * s, (B + joint) * s]
    tol = 0.12 * pitches[1]
    cells = []
    for (a0, a1), (b0, b1) in zip(beds, beds[1:]):
        y0, y1 = a1 + 1, b0 - 1
        if y1 - y0 < 8:
            continue
        band = g[y0 + 2:y1 - 1]
        col = np.percentile(band, 85, axis=0)
        med = float(np.median(col))
        jw = joint * s
        cands = []
        for r0, r1 in runs(col < np.percentile(col, 15), 2):
            if r1 - r0 > 2.5 * jw:
                continue  # too wide for a joint
            cands.append(((r0 + r1) / 2, med - float(col[r0:r1 + 1].min())))
        # a weak dark spot inside a stretcher must not split it in two headers:
        # every joint in the chain costs a fixed penalty
        if cands:
            strong = sorted(c[1] for c in cands)[len(cands) // 2:]
            pen = 0.6 * float(np.median(strong))
            cands = [(x, st - pen) for x, st in cands]
        for xa, xb in zip(*(lambda c: (c, c[1:]))(best_chain(cands, pitches, tol))):
            x0, x1 = int(round(xa + jw / 2)), int(round(xb - jw / 2))
            if x1 - x0 >= 0.8 * (y1 - y0):
                cells.append([x0, y0, x1 - x0 + 1, y1 - y0 + 1])
    # stretcher / header by width
    split = 0.5 * (L + B) * s
    out = []
    for i, (x, y, cw, ch) in enumerate(cells):
        out.append({"id": i, "x": int(x), "y": int(y), "w": int(cw), "h": int(ch),
                    "kind": "stretcher" if cw > split else "header", "disabled": False})
    return img, w, h, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("texture"); ap.add_argument("out")
    ap.add_argument("--name", default=None)
    ap.add_argument("--L", type=float, default=210); ap.add_argument("--H", type=float, default=50)
    ap.add_argument("--B", type=float, default=100); ap.add_argument("--joint", type=float, default=12)
    ap.add_argument("--overlay", default=None)
    a = ap.parse_args()
    img, w, h, cells = detect(a.texture, a.L, a.H, a.B, a.joint)
    atlas = {
        "version": 1,
        "name": a.name or os.path.splitext(os.path.basename(a.texture))[0],
        "image": {"width": w, "height": h},
        "maps": {"diffuse": os.path.basename(a.texture), "normal": None, "roughness": None, "bump": None},
        "realBrick": {"L": a.L, "H": a.H},
        "cells": cells,
    }
    with open(a.out, "w") as f:
        json.dump(atlas, f, indent=1)
    ns = sum(c["kind"] == "stretcher" for c in cells)
    print(f"{len(cells)} cells ({ns} stretchers, {len(cells) - ns} headers) -> {a.out}")
    if a.overlay:
        d = ImageDraw.Draw(img)
        for c in cells:
            col = (0, 255, 0) if c["kind"] == "stretcher" else (0, 160, 255)
            d.rectangle([c["x"], c["y"], c["x"] + c["w"] - 1, c["y"] + c["h"] - 1], outline=col, width=2)
        img.save(a.overlay)


if __name__ == "__main__":
    main()
