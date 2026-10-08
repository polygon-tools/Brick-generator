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
	unitScale = 1.0 -- system units per mm
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
	-- (a,c,d); the shared diagonal a-c is hidden in applyToMesh.
	fn addQuad buf a b c d sg mat =
	(
		append buf.faces [a, b, c]
		append buf.faces [a, c, d]
		append buf.matIDs mat
		append buf.matIDs mat
		append buf.smooth sg
		append buf.smooth sg
	),

	-- x0..x1 / z0..z1: (clipped) brick extent in mm.
	-- nomX0 / nomL: unclipped start and length (for UVs).
	-- clipL / clipR / clipT: that edge is sawn at the wall boundary.
	fn addBrick buf p idx x0 x1 z0 z1 nomX0 nomL nomZ0 clipL clipR clipT =
	(
		local R = BrickGenRNG
		local key = R.brickKey p.seed idx
		local jitter = not p.previewMode

		-- 1. size jitter (only on free edges)
		if jitter and p.sizeJitter > 0.0 do
		(
			local dL = 0.5 * p.sizeJitter * (R.sym key 1)
			local dH = 0.5 * p.sizeJitter * (R.sym key 2)
			if not clipL do x0 -= dL
			if not clipR do x1 += dL
			z0 = amax 0.0 (z0 - dH)
			if not clipT do z1 += dH
		)

		-- 2. chamfer with jitter, clamped to half the smallest side
		local w = x1 - x0
		local h = z1 - z0
		local c = 0.0
		if jitter do c = p.chamfer * (1.0 + p.chamferJitter * (R.sym key 3))
		c = amax 0.0 (amin c (0.5 * (amin w h) - 0.05))
		local cL = if clipL then 0.0 else c
		local cR = if clipR then 0.0 else c
		local cT = if clipT then 0.0 else c
		local depth = p.jointRecess + c + 3.0 + p.depthJitter

		local pts = #(
			[x0 + cL, 0.0, z0 + c], [x1 - cR, 0.0, z0 + c], [x1 - cR, 0.0, z1 - cT], [x0 + cL, 0.0, z1 - cT],
			[x0, c, z0], [x1, c, z0], [x1, c, z1], [x0, c, z1]
		)

		-- 3. corner jitter on the 8 front vertices; sawn edges stay straight
		if jitter and p.cornerJitter > 0.0 do
		(
			for v = 1 to 8 do
			(
				local k = if v > 4 then v - 4 else v
				local onLeft = (k == 1 or k == 4)
				local onTop = (k == 3 or k == 4)
				local sawnX = if onLeft then clipL else clipR
				local jx = if sawnX then 0.0 else p.cornerJitter * (R.sym key (10 + v))
				local jz = if onTop and clipT then 0.0 else p.cornerJitter * (R.sym key (20 + v))
				local jy = 0.3 * p.cornerJitter * (R.sym key (30 + v))
				pts[v] = pts[v] + [jx, jy, jz]
			)
		)

		-- back vertices follow the outer rim
		for v = 5 to 8 do append pts [pts[v].x, depth, pts[v].z]

		-- channel 1 before depth/rotation, so the texture moves with the brick
		local uv1 = for pt in pts collect BrickGenUV.brickUV pt.x pt.z nomX0 nomZ0 nomL p.brickH

		-- 4. depth jitter
		if jitter and p.depthJitter > 0.0 do
		(
			local dy = p.depthJitter * (R.sym key 4)
			for i = 1 to pts.count do pts[i] = pts[i] + [0.0, dy, 0.0]
		)

		-- 5. rotation around Y through the brick centre (not for sawn bricks)
		if jitter and p.rotJitter > 0.0 and not (clipL or clipR or clipT) do
		(
			local a = p.rotJitter * (R.sym key 5)
			local ca = cos a
			local sa = sin a
			local cx = 0.5 * (x0 + x1)
			local cz = 0.5 * (z0 + z1)
			for i = 1 to pts.count do
			(
				local dx = pts[i].x - cx
				local dz = pts[i].z - cz
				pts[i] = [cx + dx * ca - dz * sa, pts[i].y, cz + dx * sa + dz * ca]
			)
		)

		local mat = R.randInt key 6 1 (amax 1 p.matIdCount)

		local base = buf.verts.count
		local s = p.unitScale
		for i = 1 to 12 do
		(
			local pt = pts[i]
			append buf.verts (pt * s)
			append buf.uv1 uv1[i]
			append buf.uv2 (BrickGenUV.planarUV pt.x pt.z)
		)

		-- faces
		addQuad buf (base + 1) (base + 2) (base + 3) (base + 4) SG_FRONT mat
		for k = 1 to 4 do
		(
			local kn = if k == 4 then 1 else k + 1
			-- chamfer ring
			addQuad buf (base + kn) (base + k) (base + 4 + k) (base + 4 + kn) SG_SIDES mat
			-- side
			addQuad buf (base + 4 + kn) (base + 4 + k) (base + 8 + k) (base + 8 + kn) SG_SIDES mat
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
			append buf.verts (pt * p.unitScale)
			append buf.uv1 (BrickGenUV.planarUV pt.x pt.z)
			append buf.uv2 (BrickGenUV.planarUV pt.x pt.z)
		)
		addQuad buf (base + 1) (base + 2) (base + 3) (base + 4) SG_MORTAR p.mortarMatId
	),

	fn buildWall p =
	(
		local buf = BrickGenMeshBuffer()
		p.brickL = amax 1.0 p.brickL
		p.brickB = amax 1.0 p.brickB
		p.brickH = amax 1.0 p.brickH
		p.bedJoint = amax 0.0 p.bedJoint
		p.headJoint = amax 0.0 p.headJoint
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

	-- Write the buffer into a TriMesh (the `mesh` of a simpleObject).
	fn applyToMesh m buf =
	(
		setMesh m verts:buf.verts faces:buf.faces materialIDs:buf.matIDs
		local nf = buf.faces.count
		for f = 1 to nf do
		(
			setFaceSmoothGroup m f buf.smooth[f]
			-- faces come in pairs (a,b,c) (a,c,d): hide the diagonal a-c
			if (mod f 2) == 1 then setEdgeVis m f 3 false else setEdgeVis m f 1 false
		)
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
		m
	)
)

global BrickGenMesh = BrickGenMeshStruct()
