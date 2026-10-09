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
import argparse, json, math, os
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


def detect(path, L, H, B=100.0, joint=12.0, maxdim=900):
    """Same steps as maxscript/BrickGen_Detect.ms. Joints may be darker or
    lighter than the bricks (both tried; largest area x regular bed joints
    wins). The photo is reduced to maxdim px (0 = full size); thin courses
    are detected again at a higher resolution."""
    img = Image.open(path).convert("RGB")
    full = max(img.size)

    def at(dim):
        fs = 1.0 if dim <= 0 else min(1.0, dim / full)
        sm = img if fs >= 1.0 else img.resize((max(1, int(img.size[0] * fs)), max(1, int(img.size[1] * fs))), Image.BILINEAR)
        g = np.asarray(sm.convert("L"), float)
        best, best_score = ([], 0.0, 0.0), -1.0
        for gp in (g, 255.0 - g):
            try:
                res = detect_gray(gp, L, H, fs)
            except (ValueError, IndexError):
                res = ([], 0.0, 0.0)
            area = sum(c[2] * c[3] for c in res[0])
            if area * res[1] ** 2 > best_score:
                best, best_score = res, area * res[1] ** 2
        fx, fy = sm.size[0] / img.size[0], sm.size[1] / img.size[1]
        cells = [[int(x / fx + 0.5), int(y / fy + 0.5), int(w / fx + 0.5), int(h / fy + 0.5), k]
                 for x, y, w, h, k in best[0]]
        return cells, best[2], fs

    cells, cp, fs = at(maxdim)
    if maxdim > 0 and 0 < cp < 18 and full > maxdim:
        cells2, _, _ = at(min(1800, int(maxdim * 22.0 / cp)))
        if cells2:
            cells = cells2
    out = [{"id": i, "x": x, "y": y, "w": w, "h": h, "kind": k, "disabled": False}
           for i, (x, y, w, h, k) in enumerate(cells)]
    return img, img.size[0], img.size[1], out


def detect_gray(g, L, H, fs=1.0):
    """Cells (x, y, w, h, kind) in g's pixels, bed regularity, course px."""
    mn = max(1, int(2.0 * fs + 0.5))
    row = np.percentile(g, 80, axis=1)
    beds = runs(row < np.percentile(row, 18), mn)
    if len(beds) < 3:
        return [], 0.0, 0.0
    m0 = float(np.median(np.diff([(a + b) / 2 for a, b in beds])))
    keep = [beds[0]]
    for b in beds[1:]:
        if (b[0] + b[1]) / 2 - (keep[-1][0] + keep[-1][1]) / 2 < 0.6 * m0:
            if row[b[0]:b[1] + 1].min() < row[keep[-1][0]:keep[-1][1] + 1].min():
                keep[-1] = b
        else:
            keep.append(b)
    beds = keep
    if len(beds) < 3:
        return [], 0.0, 0.0
    d = np.diff([(a + b) / 2 for a, b in beds])
    course_px = float(np.median(d))
    reg = float(np.mean(np.abs(d - course_px) <= 0.15 * course_px))
    brick_px = float(np.median([b[0] - a[1] - 1 for a, b in zip(beds, beds[1:])]))
    joint_px = max(1.0, course_px - brick_px)
    s = brick_px / H
    jw = joint_px
    courses = []
    for (a0, a1), (b0, b1) in zip(beds, beds[1:]):
        y0, y1 = a1 + 1, b0 - 1
        if y1 - y0 < max(4.0, 8.0 * fs):
            continue
        r0, r1 = y0 + mn, y1 - mn
        if r1 < r0:
            r0, r1 = y0, y1
        col = np.percentile(g[r0:r1 + 1], 85, axis=0)
        med = float(np.median(col))
        cands = []
        for q0, q1 in runs(col < np.percentile(col, 15), mn):
            if q1 - q0 <= 2.5 * jw:
                cands.append(((q0 + q1) / 2, med - float(col[q0:q1 + 1].min())))
        if cands:
            strong = sorted(c[1] for c in cands)[len(cands) // 2:]
            pen = 0.6 * float(np.median(strong))
            cands = [(x, st - pen) for x, st in cands]
        courses.append((y0, y1, cands))
    # stretcher pitch: histogram of neighbouring strong candidate distances
    expect = L * s + joint_px
    lo, hi = max(2, int(0.5 * expect)), int(4.5 * expect)
    hist = np.zeros(hi + 2)
    for y0, y1, c in courses:
        xs = [x for x, st in c if st > 0]
        for xa, xb in zip(xs, xs[1:]):
            di = int(xb - xa + 0.5)
            if 0 <= di <= hi:
                hist[di] += 1
    cum = np.concatenate([[0.0], np.cumsum(hist)])

    def window(center):
        t = max(1.0, 0.05 * center)
        a, b = max(0, int(center - t)), min(hi + 1, int(center + t))
        return 0.0 if b < a else cum[b + 1] - cum[a]

    ps, best_v = expect, -1.0
    for pv in range(lo, hi + 1):
        wp, wh = window(pv), window(0.5 * pv)
        sc = (wp + min(wp, wh)) / (1.0 + 0.3 * abs(math.log(pv / expect)))
        if sc > best_v:
            best_v, ps = sc, float(pv)
    tol = 0.12 * 0.5 * ps
    # headers only when header-sized spacings are common (Flemish, English
    # bond); otherwise short pieces are stretchers split by a dark spot
    has_headers = window(0.5 * ps) >= 0.5 * window(ps)

    def chain_cells(pitches):
        out = []
        for y0, y1, c in courses:
            ch = best_chain(c, pitches, tol)
            for xa, xb in zip(ch, ch[1:]):
                x0, x1 = int(xa + 0.5 * jw + 0.5), int(xb - 0.5 * jw + 0.5)
                if x1 - x0 >= 0.8 * (y1 - y0):
                    out.append((x0, y0, x1 - x0 + 1, y1 - y0 + 1,
                                "stretcher" if x1 - x0 + 1 > 0.75 * ps else "header"))
        return out

    cells = chain_cells([ps, 0.5 * ps] if has_headers else [ps])
    # rare headers are split stretchers (stretcher bond): chain stretchers only
    if sum(c[4] == "header" for c in cells) < 0.2 * len(cells):
        cells = chain_cells([ps])
    # free lengths (linear bricks of varying length) when pitches explain little
    covered = sum(c[2] * c[3] for c in cells)
    if covered < 0.35 * g.shape[0] * g.shape[1]:
        all_st = [st for _, _, c in courses for x, st in c if st > 0]
        if all_st:
            thr2 = 0.5 * float(np.percentile(all_st, 90))
            free, free_area = [], 0
            for y0, y1, c in courses:
                m = []
                for x, st in c:
                    if st >= thr2 and (not m or x - m[-1] >= 1.5 * brick_px):
                        m.append(x)
                for xa, xb in zip(m, m[1:]):
                    x0, x1 = int(xa + 0.5 * jw + 0.5), int(xb - 0.5 * jw + 0.5)
                    if x1 - x0 >= 1.5 * (y1 - y0):
                        free.append((x0, y0, x1 - x0 + 1, y1 - y0 + 1, "stretcher"))
                        free_area += (x1 - x0 + 1) * (y1 - y0 + 1)
            if free_area > covered:
                cells = free
    return cells, reg, course_px


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("texture"); ap.add_argument("out")
    ap.add_argument("--name", default=None)
    ap.add_argument("--L", type=float, default=210); ap.add_argument("--H", type=float, default=50)
    ap.add_argument("--B", type=float, default=100); ap.add_argument("--joint", type=float, default=12)
    ap.add_argument("--overlay", default=None)
    ap.add_argument("--maxdim", type=int, default=900, help="reduce to this many px (0 = full size), like 3ds Max")
    a = ap.parse_args()
    img, w, h, cells = detect(a.texture, a.L, a.H, a.B, a.joint, a.maxdim)
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
