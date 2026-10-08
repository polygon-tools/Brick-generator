-- BrickGen_Mesh.ms
-- Wall geometry (PLAN.md §8): bricks, chamfer, imperfections, mortar plane.
--
-- Wall-local axes: X along the wall, Z up, Y into the wall. The brick face is
-- at y = 0 and faces -Y. Origin = bottom-left of the wall front.
-- Everything is computed in mm and scaled to system units when appended.
--
-- Per brick: 12 vertices, 9 quads = 18 triangles, no back face, every brick a
-- separate element. Vertex layout (k = 1..4: bottom-left, bottom-right,
-- top-right, top-left):
--   F1..F4  front face (inset by the chamfer)          y = 0
--   O1..O4  outer rim (end of the chamfer)              y = chamfer
--   B1..B4  back end of the sides, under the mortar     y = depth

struct BrickGenWallParams
(
	-- all lengths in mm
	wallLength = 3000.0, wallHeight = 2500.0, seed = 12345,
	brickL = 210.0, brickB = 100.0, brickH = 50.0,
	bedJoint = 12.0, headJoint = 12.0, jointRecess = 5.0, mortarEnabled = true,
	bondType = 1, startOffset = 0.0, wildMinOverlap = 0.25,
	chamfer = 2.0, chamferJitter = 0.3, cornerJitter = 1.0, depthJitter = 1.5,
	rotJitter = 0.3, sizeJitter = 1.0,
	matIdCount = 5, mortarMatId = 100,
	previewMode = false,
	unitScale = 1.0, -- system units per mm
	-- placement of this wall piece (set by the modifier per spline segment):
	tm = undefined,   -- matrix3 wall-local mm -> object space; undefined = scale only
	uOffset = 0.0,    -- mm along the path before this piece (UV channel 2)
	segIndex = 0      -- piece number, varies the randomness per segment
)

struct BrickGenMeshBuffer
(
	verts = #(), faces = #(), matIDs = #(), smooth = #(), uv1 = #(), uv2 = #(),
	brickCount = 0
)

struct BrickGenMeshStruct
(
	SG_FRONT = 1, SG_SIDES = 2, SG_MORTAR = 4,
	MIN_PIECE = 1.0, -- mm; thinner slivers at the wall edge are skipped

	-- Quad a-b-c-d, counter-clockwise seen from outside. Triangles (a,b,c) and
	-- (a,c,d); the shared diagonal a-c is hidden by autoEdge in applyToMesh.
	fn addQuad buf a b c d sg mat =
	(
		append buf.faces [a, b, c]
		append buf.faces [a, c, d]
		append buf.matIDs mat
		append buf.matIDs mat
		append buf.smooth sg
		append buf.smooth sg
	),

	-- Faces of one brick as 1-based offsets from the vertex count before it, built once:
	-- front, then per side k the chamfer quad and the side quad.
	BRICK_FACES = #(),
	BRICK_SMOOTH = #(),

	fn initBrickTemplate =
	(
		-- quads as #(a, b, c, d, smoothing group)
		local quads = #(#(1, 2, 3, 4, SG_FRONT))
		for k = 1 to 4 do
		(
			local kn = if k == 4 then 1 else k + 1
			append quads #(kn, k, 4 + k, 4 + kn, SG_SIDES)
			append quads #(4 + kn, 4 + k, 8 + k, 8 + kn, SG_SIDES)
		)
		local faces = #()
		local smooth = #()
		for q in quads do
		(
			append faces [q[1], q[2], q[3]]
			append faces [q[1], q[3], q[4]]
			append smooth q[5]
			append smooth q[5]
		)
		BRICK_FACES = faces
		BRICK_SMOOTH = smooth
		faces.count
	),

	-- x0..x1 / z0..z1: (clipped) brick extent in mm.
	-- nomX0 / nomL: unclipped start and length (for UVs).
	-- clipL / clipR / clipT / clipB: that edge is sawn (wall edge or opening).
	--
	-- RNG channels (each gives three values, see BrickGenRNG.u01x3):
	--   1: size L, size H, chamfer      2: depth, rotation, material ID
	--   11..18: corner jitter x, z, y for front vertex 1..8
	fn addBrick buf p idx x0 x1 z0 z1 nomX0 nomL nomZ0 clipL clipR clipT clipB:false =
	(
		local R = BrickGenRNG
		local key = R.brickKey (p.seed + p.segIndex * 7919) idx
		local jitter = not p.previewMode
		local r1 = if jitter then R.sym3 key 1 else [0.0, 0.0, 0.0]
		local r2 = R.u01x3 key 2

		-- 1. size jitter (only on free edges)
		if jitter and p.sizeJitter > 0.0 do
		(
			local dL = 0.5 * p.sizeJitter * r1.x
			local dH = 0.5 * p.sizeJitter * r1.y
			if not clipL do x0 -= dL
			if not clipR do x1 += dL
			if not clipB do z0 = amax 0.0 (z0 - dH)
			if not clipT do z1 += dH
		)

		-- 2. chamfer with jitter, clamped to half the smallest side
		local w = x1 - x0
		local h = z1 - z0
		local c = 0.0
		if jitter do c = p.chamfer * (1.0 + p.chamferJitter * r1.z)
		c = amax 0.0 (amin c (0.5 * (amin w h) - 0.05))
		local cL = if clipL then 0.0 else c
		local cR = if clipR then 0.0 else c
		local cT = if clipT then 0.0 else c
		local cB = if clipB then 0.0 else c
		local depth = p.jointRecess + c + 3.0 + p.depthJitter

		local pts = #(
			[x0 + cL, 0.0, z0 + cB], [x1 - cR, 0.0, z0 + cB], [x1 - cR, 0.0, z1 - cT], [x0 + cL, 0.0, z1 - cT],
			[x0, c, z0], [x1, c, z0], [x1, c, z1], [x0, c, z1]
		)

		-- 3. corner jitter on the 8 front vertices; sawn edges stay straight
		if jitter and p.cornerJitter > 0.0 do
		(
			local cj = p.cornerJitter
			for v = 1 to 8 do
			(
				local k = if v > 4 then v - 4 else v
				local onLeft = (k == 1 or k == 4)
				local onTop = (k == 3 or k == 4)
				local sawnX = if onLeft then clipL else clipR
				local sawnZ = if onTop then clipT else clipB
				local j = R.sym3 key (10 + v)
				pts[v] = pts[v] + [(if sawnX then 0.0 else cj * j.x), 0.3 * cj * j.z, (if sawnZ then 0.0 else cj * j.y)]
			)
		)

		-- back vertices follow the outer rim
		for v = 5 to 8 do append pts [pts[v].x, depth, pts[v].z]

		-- channel 1 before depth/rotation, so the texture moves with the brick
		local invL = 1.0 / nomL
		local invH = 1.0 / p.brickH
		local uv1 = for pt in pts collect [(pt.x - nomX0) * invL, (pt.z - nomZ0) * invH, 0.0]

		-- 4. depth jitter
		if jitter and p.depthJitter > 0.0 do
		(
			local dyv = [0.0, p.depthJitter * (2.0 * r2.x - 1.0), 0.0]
			for i = 1 to 12 do pts[i] = pts[i] + dyv
		)

		-- 5. rotation around Y through the brick centre (not for sawn bricks)
		if jitter and p.rotJitter > 0.0 and not (clipL or clipR or clipT or clipB) do
		(
			local a = p.rotJitter * (2.0 * r2.y - 1.0)
			local ca = cos a
			local sa = sin a
			local cx = 0.5 * (x0 + x1)
			local cz = 0.5 * (z0 + z1)
			for i = 1 to 12 do
			(
				local dx = pts[i].x - cx
				local dz = pts[i].z - cz
				pts[i] = [cx + dx * ca - dz * sa, pts[i].y, cz + dx * sa + dz * ca]
			)
		)

		local n = amax 1 p.matIdCount
		local mat = amin n (1 + ((floor (r2.z * n)) as integer))

		local base = buf.verts.count
		local tm = p.tm
		local u0 = p.uOffset
		for i = 1 to 12 do
		(
			local pt = pts[i]
			append buf.verts (pt * tm)
			append buf.uv1 uv1[i]
			append buf.uv2 [(pt.x + u0) * 0.001, pt.z * 0.001, 0.0]
		)

		local bv = [base, base, base]
		for f = 1 to 18 do
		(
			append buf.faces (BRICK_FACES[f] + bv)
			append buf.smooth BRICK_SMOOTH[f]
			append buf.matIDs mat
		)
		buf.brickCount += 1
	),

	fn addMortar buf p =
	(
		local y = p.jointRecess
		local W = p.wallLength
		local H = p.wallHeight
		local pts = #([0.0, y, 0.0], [W, y, 0.0], [W, y, H], [0.0, y, H])
		local base = buf.verts.count
		for pt in pts do
		(
			local uv = BrickGenUV.planarUV (pt.x + p.uOffset) pt.z
			append buf.verts (pt * p.tm)
			append buf.uv1 uv
			append buf.uv2 uv
		)
		addQuad buf (base + 1) (base + 2) (base + 3) (base + 4) SG_MORTAR p.mortarMatId
	),

	fn sanitize p =
	(
		if BRICK_FACES.count != 18 do initBrickTemplate()
		if p.tm == undefined do p.tm = scaleMatrix [p.unitScale, p.unitScale, p.unitScale]
		p.brickL = amax 1.0 p.brickL
		p.brickB = amax 1.0 p.brickB
		p.brickH = amax 1.0 p.brickH
		p.bedJoint = amax 0.0 p.bedJoint
		p.headJoint = amax 0.0 p.headJoint
		p
	),

	-- Mortar rectangle [x0, x1] x [za, zb] at the joint recess.
	fn addMortarRect buf p x0 x1 za zb =
	(
		local y = p.jointRecess
		local base = buf.verts.count
		for pt in #([x0, y, za], [x1, y, za], [x1, y, zb], [x0, y, zb]) do
		(
			local uv = BrickGenUV.planarUV (pt.x + p.uOffset) pt.z
			append buf.verts (pt * p.tm)
			append buf.uv1 uv
			append buf.uv2 uv
		)
		addQuad buf (base + 1) (base + 2) (base + 3) (base + 4) SG_MORTAR p.mortarMatId
	),

	-- Full brick as a box [x0,x1] x [y0,y1] x [z0,z1] (wall mm) with all 12
	-- edges chamfered: used where a brick turns a corner (front face on the
	-- facade AND an end/side face in the reveal). 24 vertices, 44 triangles.
	fn addBoxBrick buf p idx x0 x1 y0 y1 z0 z1 =
	(
		local R = BrickGenRNG
		local key = R.brickKey (p.seed + p.segIndex * 7919 + 4099) idx
		local c = if p.previewMode then 0.0 else p.chamfer
		c = amax 0.0 (amin c (0.45 * (amin (x1 - x0) (amin (y1 - y0) (z1 - z0)))))
		local ctr = [0.5 * (x0 + x1), 0.5 * (y0 + y1), 0.5 * (z0 + z1)]

		-- vertex (axis a on whose face it lies, box corner ci) -> local index a*8 + ci + 1
		local loc = #()
		for a = 0 to 2 do
			for ci = 0 to 7 do
			(
				local sx = if (bit.and ci 1) != 0 then 1.0 else -1.0
				local sy = if (bit.and ci 2) != 0 then 1.0 else -1.0
				local sz = if (bit.and ci 4) != 0 then 1.0 else -1.0
				local px = (if sx > 0 then x1 else x0) - (if a != 0 then sx * c else 0.0)
				local py = (if sy > 0 then y1 else y0) - (if a != 1 then sy * c else 0.0)
				local pz = (if sz > 0 then z1 else z0) - (if a != 2 then sz * c else 0.0)
				append loc [px, py, pz]
			)
		fn vi a ci = ( a * 8 + ci + 1 )

		-- polygons as local index lists, with smoothing group
		local polys = #()
		local sgs = #()
		-- 6 faces
		for a = 0 to 2 do
			for side = 0 to 1 do
			(
				local b = (mod (a + 1) 3) as integer
				local d = (mod (a + 2) 3) as integer
				local bitA = (2 ^ a) as integer
				local bitB = (2 ^ b) as integer
				local bitD = (2 ^ d) as integer
				local baseC = side * bitA
				append polys #(vi a baseC, vi a (baseC + bitB), vi a (baseC + bitB + bitD), vi a (baseC + bitD))
				append sgs SG_FRONT
			)
		-- 12 edge bevels: edge along axis a, between faces b and d
		for a = 0 to 2 do
		(
			local b = (mod (a + 1) 3) as integer
			local d = (mod (a + 2) 3) as integer
			local bitA = (2 ^ a) as integer
			local bitB = (2 ^ b) as integer
			local bitD = (2 ^ d) as integer
			for sb = 0 to 1 do
				for sd = 0 to 1 do
				(
					local c0 = sb * bitB + sd * bitD
					append polys #(vi b c0, vi b (c0 + bitA), vi d (c0 + bitA), vi d c0)
					append sgs SG_SIDES
				)
		)
		-- 8 corner triangles
		for ci = 0 to 7 do
		(
			append polys #(vi 0 ci, vi 1 ci, vi 2 ci)
			append sgs SG_SIDES
		)

		local r2 = R.u01x3 key 2
		local n = amax 1 p.matIdCount
		local mat = amin n (1 + ((floor (r2.z * n)) as integer))

		local base = buf.verts.count
		for k = 1 to 24 do
		(
			local pt = loc[k]
			local a = (k - 1) / 8
			append buf.verts (pt * p.tm)
			case a of
			(
				0: ( append buf.uv1 [(pt.y - y0) / p.brickL, (pt.z - z0) / p.brickH, 0.0]
				     append buf.uv2 [pt.y * 0.001, pt.z * 0.001, 0.0] )
				1: ( append buf.uv1 [(pt.x - x0) / p.brickL, (pt.z - z0) / p.brickH, 0.0]
				     append buf.uv2 [(pt.x + p.uOffset) * 0.001, pt.z * 0.001, 0.0] )
				default: ( append buf.uv1 [(pt.x - x0) / p.brickL, (pt.y - y0) / p.brickH, 0.0]
				           append buf.uv2 [(pt.x + p.uOffset) * 0.001, pt.y * 0.001, 0.0] )
			)
		)
		-- faces, wound so that the normal points away from the box centre
		for k = 1 to polys.count do
		(
			local q = polys[k]
			local p1 = loc[q[1]]
			local nrm = cross (loc[q[2]] - p1) (loc[q[3]] - p1)
			local fc = [0.0, 0.0, 0.0]
			for v in q do fc += loc[v]
			fc /= q.count
			if (dot nrm (fc - ctr)) < 0.0 do q = for m = q.count to 1 by -1 collect q[m]
			for t = 2 to q.count - 1 do
			(
				append buf.faces [base + q[1], base + q[t], base + q[t + 1]]
				append buf.matIDs mat
				append buf.smooth sgs[k]
			)
		)
		buf.brickCount += 1
	),

	-- Horizontal/vertical edges that get a reveal: openings, plus the outline
	-- when includeOuter. #(#(type, a, b, nx, ny), ...) with type #jamb or
	-- #horizontal and (nx, ny) the side the reveal faces (unnormalised).
	fn revealEdges polys includeOuter =
	(
		local G = BrickGenRegion
		local res = #()
		for pIdx = 1 to polys.count do
		(
			local poly = polys[pIdx]
			local hole = G.isHole polys pIdx
			if hole or includeOuter do
			(
				-- the opening's inside, or the outside of the outline
				local sgn = if (G.signedArea poly) > 0.0 then 1.0 else -1.0
				if not hole do sgn = -sgn
				local n = poly.count
				for i = 1 to n do
				(
					local a = poly[i]
					local b = poly[if i == n then 1 else i + 1]
					local dx = b.x - a.x
					local dy = b.y - a.y
					if (abs dx) <= 0.02 * (abs dy) and (abs dy) >= MIN_PIECE then
						append res #(#jamb, a, b, -dy * sgn, dx * sgn)
					else if (abs dy) <= 0.02 * (abs dx) and (abs dx) >= MIN_PIECE do
						append res #(#horizontal, a, b, -dy * sgn, dx * sgn)
				)
			)
		)
		res
	),

	-- Corner descriptors for the facade: one per jamb, #(xEdge, y1, y2, side)
	-- with side +1 when the masonry ends at xEdge (opening to the right).
	fn facadeCorners polys includeOuter =
	(
		for e in (revealEdges polys includeOuter) where e[1] == #jamb collect
			#(0.5 * (e[2].x + e[3].x), amin e[2].y e[3].y, amax e[2].y e[3].y, (if e[4] > 0.0 then 1 else -1))
	),

	-- Fills a region (closed polygons in wall mm, x along, y up, bounding box
	-- starting at 0,0; inner polygons are openings) with bricks, placed by p.tm.
	-- Per course the band is cut at polygon vertex heights; each piece is
	-- clipped to the inside intervals, so bricks are sawn at every edge.
	--
	-- corners: #(#(xEdge, y1, y2, side), ...) where a brick turns a corner. In
	-- every full course within [y1, y2] the interval ending (side +1) or
	-- starting (side -1) at xEdge is shortened by the corner brick + a head
	-- joint. Even courses: stretcher (L) on the facade, header (B) into the
	-- reveal; odd courses the other way round.
	-- cornerMode #facade also builds the corner bricks; #reveal (the strip in
	-- the reveal, whose x runs into the wall) only leaves room for them.
	fn buildRegionInto buf p polys corners:#() cornerMode:#facade =
	(
		sanitize p
		local G = BrickGenRegion
		local maxX = 0.0
		local maxY = 0.0
		for poly in polys do for pt in poly do
		(
			if pt.x > maxX do maxX = pt.x
			if pt.y > maxY do maxY = pt.y
		)
		if maxX < MIN_PIECE or maxY < MIN_PIECE do return buf
		p.wallLength = maxX
		p.wallHeight = maxY

		local ys = G.vertexHeights polys
		local bond = BrickGenBonds.get p.bondType
		local pitchZ = p.brickH + p.bedJoint
		local nCourses = (ceil (maxY / pitchZ)) as integer
		local offsets = BrickGenBonds.courseOffsets bond nCourses p.seed p.brickL p.brickB p.headJoint p.wildMinOverlap

		for c = 0 to nCourses - 1 do
		(
			local z0 = c * pitchZ
			local zTop = z0 + p.brickH
			local cdef = BrickGenBonds.courseDef bond c
			local pieces = BrickGenBonds.layoutCourse cdef (offsets[c + 1] + p.startOffset) maxX p.headJoint p.brickL p.brickB

			-- corners active in this course (only full-height courses turn a corner)
			local even = (mod c 2) == 0 or not bond.cornerAlternate
			local cw = if even then p.brickL else p.brickB -- along the facade
			local cd = if even then p.brickB else p.brickL -- into the reveal
			local trim = (if cornerMode == #facade then cw else cd) + p.headJoint
			local active = for k = 1 to corners.count where \
				corners[k][2] <= z0 + 0.5 and zTop <= corners[k][3] + 0.5 and zTop <= maxY collect k
			if cornerMode == #facade do
				for k in active do
				(
					local e = corners[k]
					-- 0.5 mm into the opening, flush with the reveal strip (see buildRevealsInto)
					if e[4] > 0 then
						addBoxBrick buf p (c * 65536 + 60000 + k) (e[1] - cw) (e[1] + 0.5) 0.0 cd z0 zTop
					else
						addBoxBrick buf p (c * 65536 + 60000 + k) (e[1] - 0.5) (e[1] + cw) 0.0 cd z0 zTop
				)

			-- bricks
			local cuts = G.bandCuts ys z0 (amin zTop maxY)
			for i = 1 to cuts.count - 1 do
			(
				local ha = cuts[i]
				local hb = cuts[i + 1]
				if (hb - ha) >= MIN_PIECE do
				(
					-- intervals as #(x0, x1, anchoredLeft, anchoredRight)
					local ivs = for iv in (G.bandIntervals polys ha hb) collect #(iv[1], iv[2], false, false)
					for k in active do
					(
						local e = corners[k]
						for iv in ivs do
						(
							if e[4] > 0 and (abs (iv[2] - e[1])) < 0.5 do ( iv[2] -= trim; iv[4] = true )
							if e[4] < 0 and (abs (iv[1] - e[1])) < 0.5 do ( iv[1] += trim; iv[3] = true )
						)
					)
					for ivIdx = 1 to ivs.count where ivs[ivIdx][2] - ivs[ivIdx][1] >= MIN_PIECE do
					(
						local iv = ivs[ivIdx]
						-- next to a corner the bond is set out from that corner; between
						-- two corners from both sides, with the closers in the middle
						local ivPieces = pieces
						local keyBase = 0
						if iv[3] or iv[4] do
						(
							keyBase = 20000 + ivIdx * 512
							local h = p.headJoint
							if iv[3] and iv[4] then
							(
								local mid = 0.5 * (iv[1] + iv[2])
								local lp = for pc in (BrickGenBonds.anchoredCourse cdef iv[1] iv[2] h p.brickL p.brickB true) where pc[2] <= mid collect pc
								local rp = for pc in (BrickGenBonds.anchoredCourse cdef iv[1] iv[2] h p.brickL p.brickB false) where pc[1] >= mid collect #(pc[1], pc[2], pc[3], pc[4] + 256)
								local a0 = if lp.count > 0 then lp[lp.count][2] + h else iv[1]
								local b0 = if rp.count > 0 then rp[rp.count][1] - h else iv[2]
								ivPieces = lp + rp
								-- closer(s) in the gap
								if (b0 - a0) > p.brickL then
								(
									local m = 0.5 * (a0 + b0)
									append ivPieces #(a0, m - 0.5 * h, #S, 500)
									append ivPieces #(m + 0.5 * h, b0, #S, 501)
								)
								else if (b0 - a0) >= MIN_PIECE do append ivPieces #(a0, b0, #S, 500)
							)
							else
								ivPieces = BrickGenBonds.anchoredCourse cdef iv[1] iv[2] h p.brickL p.brickB iv[3]
						)
						for pc in ivPieces do
						(
							local xa = pc[1]
							local xb = pc[2]
							local x0 = amax xa iv[1]
							local x1 = amin xb iv[2]
							if (x1 - x0) >= MIN_PIECE do
								addBrick buf p (c * 65536 + keyBase + pc[4]) x0 x1 ha hb xa (xb - xa) z0 \
									(xa < iv[1] - 0.001) (xb > iv[2] + 0.001) (hb < zTop - 0.001) clipB:(ha > z0 + 0.001)
						)
					)
				)
			)

			-- mortar behind this course and its bed joint
			if p.mortarEnabled do
			(
				local mcuts = G.bandCuts ys z0 (amin (z0 + pitchZ) maxY)
				for i = 1 to mcuts.count - 1 do
				(
					local ha = mcuts[i]
					local hb = mcuts[i + 1]
					if (hb - ha) > 0.01 do
						for iv in (G.bandIntervals polys ha hb) do addMortarRect buf p iv[1] iv[2] ha hb
				)
			)
		)
		buf
	),

	-- Reveals (dagkanten): a strip of bricks depthMm deep along every
	-- horizontal/vertical edge of every opening (and of the outline when
	-- includeOuter), facing into the opening. Courses on the jambs use the
	-- facade's course grid, so the bond runs on round the corner; jamb strips
	-- leave room for the corner bricks built by the facade (facadeCorners).
	-- polys / p as for buildRegionInto (p.tm = facade placement).
	fn buildRevealsInto buf p polys depthMm includeOuter =
	(
		if depthMm < MIN_PIECE do return buf
		local T = depthMm
		local W = 0.0
		for poly in polys do for pt in poly do if pt.x > W do W = pt.x
		local strip = 0
		for e in (revealEdges polys includeOuter) do
		(
			local a = e[2]
			local b = e[3]
			local stm = undefined
			local rect = undefined
			local corners = #()
			if e[1] == #jamb then
			(
				-- jamb: strip x = depth into the wall, strip z = facade height
				local ex = 0.5 * (a.x + b.x)
				local y1 = amin a.y b.y
				local y2 = amax a.y b.y
				if e[4] > 0.0 then
				(
					stm = matrix3 [0, 1, 0] [-1, 0, 0] [0, 0, 1] [ex, 0, 0]
					corners = #(#(0.0, y1, y2, -1)) -- facade side at strip x = 0
				)
				else
				(
					stm = matrix3 [0, -1, 0] [1, 0, 0] [0, 0, 1] [ex, T, 0]
					corners = #(#(T, y1, y2, 1))    -- facade side at strip x = T
				)
				rect = #([0, y1, 0], [T, y1, 0], [T, y2, 0], [0, y2, 0])
			)
			else
			(
				-- sill (faces up) / head (faces down): strip x = along the
				-- edge, strip z = depth into the wall
				local ey = 0.5 * (a.y + b.y)
				local x1 = amin a.x b.x
				local x2 = amax a.x b.x
				if e[5] > 0.0 then
				(
					stm = matrix3 [1, 0, 0] [0, 0, -1] [0, 1, 0] [0, 0, ey]
					rect = #([x1, 0, 0], [x2, 0, 0], [x2, T, 0], [x1, T, 0])
				)
				else
				(
					stm = matrix3 [-1, 0, 0] [0, 0, 1] [0, 1, 0] [W, 0, ey]
					rect = #([W - x2, 0, 0], [W - x1, 0, 0], [W - x1, T, 0], [W - x2, T, 0])
				)
			)
			-- 0.5 mm towards the opening: covers sawn facade brick ends
			-- instead of z-fighting with them
			stm.row4 = stm.row4 - 0.5 * stm.row2
			strip += 1
			local q = copy p
			q.tm = stm * p.tm
			q.segIndex = p.segIndex + 1000 + strip
			q.uOffset = 0.0
			buildRegionInto buf q #(rect) corners:corners cornerMode:#reveal
		)
		buf
	),

	-- Appends one straight wall piece (p.wallLength x p.wallHeight, placed by
	-- p.tm) to buf. Used for the BrickWall object and per spline segment.
	fn buildWallInto buf p =
	(
		sanitize p
		if p.wallLength < MIN_PIECE or p.wallHeight < MIN_PIECE do return buf

		local bond = BrickGenBonds.get p.bondType
		local pitchZ = p.brickH + p.bedJoint
		local nCourses = (ceil (p.wallHeight / pitchZ)) as integer
		local offsets = BrickGenBonds.courseOffsets bond nCourses p.seed p.brickL p.brickB p.headJoint p.wildMinOverlap

		for c = 0 to nCourses - 1 do
		(
			local z0 = c * pitchZ
			local zTop = z0 + p.brickH
			local clipT = zTop > p.wallHeight
			local z1 = amin zTop p.wallHeight
			if (z1 - z0) >= MIN_PIECE do
			(
				local cdef = BrickGenBonds.courseDef bond c
				local pieces = BrickGenBonds.layoutCourse cdef (offsets[c + 1] + p.startOffset) p.wallLength p.headJoint p.brickL p.brickB
				for pc in pieces do
				(
					local xa = pc[1]
					local xb = pc[2]
					local clipL = xa < 0.0
					local clipR = xb > p.wallLength
					local x0 = amax xa 0.0
					local x1 = amin xb p.wallLength
					if (x1 - x0) >= MIN_PIECE do
						addBrick buf p (c * 65536 + pc[4]) x0 x1 z0 z1 xa (xb - xa) z0 clipL clipR clipT
				)
			)
		)
		if p.mortarEnabled do addMortar buf p
		buf
	),

	fn buildWall p = ( buildWallInto (BrickGenMeshBuffer()) p ),

	-- Write the buffer into a TriMesh (the `mesh` of a simpleObject).
	-- Returns timings in ms: #(setMesh, smoothing+edges, uv).
	fn applyToMesh m buf =
	(
		local t0 = timeStamp()
		setMesh m verts:buf.verts faces:buf.faces materialIDs:buf.matIDs
		local t1 = timeStamp()
		local nf = buf.faces.count
		for f = 1 to nf do setFaceSmoothGroup m f buf.smooth[f]
		-- hide the quad diagonals (coplanar edges) in one call
		meshop.autoEdge m #all 5.0 type:#setClear
		local t2 = timeStamp()
		-- map verts = geometry verts, map faces = geometry faces.
		-- A fresh mesh only has channels 0 and 1: allocate channel 2 first.
		if (meshop.getNumMaps m) < 3 do meshop.setNumMaps m 3 keep:true
		for ch = 1 to 2 do
		(
			local uv = if ch == 1 then buf.uv1 else buf.uv2
			meshop.setMapSupport m ch true
			meshop.defaultMapFaces m ch
			for i = 1 to uv.count do meshop.setMapVert m ch i uv[i]
		)
		local t3 = timeStamp()
		#(t1 - t0, t2 - t1, t3 - t2)
	)
)

global BrickGenMesh = BrickGenMeshStruct()
