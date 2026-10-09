// BrickGen.Core: the geometry builder of the BrickGen modifier in C#
// (PLAN.md: performance). A line-by-line port of BrickGen_RNG.ms,
// BrickGen_Bonds.ms, BrickGen_Region.ms, BrickGen_Mesh.ms (buildRegionInto,
// buildRevealsInto, addBrick, addMortarRect) and BrickGenAtlasLib.mapBrick.
// Same RNG, same channels: the same seed gives the same wall as the MAXScript
// version. Keep both in sync when the algorithm changes.
//
// Called from BrickGen_Modifier.ms through dotNet; results are flat arrays
// (MAXScript converts arrays returned by methods to MAXScript arrays).
// Targets netstandard2.0 so it loads in .NET Framework and .NET 8 (3ds Max 2025+).

using System;
using System.Collections.Generic;

namespace BrickGen
{
    /// <summary>All lengths in mm. Set by MAXScript before calling Builder.Build.</summary>
    public class Params
    {
        public int Seed = 12345;
        public double BrickL = 210, BrickB = 100, BrickH = 50;
        public double BedJoint = 12, HeadJoint = 12, JointRecess = 5;
        public bool MortarEnabled = true;
        public int BondType = 1; // 1-based, order of BrickGen_Bonds.ms
        public double StartOffset = 0, WildMinOverlap = 0.25;
        public double Chamfer = 2, ChamferJitter = 0.3, CornerJitter = 1, DepthJitter = 1.5;
        public double RotJitter = 0.3, SizeJitter = 1;
        public int MatIdCount = 5, MortarMatId = 100;
        public bool PreviewMode = false;
        public bool AtlasFlip = true, AtlasRotate = true;
        public double ChipChance = 0, ChipSize = 6;
        public double RevealDepth = 0, RevealOffset = 0;
        public bool RevealOuter = false;

        // internal (per strip)
        internal int SegIndex = 0;
        internal double UOffset = 0;
        internal double[] Tm; // 12 values, rows of a 3ds Max matrix3
        internal Bond BondOverride;
        internal double WallLength, WallHeight;

        internal Params Clone() { return (Params)MemberwiseClone(); }
    }

    /// <summary>Flat result arrays (1-based face indices, like 3ds Max).</summary>
    public class Result
    {
        public float[] Verts;   // x, y, z per vertex
        public int[] Faces;     // a, b, c per face (1-based)
        public int[] MatIDs;    // per face
        public int[] Smooth;    // per face
        public float[] UV1;     // u, v per vertex
        public float[] UV2;     // u, v per vertex
        public int BrickCount;
        public double Milliseconds;

        public float[] GetVerts() { return Verts; }
        public int[] GetFaces() { return Faces; }
        public int[] GetMatIDs() { return MatIDs; }
        public int[] GetSmooth() { return Smooth; }
        public float[] GetUV1() { return UV1; }
        public float[] GetUV2() { return UV2; }
    }

    internal enum Unit { S, K, KM }

    internal class Course
    {
        public double AL, AB, AJ;
        public Unit[] Units;
        public Course(double aL, double aB, double aJ, params Unit[] u) { AL = aL; AB = aB; AJ = aJ; Units = u; }
    }

    internal class Bond
    {
        public Course[] Courses;
        public bool Wild;
        public Bond(bool wild, params Course[] c) { Wild = wild; Courses = c; }
    }

    // ------------------------------------------------------------------ RNG
    internal static class Rng
    {
        const long P = 2147483647L;
        static long ModP(long x) { return x - (x / P) * P; }

        static long Mix(long x)
        {
            x = ModP(Math.Abs(x));
            x = ModP(x * x + 1013904223L);
            x = ModP(x * 48271L);
            x = ModP(x * x + 362437L);
            return x;
        }

        public static long BrickKey(long seed, long idx)
        {
            return Mix(Mix(seed + 9973L) + idx * 7919L + 1L);
        }

        static long HashCh(long key, long ch)
        {
            long x = key + ch * 104729L + 7L;
            x = ModP(x * x + 1013904223L);
            x = ModP(x * 48271L);
            return ModP(x * x + 362437L);
        }

        public static double U01(long key, long ch)
        {
            double r = HashCh(key, ch) / 2147483647.0;
            return r >= 1.0 ? 0.9999999 : r;
        }

        public static void U01x3(long key, long ch, out double a, out double b, out double c)
        {
            long x = HashCh(key, ch);
            long ia = x - (x / 1024L) * 1024L;
            x = x / 1024L;
            long ib = x - (x / 1024L) * 1024L;
            long ic = x / 1024L;
            a = ia / 1024.0; b = ib / 1024.0; c = ic / 2048.0;
        }

        public static void Sym3(long key, long ch, out double a, out double b, out double c)
        {
            U01x3(key, ch, out a, out b, out c);
            a = 2 * a - 1; b = 2 * b - 1; c = 2 * c - 1;
        }
    }

    // ---------------------------------------------------------------- Bonds
    internal static class Bonds
    {
        // Same order as BrickGen_Bonds.ms (the index is stored in scenes).
        public static readonly Bond[] Defs =
        {
            new Bond(false, new Course(0, 0, 0, Unit.S), new Course(0.5, 0, 0.5, Unit.S)),                 // Halfsteens
            new Bond(false, new Course(0, 0, 0, Unit.S)),                                                  // Staand
            new Bond(false, new Course(0, 0, 0, Unit.S, Unit.K), new Course(0.5, -0.5, 0, Unit.K, Unit.S)), // Vlaams
            new Bond(false, new Course(0, 0, 0, Unit.S), new Course(1, -0.5, 0.5, Unit.KM),
                            new Course(0.5, 0, 0.5, Unit.S), new Course(1, -0.5, 0.5, Unit.KM)),          // Kruisverband
            new Bond(true, new Course(0, 0, 0, Unit.S)),                                                   // Wild
        };

        public static Bond Get(int i) { return (i >= 1 && i <= Defs.Length) ? Defs[i - 1] : Defs[0]; }

        public static double UnitLength(Unit u, double L, double B) { return (u == Unit.K || u == Unit.KM) ? B : L; }

        public static double UnitPitch(Unit u, double L, double B, double hj)
        {
            return u == Unit.KM ? 0.5 * (L + hj) : UnitLength(u, L, B) + hj;
        }

        public static Course CourseDef(Bond b, int c) { return b.Courses[c % b.Courses.Length]; }

        // MAXScript "mod" on floats (fmod: sign of the dividend) is C#'s %.
        public static double[] CourseOffsets(Bond bond, int n, int seed, double L, double B, double hj, double minOverlap)
        {
            var offs = new double[Math.Max(0, n)];
            if (!bond.Wild)
            {
                for (int c = 0; c < n; c++)
                {
                    var k = CourseDef(bond, c);
                    offs[c] = k.AL * L + k.AB * B + k.AJ * hj;
                }
                return offs;
            }
            double Lm = L + hj;
            var steps = new List<double>();
            if (n > 0) offs[0] = 0;
            for (int c = 1; c < n; c++)
            {
                double chosenO = 0, chosenS = 0;
                bool done = false;
                int t = 1;
                while (!done)
                {
                    long key = Rng.BrickKey(seed, -1 - c);
                    double s = Lm * (minOverlap + (1.0 - 2.0 * minOverlap) * Rng.U01(key, t));
                    double o = (offs[c - 1] + s) % Lm;
                    bool ok = true;
                    if (c >= 2)
                    {
                        double d = Math.Abs((o - offs[c - 2]) % Lm);
                        d = Math.Min(d, Lm - d);
                        if (d < 0.5 * minOverlap * Lm) ok = false;
                    }
                    if (ok && steps.Count >= 2)
                    {
                        double s1 = steps[steps.Count - 1], s2 = steps[steps.Count - 2];
                        if (Math.Abs(s - s1) < 0.08 * Lm && Math.Abs(s1 - s2) < 0.08 * Lm) ok = false;
                    }
                    if (ok || t >= 16) { chosenO = o; chosenS = s; done = true; }
                    t++;
                }
                offs[c] = chosenO;
                steps.Add(chosenS);
            }
            return offs;
        }

        public struct Piece { public double X0, X1; public Unit U; public int K; }

        public static List<Piece> LayoutCourse(Unit[] units, double offset, double wallLen, double hj, double L, double B)
        {
            var res = new List<Piece>();
            int n = units.Length;
            double period = 0;
            foreach (var u in units) period += UnitPitch(u, L, B, hj);
            if (period <= 0) return res;
            double x = offset % period;
            if (x > 0) x -= period;
            int k = 0;
            while (x < wallLen && k < 200000)
            {
                var u = units[k % n];
                double xb = x + UnitLength(u, L, B);
                if (xb > 0) res.Add(new Piece { X0 = x, X1 = xb, U = u, K = k });
                x += UnitPitch(u, L, B, hj);
                k++;
            }
            return res;
        }
    }

    // --------------------------------------------------------------- Region
    internal struct V2 { public double X, Y; public V2(double x, double y) { X = x; Y = y; } }

    internal static class Region
    {
        public static List<double[]> IntervalsAt(List<V2[]> polys, double y)
        {
            var xs = new List<double>();
            foreach (var poly in polys)
            {
                int n = poly.Length;
                for (int i = 0; i < n; i++)
                {
                    var a = poly[i];
                    var b = poly[i == n - 1 ? 0 : i + 1];
                    if ((a.Y <= y && y < b.Y) || (b.Y <= y && y < a.Y))
                        xs.Add(a.X + (y - a.Y) * (b.X - a.X) / (b.Y - a.Y));
                }
            }
            xs.Sort();
            var res = new List<double[]>();
            for (int i = 0; i + 1 < xs.Count; i += 2) res.Add(new[] { xs[i], xs[i + 1] });
            return res;
        }

        public static List<double[]> Intersect(List<double[]> A, List<double[]> B)
        {
            var res = new List<double[]>();
            int i = 0, j = 0;
            while (i < A.Count && j < B.Count)
            {
                double lo = Math.Max(A[i][0], B[j][0]);
                double hi = Math.Min(A[i][1], B[j][1]);
                if (hi > lo) res.Add(new[] { lo, hi });
                if (A[i][1] < B[j][1]) i++; else j++;
            }
            return res;
        }

        public static List<double[]> BandIntervals(List<V2[]> polys, double ha, double hb)
        {
            const double eps = 0.01;
            return Intersect(IntervalsAt(polys, ha + eps), IntervalsAt(polys, hb - eps));
        }

        public static List<double> VertexHeights(List<V2[]> polys)
        {
            var set = new SortedSet<double>();
            foreach (var poly in polys) foreach (var p in poly) set.Add(p.Y);
            return new List<double>(set);
        }

        public static double SignedArea(V2[] poly)
        {
            double a = 0;
            int n = poly.Length;
            for (int i = 0; i < n; i++)
            {
                var p = poly[i];
                var q = poly[i == n - 1 ? 0 : i + 1];
                a += p.X * q.Y - q.X * p.Y;
            }
            return 0.5 * a;
        }

        public static bool InsidePoly(V2[] poly, V2 pt)
        {
            bool inside = false;
            int n = poly.Length;
            for (int i = 0; i < n; i++)
            {
                var a = poly[i];
                var b = poly[i == n - 1 ? 0 : i + 1];
                if (((a.Y > pt.Y) != (b.Y > pt.Y)) &&
                    (pt.X < a.X + (pt.Y - a.Y) * (b.X - a.X) / (b.Y - a.Y))) inside = !inside;
            }
            return inside;
        }

        public static bool IsHole(List<V2[]> polys, int i)
        {
            int cnt = 0;
            var pt = polys[i][0];
            for (int j = 0; j < polys.Count; j++) if (j != i && InsidePoly(polys[j], pt)) cnt++;
            return cnt % 2 == 1;
        }

        public static List<double> BandCuts(List<double> ys, double ha, double hb)
        {
            var res = new List<double> { ha };
            foreach (var y in ys) if (y > ha && y < hb) res.Add(y);
            res.Add(hb);
            return res;
        }
    }

    // --------------------------------------------------------------- Atlas
    internal class Atlas
    {
        public double[][] Stretchers, Headers; // cells: u0, v0, u1, v1, aspect

        public static double[][] Cells(double[] flat)
        {
            int n = flat == null ? 0 : flat.Length / 5;
            var res = new double[n][];
            for (int i = 0; i < n; i++) res[i] = new[] { flat[5 * i], flat[5 * i + 1], flat[5 * i + 2], flat[5 * i + 3], flat[5 * i + 4] };
            return res;
        }

        // Port of BrickGenAtlasLib.mapBrick (in place on u, v arrays).
        public void MapBrick(double[] us, double[] vs, double rx, double ry, double rz, Unit unit, double aspect, bool allowFlip, bool allowRotate)
        {
            var pool = ((unit == Unit.K || unit == Unit.KM) && Headers.Length > 0) ? Headers
                : (Stretchers.Length > 0 ? Stretchers : Headers);
            int n = pool.Length;
            if (n == 0) return;
            int i0 = Math.Min(n, 1 + (int)Math.Floor(rx * n));
            var cell = pool[i0 - 1];
            if (cell[4] < 0.8 * aspect)
            {
                var best = cell;
                int tries = Math.Min(n, 40);
                int k = 1;
                while (k < tries && cell[4] < 0.8 * aspect)
                {
                    var c2 = pool[(int)((i0 - 1 + (long)k * 7919) % n)];
                    if (c2[4] > best[4]) best = c2;
                    if (c2[4] >= 0.8 * aspect) cell = c2;
                    k++;
                }
                if (cell[4] < 0.8 * aspect) cell = best;
            }
            double u0 = cell[0], v0 = cell[1], du = cell[2] - cell[0], dv = cell[3] - cell[1];
            if (cell[4] > aspect)
            {
                double f = aspect / cell[4];
                u0 += 0.5 * du * (1.0 - f);
                du *= f;
            }
            else
            {
                double f = cell[4] / aspect;
                v0 += 0.5 * dv * (1.0 - f);
                dv *= f;
            }
            bool flipU = allowFlip && ry >= 0.5;
            bool rot = allowRotate && rz >= 0.5;
            for (int i = 0; i < us.Length; i++)
            {
                double u = us[i], v = vs[i];
                if (flipU) u = 1.0 - u;
                if (rot) { u = 1.0 - u; v = 1.0 - v; }
                us[i] = u0 + u * du;
                vs[i] = v0 + v * dv;
            }
        }
    }

    // -------------------------------------------------------------- Builder
    public static class Builder
    {
        const int SG_FRONT = 1, SG_SIDES = 2, SG_MORTAR = 4;
        const double MIN_PIECE = 1.0;

        static readonly int[] BrickFaces;   // 18 x 3, 1-based offsets
        static readonly int[] BrickSmooth;  // 18

        static Builder()
        {
            var quads = new List<int[]> { new[] { 1, 2, 3, 4, SG_FRONT } };
            for (int k = 1; k <= 4; k++)
            {
                int kn = k == 4 ? 1 : k + 1;
                quads.Add(new[] { kn, k, 4 + k, 4 + kn, SG_SIDES });
                quads.Add(new[] { 4 + kn, 4 + k, 8 + k, 8 + kn, SG_SIDES });
            }
            var f = new List<int>();
            var s = new List<int>();
            foreach (var q in quads)
            {
                f.AddRange(new[] { q[0], q[1], q[2], q[0], q[2], q[3] });
                s.Add(q[4]); s.Add(q[4]);
            }
            BrickFaces = f.ToArray();
            BrickSmooth = s.ToArray();
        }

        class Buf
        {
            public List<float> V = new List<float>(1 << 20);
            public List<int> F = new List<int>(1 << 20);
            public List<int> Mat = new List<int>(1 << 18);
            public List<int> Sm = new List<int>(1 << 18);
            public List<float> T1 = new List<float>(1 << 19);
            public List<float> T2 = new List<float>(1 << 19);
            public int Bricks;
            public int VertCount { get { return V.Count / 3; } }
        }

        // pt * tm for a 3ds Max matrix3 given as 12 values (row1..row4)
        static void AddVert(Buf b, double[] m, double x, double y, double z)
        {
            b.V.Add((float)(x * m[0] + y * m[3] + z * m[6] + m[9]));
            b.V.Add((float)(x * m[1] + y * m[4] + z * m[7] + m[10]));
            b.V.Add((float)(x * m[2] + y * m[5] + z * m[8] + m[11]));
        }

        // a * b (apply a, then b), both 12-value matrix3
        static double[] Mul(double[] a, double[] b)
        {
            var r = new double[12];
            for (int row = 0; row < 4; row++)
            {
                double x = a[3 * row], y = a[3 * row + 1], z = a[3 * row + 2];
                double w = row == 3 ? 1 : 0;
                for (int col = 0; col < 3; col++)
                    r[3 * row + col] = x * b[col] + y * b[3 + col] + z * b[6 + col] + w * b[9 + col];
            }
            return r;
        }

        /// <summary>
        /// Builds the facade: region fill + reveals.
        /// polyXY: x, y pairs (wall mm, bounding box from 0,0); polyCounts:
        /// number of points per polygon; tm: 12 values (wall mm -> object space);
        /// stretchers/headers: atlas cells (u0, v0, u1, v1, aspect) or null.
        /// </summary>
        public static Result Build(Params p, double[] polyXY, int[] polyCounts, double[] tm, double[] stretchers, double[] headers)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var polys = new List<V2[]>();
            int at = 0;
            foreach (int cnt in polyCounts)
            {
                var poly = new V2[cnt];
                for (int i = 0; i < cnt; i++) { poly[i] = new V2(polyXY[at], polyXY[at + 1]); at += 2; }
                if (cnt >= 3) polys.Add(poly);
            }
            Atlas atlas = null;
            if ((stretchers != null && stretchers.Length >= 5) || (headers != null && headers.Length >= 5))
                atlas = new Atlas { Stretchers = Atlas.Cells(stretchers), Headers = Atlas.Cells(headers) };

            var buf = new Buf();
            var q = p.Clone();
            q.Tm = tm;
            if (polys.Count > 0)
            {
                BuildRegion(buf, q, polys, atlas);
                BuildReveals(buf, p.Clone(), tm, polys, atlas);
            }
            var res = new Result
            {
                Verts = buf.V.ToArray(), Faces = buf.F.ToArray(), MatIDs = buf.Mat.ToArray(),
                Smooth = buf.Sm.ToArray(), UV1 = buf.T1.ToArray(), UV2 = buf.T2.ToArray(),
                BrickCount = buf.Bricks
            };
            res.Milliseconds = sw.Elapsed.TotalMilliseconds;
            return res;
        }

        static void Sanitize(Params p)
        {
            p.BrickL = Math.Max(1, p.BrickL);
            p.BrickB = Math.Max(1, p.BrickB);
            p.BrickH = Math.Max(1, p.BrickH);
            p.BedJoint = Math.Max(0, p.BedJoint);
            p.HeadJoint = Math.Max(0, p.HeadJoint);
        }

        static void AddBrick(Buf buf, Params p, Atlas atlas, long idx, double x0, double x1, double z0, double z1,
            double nomX0, double nomL, double nomZ0, bool clipL, bool clipR, bool clipT, bool clipB, Unit unit)
        {
            long key = Rng.BrickKey(p.Seed + (long)p.SegIndex * 7919, idx);
            bool jitter = !p.PreviewMode;
            double r1x = 0, r1y = 0, r1z = 0;
            if (jitter) Rng.Sym3(key, 1, out r1x, out r1y, out r1z);
            double r2x, r2y, r2z;
            Rng.U01x3(key, 2, out r2x, out r2y, out r2z);

            // 1. size jitter
            if (jitter && p.SizeJitter > 0)
            {
                double dL = 0.5 * p.SizeJitter * r1x, dH = 0.5 * p.SizeJitter * r1y;
                if (!clipL) x0 -= dL;
                if (!clipR) x1 += dL;
                if (!clipB) z0 = Math.Max(0.0, z0 - dH);
                if (!clipT) z1 += dH;
            }

            // 2. chamfer
            double w = x1 - x0, h = z1 - z0;
            double c = 0;
            if (jitter) c = p.Chamfer * (1.0 + p.ChamferJitter * r1z);
            c = Math.Max(0.0, Math.Min(c, 0.5 * Math.Min(w, h) - 0.05));
            double cL = clipL ? 0 : c, cR = clipR ? 0 : c, cT = clipT ? 0 : c, cB = clipB ? 0 : c;
            double depth = p.JointRecess + c + 3.0 + p.DepthJitter;

            var px = new double[12]; var py = new double[12]; var pz = new double[12];
            void Set(int i, double x, double y, double z) { px[i] = x; py[i] = y; pz[i] = z; }
            Set(0, x0 + cL, 0, z0 + cB); Set(1, x1 - cR, 0, z0 + cB); Set(2, x1 - cR, 0, z1 - cT); Set(3, x0 + cL, 0, z1 - cT);
            Set(4, x0, c, z0); Set(5, x1, c, z0); Set(6, x1, c, z1); Set(7, x0, c, z1);

            // 3. corner jitter
            if (jitter && p.CornerJitter > 0)
            {
                double cj = p.CornerJitter;
                for (int v = 1; v <= 8; v++)
                {
                    int k = v > 4 ? v - 4 : v;
                    bool onLeft = k == 1 || k == 4, onTop = k == 3 || k == 4;
                    bool sawnX = onLeft ? clipL : clipR, sawnZ = onTop ? clipT : clipB;
                    double jx, jy, jz;
                    Rng.Sym3(key, 10 + v, out jx, out jy, out jz);
                    px[v - 1] += sawnX ? 0 : cj * jx;
                    py[v - 1] += 0.3 * cj * jz;
                    pz[v - 1] += sawnZ ? 0 : cj * jy;
                }
            }
            for (int v = 4; v < 8; v++) Set(v + 4, px[v], depth, pz[v]);

            // 3b. broken corner (channel 4)
            if (jitter && p.ChipChance > 0 && p.ChipSize > 0)
            {
                double r4x, r4y, r4z;
                Rng.U01x3(key, 4, out r4x, out r4y, out r4z);
                if (r4x < p.ChipChance)
                {
                    int k = 1 + (int)Math.Floor(r4y * 4.0);
                    if (k > 4) k = 4;
                    bool onLeft = k == 1 || k == 4, onTop = k == 3 || k == 4;
                    bool sawn = (onLeft ? clipL : clipR) || (onTop ? clipT : clipB);
                    if (!sawn)
                    {
                        double sz = Math.Min(p.ChipSize * (0.5 + r4z), 0.3 * Math.Min(x1 - x0, z1 - z0));
                        double sx = onLeft ? 1 : -1, sy = onTop ? -1 : 1;
                        px[k - 1] += sx * sz; py[k - 1] += 0.6 * sz; pz[k - 1] += sy * sz;
                        px[k + 3] += sx * sz * 0.8; py[k + 3] += 0.3 * sz; pz[k + 3] += sy * sz * 0.8;
                    }
                }
            }

            // UV channel 1 (box unfold for the sides), then atlas
            double invL = 1.0 / nomL, invH = 1.0 / p.BrickH;
            var us = new double[12]; var vs = new double[12];
            for (int i = 0; i < 12; i++) { us[i] = (px[i] - nomX0) * invL; vs[i] = (pz[i] - nomZ0) * invH; }
            for (int v = 9; v <= 12; v++)
            {
                int k = v - 8;
                double sx = (k == 1 || k == 4) ? 1 : -1, sz = (k == 1 || k == 2) ? 1 : -1;
                us[v - 1] += sx * depth * invL;
                vs[v - 1] += sz * depth * invH;
            }
            if (atlas != null)
            {
                double r3x, r3y, r3z;
                Rng.U01x3(key, 3, out r3x, out r3y, out r3z);
                atlas.MapBrick(us, vs, r3x, r3y, r3z, unit, nomL / p.BrickH, p.AtlasFlip, p.AtlasRotate);
            }

            // 4. depth jitter
            if (jitter && p.DepthJitter > 0)
            {
                double dy = p.DepthJitter * (2.0 * r2x - 1.0);
                for (int i = 0; i < 12; i++) py[i] += dy;
            }

            // 5. rotation (degrees, like MAXScript cos/sin)
            if (jitter && p.RotJitter > 0 && !(clipL || clipR || clipT || clipB))
            {
                double a = p.RotJitter * (2.0 * r2y - 1.0) * Math.PI / 180.0;
                double ca = Math.Cos(a), sa = Math.Sin(a);
                double cx = 0.5 * (x0 + x1), cz = 0.5 * (z0 + z1);
                for (int i = 0; i < 12; i++)
                {
                    double dx = px[i] - cx, dz = pz[i] - cz;
                    px[i] = cx + dx * ca - dz * sa;
                    pz[i] = cz + dx * sa + dz * ca;
                }
            }

            int n = Math.Max(1, p.MatIdCount);
            int mat = Math.Min(n, 1 + (int)Math.Floor(r2z * n));

            int b = buf.VertCount;
            for (int i = 0; i < 12; i++)
            {
                AddVert(buf, p.Tm, px[i], py[i], pz[i]);
                buf.T1.Add((float)us[i]); buf.T1.Add((float)vs[i]);
                buf.T2.Add((float)((px[i] + p.UOffset) * 0.001)); buf.T2.Add((float)(pz[i] * 0.001));
            }
            for (int f = 0; f < 18; f++)
            {
                buf.F.Add(BrickFaces[3 * f] + b); buf.F.Add(BrickFaces[3 * f + 1] + b); buf.F.Add(BrickFaces[3 * f + 2] + b);
                buf.Sm.Add(BrickSmooth[f]);
                buf.Mat.Add(mat);
            }
            buf.Bricks++;
        }

        static void AddMortarRect(Buf buf, Params p, double x0, double x1, double za, double zb)
        {
            double y = p.JointRecess;
            int b = buf.VertCount;
            double[,] pts = { { x0, za }, { x1, za }, { x1, zb }, { x0, zb } };
            for (int i = 0; i < 4; i++)
            {
                AddVert(buf, p.Tm, pts[i, 0], y, pts[i, 1]);
                float u = (float)((pts[i, 0] + p.UOffset) * 0.001), v = (float)(pts[i, 1] * 0.001);
                buf.T1.Add(u); buf.T1.Add(v);
                buf.T2.Add(u); buf.T2.Add(v);
            }
            buf.F.Add(b + 1); buf.F.Add(b + 2); buf.F.Add(b + 3);
            buf.F.Add(b + 1); buf.F.Add(b + 3); buf.F.Add(b + 4);
            buf.Mat.Add(p.MortarMatId); buf.Mat.Add(p.MortarMatId);
            buf.Sm.Add(SG_MORTAR); buf.Sm.Add(SG_MORTAR);
        }

        static void BuildRegion(Buf buf, Params p, List<V2[]> polys, Atlas atlas)
        {
            Sanitize(p);
            double maxX = 0, maxY = 0;
            foreach (var poly in polys) foreach (var pt in poly) { if (pt.X > maxX) maxX = pt.X; if (pt.Y > maxY) maxY = pt.Y; }
            if (maxX < MIN_PIECE || maxY < MIN_PIECE) return;
            p.WallLength = maxX; p.WallHeight = maxY;

            var ys = Region.VertexHeights(polys);
            var bond = p.BondOverride ?? Bonds.Get(p.BondType);
            double pitchZ = p.BrickH + p.BedJoint;
            int nCourses = (int)Math.Ceiling(maxY / pitchZ);
            var offsets = Bonds.CourseOffsets(bond, nCourses, p.Seed, p.BrickL, p.BrickB, p.HeadJoint, p.WildMinOverlap);

            for (int c = 0; c < nCourses; c++)
            {
                double z0 = c * pitchZ, zTop = z0 + p.BrickH;
                var cdef = Bonds.CourseDef(bond, c);
                var pieces = Bonds.LayoutCourse(cdef.Units, offsets[c] + p.StartOffset, maxX, p.HeadJoint, p.BrickL, p.BrickB);

                var cuts = Region.BandCuts(ys, z0, Math.Min(zTop, maxY));
                for (int i = 0; i + 1 < cuts.Count; i++)
                {
                    double ha = cuts[i], hb = cuts[i + 1];
                    if (hb - ha < MIN_PIECE) continue;
                    foreach (var iv in Region.BandIntervals(polys, ha, hb))
                    {
                        foreach (var pc in pieces)
                        {
                            double x0 = Math.Max(pc.X0, iv[0]), x1 = Math.Min(pc.X1, iv[1]);
                            if (x1 - x0 >= MIN_PIECE)
                                AddBrick(buf, p, atlas, (long)c * 65536 + pc.K, x0, x1, ha, hb, pc.X0, pc.X1 - pc.X0, z0,
                                    pc.X0 < iv[0], pc.X1 > iv[1], hb < zTop - 0.001, ha > z0 + 0.001, pc.U);
                        }
                    }
                }

                if (p.MortarEnabled)
                {
                    var mcuts = Region.BandCuts(ys, z0, Math.Min(z0 + pitchZ, maxY));
                    for (int i = 0; i + 1 < mcuts.Count; i++)
                    {
                        double ha = mcuts[i], hb = mcuts[i + 1];
                        if (hb - ha > 0.01)
                            foreach (var iv in Region.BandIntervals(polys, ha, hb)) AddMortarRect(buf, p, iv[0], iv[1], ha, hb);
                    }
                }
            }
        }

        static void BuildReveals(Buf buf, Params p, double[] tm, List<V2[]> polys, Atlas atlas)
        {
            Sanitize(p);
            double T = p.RevealDepth;
            if (T < MIN_PIECE) return;
            double W = 0;
            foreach (var poly in polys) foreach (var pt in poly) if (pt.X > W) W = pt.X;
            int strip = 0;

            for (int pIdx = 0; pIdx < polys.Count; pIdx++)
            {
                var poly = polys[pIdx];
                bool hole = Region.IsHole(polys, pIdx);
                if (!hole && !p.RevealOuter) continue;
                double sgn = Region.SignedArea(poly) > 0 ? 1 : -1;
                if (!hole) sgn = -sgn;
                int n = poly.Length;
                for (int i = 0; i < n; i++)
                {
                    var a = poly[i];
                    var b = poly[i == n - 1 ? 0 : i + 1];
                    double dx = b.X - a.X, dy = b.Y - a.Y;
                    double nx = -dy * sgn, ny = dx * sgn;
                    bool jamb = Math.Abs(dx) <= 0.02 * Math.Abs(dy) && Math.Abs(dy) >= MIN_PIECE;
                    bool horiz = !jamb && Math.Abs(dy) <= 0.02 * Math.Abs(dx) && Math.Abs(dx) >= MIN_PIECE;
                    if (!jamb && !horiz) continue;

                    double[] stm;
                    V2[] rect;
                    double offs = p.StartOffset;
                    Bond hBond = null;
                    if (jamb)
                    {
                        double ex = 0.5 * (a.X + b.X);
                        double y1 = Math.Min(a.Y, b.Y), y2 = Math.Max(a.Y, b.Y);
                        if (nx > 0)
                        {
                            stm = new double[] { 0, 1, 0, -1, 0, 0, 0, 0, 1, ex, 0, 0 };
                            offs = p.RevealOffset;
                        }
                        else
                        {
                            stm = new double[] { 0, -1, 0, 1, 0, 0, 0, 0, 1, ex, T, 0 };
                            offs = T - p.RevealOffset - p.BrickL;
                        }
                        rect = new[] { new V2(0, y1), new V2(T, y1), new V2(T, y2), new V2(0, y2) };
                    }
                    else
                    {
                        double ey = 0.5 * (a.Y + b.Y);
                        double x1 = Math.Min(a.X, b.X), x2 = Math.Max(a.X, b.X);
                        bool up = ny > 0;
                        double pitchZ = p.BrickH + p.BedJoint;
                        int c = up ? (int)Math.Ceiling(ey / pitchZ) - 1 : (int)Math.Floor((ey - p.BrickH) / pitchZ) + 1;
                        c = Math.Max(0, c);
                        var fbond = Bonds.Get(p.BondType);
                        var fOffs = Bonds.CourseOffsets(fbond, c + 1, p.Seed, p.BrickL, p.BrickB, p.HeadJoint, p.WildMinOverlap);
                        var units = Bonds.CourseDef(fbond, c).Units;
                        double o = fOffs[c] + p.StartOffset;
                        if (up)
                        {
                            stm = new double[] { 1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, ey };
                            rect = new[] { new V2(x1, 0), new V2(x2, 0), new V2(x2, T), new V2(x1, T) };
                        }
                        else
                        {
                            stm = new double[] { -1, 0, 0, 0, 0, 1, 0, 1, 0, W, 0, ey };
                            rect = new[] { new V2(W - x2, 0), new V2(W - x1, 0), new V2(W - x1, T), new V2(W - x2, T) };
                            double period = 0;
                            foreach (var u in units) period += Bonds.UnitPitch(u, p.BrickL, p.BrickB, p.HeadJoint);
                            var rev = (Unit[])units.Clone();
                            Array.Reverse(rev);
                            units = rev;
                            o = W - o - period + p.HeadJoint;
                        }
                        offs = o;
                        hBond = new Bond(false, new Course(0, 0, 0, units), new Course(0.5, 0, 0.5, units));
                    }
                    // 0.5 mm towards the opening
                    stm[9] -= 0.5 * stm[3]; stm[10] -= 0.5 * stm[4]; stm[11] -= 0.5 * stm[5];
                    strip++;
                    var q = p.Clone();
                    if (hBond != null)
                    {
                        q.BondOverride = hBond;
                        q.BrickH = p.BrickB;
                        q.BedJoint = p.HeadJoint;
                    }
                    q.Tm = Mul(stm, tm);
                    q.SegIndex = p.SegIndex + 1000 + strip;
                    q.UOffset = 0;
                    q.StartOffset = offs;
                    BuildRegion(buf, q, new List<V2[]> { rect }, atlas);
                }
            }
        }
    }
}
