-- BrickGen_Region.ms
-- 2D region helpers for filling a facade outline (with openings) with bricks.
-- A region is an array of closed polygons (arrays of point3, only x/y used,
-- in wall mm: x along the facade, y up). Inside = even-odd rule, so inner
-- polygons (windows, doors) are holes.

struct BrickGenRegionStruct
(
	-- Inside intervals #(#(x0, x1), ...) on the horizontal line at height y.
	fn intervalsAt polys y =
	(
		local xs = #()
		for poly in polys do
		(
			local n = poly.count
			for i = 1 to n do
			(
				local a = poly[i]
				local b = poly[if i == n then 1 else i + 1]
				if (a.y <= y and y < b.y) or (b.y <= y and y < a.y) do
					append xs (a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
			)
		)
		sort xs
		for i = 1 to xs.count - 1 by 2 collect #(xs[i], xs[i + 1])
	),

	-- Intersection of two sorted interval lists.
	fn intersect A B =
	(
		local res = #()
		local i = 1
		local j = 1
		while i <= A.count and j <= B.count do
		(
			local lo = amax A[i][1] B[j][1]
			local hi = amin A[i][2] B[j][2]
			if hi > lo do append res #(lo, hi)
			if A[i][2] < B[j][2] then i += 1 else j += 1
		)
		res
	),

	-- Inside intervals for the whole band [ha, hb]: inside at both its bottom
	-- and top. Exact when no polygon vertex lies strictly between ha and hb.
	fn bandIntervals polys ha hb =
	(
		local eps = 0.01
		intersect (intervalsAt polys (ha + eps)) (intervalsAt polys (hb - eps))
	),

	-- Sorted unique vertex heights.
	fn vertexHeights polys =
	(
		local ys = #()
		for poly in polys do for pt in poly do append ys pt.y
		sort (makeUniqueArray ys)
	),

	-- Signed area (> 0 = counter-clockwise, y up).
	fn signedArea poly =
	(
		local a = 0.0
		local n = poly.count
		for i = 1 to n do
		(
			local p = poly[i]
			local q = poly[if i == n then 1 else i + 1]
			a += p.x * q.y - q.x * p.y
		)
		0.5 * a
	),

	-- Even-odd point-in-polygon test.
	fn insidePoly poly pt =
	(
		local inside = false
		local n = poly.count
		for i = 1 to n do
		(
			local a = poly[i]
			local b = poly[if i == n then 1 else i + 1]
			if ((a.y > pt.y) != (b.y > pt.y)) and \
				(pt.x < a.x + (pt.y - a.y) * (b.x - a.x) / (b.y - a.y)) do inside = not inside
		)
		inside
	),

	-- A polygon is an opening when it lies inside an odd number of the others.
	fn isHole polys i =
	(
		local cnt = 0
		local pt = polys[i][1]
		for j = 1 to polys.count where j != i do if (insidePoly polys[j] pt) do cnt += 1
		(mod cnt 2) == 1
	),

	-- Cut heights for a band: ha, every vertex height strictly inside, hb.
	fn bandCuts ys ha hb =
	(
		#(ha) + (for y in ys where y > ha and y < hb collect y) + #(hb)
	)
)

global BrickGenRegion = BrickGenRegionStruct()
