// Brick detection in a photo (port of detect_gray in tools/detect_atlas.py,
// the reference, and of BrickGen_Detect.ms). Input: grey values of a reduced
// copy of the photo, row-major. Both joint colours (dark / light mortar) are
// tried; the result covering the largest area x regular bed joints wins.
// Keep in sync with tools/detect_atlas.py and BrickGen_Detect.ms.

using System;
using System.Collections.Generic;
using System.Linq;

namespace BrickGen
{
    public static class Detector
    {
        // numpy-style percentile (linear interpolation), p in 0..100
        static double Pct(IList<double> arr, double p)
        {
            var a = arr.ToArray();
            Array.Sort(a);
            if (a.Length == 0) return 0;
            double f = p / 100.0 * (a.Length - 1);
            int i = (int)Math.Floor(f);
            return i + 1 >= a.Length ? a[a.Length - 1] : a[i] + (f - i) * (a[i + 1] - a[i]);
        }

        static List<int[]> Runs(bool[] mask, int minLen)
        {
            var res = new List<int[]>();
            int s = -1;
            for (int i = 0; i < mask.Length; i++)
            {
                if (mask[i] && s < 0) s = i;
                if (!mask[i] && s >= 0)
                {
                    if (i - s >= minLen) res.Add(new[] { s, i - 1 });
                    s = -1;
                }
            }
            if (s >= 0 && mask.Length - s >= minLen) res.Add(new[] { s, mask.Length - 1 });
            return res;
        }

        static List<double> BestChain(List<double[]> cands, double[] pitches, double tol)
        {
            int n = cands.Count;
            var chain = new List<double>();
            if (n == 0) return chain;
            var score = cands.Select(c => c[1]).ToArray();
            var prev = Enumerable.Repeat(-1, n).ToArray();
            for (int j = 0; j < n; j++)
                for (int i = 0; i < j; i++)
                {
                    double d = cands[j][0] - cands[i][0];
                    bool ok = false;
                    foreach (var p in pitches) if (Math.Abs(d - p) <= tol) ok = true;
                    if (ok && score[i] + cands[j][1] > score[j]) { score[j] = score[i] + cands[j][1]; prev[j] = i; }
                }
            int best = 0;
            for (int k = 1; k < n; k++) if (score[k] > score[best]) best = k;
            for (int k = best; k >= 0; k = prev[k]) chain.Insert(0, cands[k][0]);
            return chain;
        }

        class Course { public int Y0, Y1; public List<double[]> Cands; }

        // cells: x, y, w, h, kind (1 stretcher / 0 header) in g's pixels
        static List<double[]> DetectGray(float[] g, int w, int h, double fs, double L, double H, out double reg, out double coursePx)
        {
            reg = 0; coursePx = 0;
            var cells = new List<double[]>();
            int mn = Math.Max(1, (int)(2.0 * fs + 0.5));
            var row = new double[h];
            var buf = new double[w];
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++) buf[x] = g[y * w + x];
                row[y] = Pct(buf, 80);
            }
            double thr = Pct(row, 18);
            var beds = Runs(row.Select(v => v < thr).ToArray(), mn);
            if (beds.Count < 3) return cells;
            var cen = beds.Select(b => 0.5 * (b[0] + b[1])).ToList();
            double m0 = Pct(Enumerable.Range(0, cen.Count - 1).Select(i => cen[i + 1] - cen[i]).ToList(), 50);
            Func<int[], double> rowMin = b => { double m = 1e9; for (int i = b[0]; i <= b[1]; i++) m = Math.Min(m, row[i]); return m; };
            var keep = new List<int[]> { beds[0] };
            for (int i = 1; i < beds.Count; i++)
            {
                var b = beds[i];
                var last = keep[keep.Count - 1];
                if (0.5 * (b[0] + b[1]) - 0.5 * (last[0] + last[1]) < 0.6 * m0)
                {
                    if (rowMin(b) < rowMin(last)) keep[keep.Count - 1] = b;
                }
                else keep.Add(b);
            }
            beds = keep;
            if (beds.Count < 3) return cells;
            var d = new List<double>();
            for (int i = 0; i + 1 < beds.Count; i++) d.Add(0.5 * (beds[i + 1][0] + beds[i + 1][1]) - 0.5 * (beds[i][0] + beds[i][1]));
            coursePx = Pct(d, 50);
            double cp = coursePx;
            reg = d.Count(v => Math.Abs(v - cp) <= 0.15 * cp) / (double)d.Count;
            var gaps = new List<double>();
            for (int i = 0; i + 1 < beds.Count; i++) gaps.Add(beds[i + 1][0] - beds[i][1] - 1);
            double brickPx = Pct(gaps, 50);
            double jointPx = Math.Max(1.0, coursePx - brickPx);
            double s = brickPx / H;
            double jw = jointPx;

            var courses = new List<Course>();
            for (int bi = 0; bi + 1 < beds.Count; bi++)
            {
                int y0 = beds[bi][1] + 1, y1 = beds[bi + 1][0] - 1;
                if (y1 - y0 < Math.Max(4.0, 8.0 * fs)) continue;
                int r0 = y0 + mn, r1 = y1 - mn;
                if (r1 < r0) { r0 = y0; r1 = y1; }
                var col = new double[w];
                var vals = new double[r1 - r0 + 1];
                for (int x = 0; x < w; x++)
                {
                    for (int r = r0; r <= r1; r++) vals[r - r0] = g[r * w + x];
                    col[x] = Pct(vals, 85);
                }
                double med = Pct(col, 50), t = Pct(col, 15);
                var cands = new List<double[]>();
                foreach (var q in Runs(col.Select(v => v < t).ToArray(), mn))
                {
                    if (q[1] - q[0] > 2.5 * jw) continue;
                    double m = 1e9;
                    for (int i = q[0]; i <= q[1]; i++) m = Math.Min(m, col[i]);
                    cands.Add(new[] { 0.5 * (q[0] + q[1]), med - m });
                }
                if (cands.Count > 0)
                {
                    var st = cands.Select(c => c[1]).OrderBy(v => v).ToList();
                    var strong = st.Skip(st.Count / 2).ToList();
                    double pen = 0.6 * Pct(strong, 50);
                    foreach (var c in cands) c[1] -= pen;
                }
                courses.Add(new Course { Y0 = y0, Y1 = y1, Cands = cands });
            }

            // stretcher pitch from the histogram of neighbouring joint distances
            double expect = L * s + jointPx;
            int lo = Math.Max(2, (int)(0.5 * expect)), hi = (int)(4.5 * expect);
            var hist = new double[hi + 2];
            foreach (var crs in courses)
            {
                var xs = crs.Cands.Where(c => c[1] > 0).Select(c => c[0]).ToList();
                for (int i = 0; i + 1 < xs.Count; i++)
                {
                    int di = (int)(xs[i + 1] - xs[i] + 0.5);
                    if (di >= 0 && di <= hi) hist[di] += 1;
                }
            }
            var cum = new double[hist.Length + 1];
            for (int i = 0; i < hist.Length; i++) cum[i + 1] = cum[i] + hist[i];
            Func<double, double> window = center =>
            {
                double tw = Math.Max(1.0, 0.05 * center);
                int a = Math.Max(0, (int)(center - tw)), b = Math.Min(hi + 1, (int)(center + tw));
                return b < a ? 0.0 : cum[b + 1] - cum[a];
            };
            double ps = expect, bestV = -1;
            for (int pv = lo; pv <= hi; pv++)
            {
                double wp = window(pv), wh = window(0.5 * pv);
                double sc = (wp + Math.Min(wp, wh)) / (1.0 + 0.3 * Math.Abs(Math.Log(pv / expect)));
                if (sc > bestV) { bestV = sc; ps = pv; }
            }
            double tol = 0.12 * 0.5 * ps;
            bool hasHeaders = window(0.5 * ps) >= 0.5 * window(ps);

            Func<double[], List<double[]>> chainCells = pitches =>
            {
                var res = new List<double[]>();
                foreach (var crs in courses)
                {
                    var ch = BestChain(crs.Cands, pitches, tol);
                    for (int i = 0; i + 1 < ch.Count; i++)
                    {
                        int x0 = (int)(ch[i] + 0.5 * jw + 0.5), x1 = (int)(ch[i + 1] - 0.5 * jw + 0.5);
                        if (x1 - x0 >= 0.8 * (crs.Y1 - crs.Y0))
                            res.Add(new double[] { x0, crs.Y0, x1 - x0 + 1, crs.Y1 - crs.Y0 + 1, (x1 - x0 + 1) > 0.75 * ps ? 1 : 0 });
                    }
                }
                return res;
            };
            cells = chainCells(hasHeaders ? new[] { ps, 0.5 * ps } : new[] { ps });
            if (cells.Count(c => c[4] == 0) < 0.2 * cells.Count) cells = chainCells(new[] { ps });

            // free lengths when the pitches explain little of the photo
            double covered = cells.Sum(c => c[2] * c[3]);
            if (covered < 0.35 * w * h)
            {
                var allSt = courses.SelectMany(c => c.Cands).Where(c => c[1] > 0).Select(c => c[1]).ToList();
                if (allSt.Count > 0)
                {
                    double thr2 = 0.5 * Pct(allSt, 90);
                    var free = new List<double[]>();
                    double freeArea = 0;
                    foreach (var crs in courses)
                    {
                        var m = new List<double>();
                        foreach (var c in crs.Cands)
                            if (c[1] >= thr2 && (m.Count == 0 || c[0] - m[m.Count - 1] >= 1.5 * brickPx)) m.Add(c[0]);
                        for (int i = 0; i + 1 < m.Count; i++)
                        {
                            int x0 = (int)(m[i] + 0.5 * jw + 0.5), x1 = (int)(m[i + 1] - 0.5 * jw + 0.5);
                            if (x1 - x0 >= 1.5 * (crs.Y1 - crs.Y0))
                            {
                                free.Add(new double[] { x0, crs.Y0, x1 - x0 + 1, crs.Y1 - crs.Y0 + 1, 1 });
                                freeArea += (x1 - x0 + 1) * (crs.Y1 - crs.Y0 + 1);
                            }
                        }
                    }
                    if (freeArea > covered) cells = free;
                }
            }
            return cells;
        }

        /// <summary>
        /// gray: w*h grey values (row-major) of the photo reduced by factor fs.
        /// Returns #(coursePx, n, x, y, w, h, kind, ...) in reduced pixels
        /// (kind 1 = stretcher, 0 = header), for the better joint colour.
        /// </summary>
        public static double[] Detect(float[] gray, int w, int h, double fs, double L, double H)
        {
            double bestScore = -1, bestCp = 0;
            List<double[]> best = new List<double[]>();
            for (int pass = 0; pass < 2; pass++)
            {
                var g = gray;
                if (pass == 1) { g = new float[gray.Length]; for (int i = 0; i < g.Length; i++) g[i] = 255f - gray[i]; }
                double reg, cp;
                var cells = DetectGray(g, w, h, fs, L, H, out reg, out cp);
                double area = cells.Sum(c => c[2] * c[3]);
                double score = area * reg * reg;
                if (score > bestScore) { bestScore = score; best = cells; bestCp = cp; }
            }
            var res = new List<double> { bestCp, best.Count };
            foreach (var c in best) res.AddRange(c);
            return res.ToArray();
        }
    }
}
