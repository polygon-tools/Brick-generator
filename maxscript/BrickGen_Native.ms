-- BrickGen_Native.ms
-- Fast path: the geometry is built by bin\BrickGen.Core.dll (C#, source in
-- csharp\BrickGen.Core\Builder.cs, a port of BrickGen_Mesh.ms). Same RNG and
-- channels, so the same seed gives the same wall. When the DLL cannot be
-- loaded, BrickGen falls back to the MAXScript builder (BrickGen_Mesh.ms).
--
-- Switch off for a comparison:  BrickGenNative.enabled = false

struct BrickGenNativeStruct
(
	enabled = true,
	loaded = false,
	failed = false, -- an error occurred once: stay on MAXScript this session
	builder = undefined,

	fn load root =
	(
		local f = pathConfig.appendPath root "bin\\BrickGen.Core.dll"
		if doesFileExist f do
		(
			try
			(
				dotNet.loadAssembly f
				builder = dotNetClass "BrickGen.Builder"
				loaded = builder != undefined
			)
			catch ( format "BrickGen: C#-module niet geladen: %\n" (getCurrentException()) )
		)
		loaded
	),

	fn available = ( enabled and loaded and not failed ),

	fn toDoubles arr = ( dotNet.ValueToDotNetObject arr (dotNetClass "System.Double[]") ),
	fn toInts arr = ( dotNet.ValueToDotNetObject arr (dotNetClass "System.Int32[]") ),

	-- matrix3 -> 12 values (row1..row4)
	fn matrixValues m =
	(
		#(m.row1.x, m.row1.y, m.row1.z, m.row2.x, m.row2.y, m.row2.z,
		  m.row3.x, m.row3.y, m.row3.z, m.row4.x, m.row4.y, m.row4.z)
	),

	fn cellValues cells =
	(
		local res = #()
		for c in cells do ( append res c[1]; append res c[2]; append res c[3]; append res c[4]; append res c[5] )
		if res.count == 0 do res = #(0.0)
		res
	),

	-- Build the facade (region fill + reveals) into a BrickGenMeshBuffer.
	-- p: BrickGenWallParams (sanitized values in mm), polys: closed polygons in
	-- wall mm. Returns the buffer, or undefined on error (then: MAXScript).
	fn build p polys revealDepthMm revealOuter revealOffsetMm =
	(
		local buf = undefined
		try
		(
			local np = dotNetObject "BrickGen.Params"
			np.Seed = p.seed
			np.BrickL = p.brickL
			np.BrickB = p.brickB
			np.BrickH = p.brickH
			np.BedJoint = p.bedJoint
			np.HeadJoint = p.headJoint
			np.JointRecess = p.jointRecess
			np.MortarEnabled = p.mortarEnabled
			np.BondType = p.bondType
			np.StartOffset = p.startOffset
			np.WildMinOverlap = p.wildMinOverlap
			np.Chamfer = p.chamfer
			np.ChamferJitter = p.chamferJitter
			np.CornerJitter = p.cornerJitter
			np.DepthJitter = p.depthJitter
			np.RotJitter = p.rotJitter
			np.SizeJitter = p.sizeJitter
			np.MatIdCount = p.matIdCount
			np.MortarMatId = p.mortarMatId
			np.PreviewMode = p.previewMode
			np.AtlasFlip = p.atlasFlip
			np.AtlasRotate = p.atlasRotate
			np.ChipChance = p.chipChance
			np.ChipSize = p.chipSize
			np.RevealDepth = revealDepthMm
			np.RevealOuter = revealOuter
			np.RevealOffset = revealOffsetMm

			local xy = #()
			local counts = #()
			for poly in polys do
			(
				append counts poly.count
				for pt in poly do ( append xy pt.x; append xy pt.y )
			)
			local tmv = matrixValues p.tm
			local st = if p.atlas != undefined then cellValues p.atlas.stretchers else #(0.0)
			local hd = if p.atlas != undefined then cellValues p.atlas.headers else #(0.0)
			local r = builder.Build np (toDoubles xy) (toInts counts) (toDoubles tmv) (toDoubles st) (toDoubles hd)

			local V = r.GetVerts()
			local F = r.GetFaces()
			if classOf V != Array or classOf F != Array do throw "arrays not converted"
			buf = BrickGenMeshBuffer()
			local nv = V.count / 3
			local nf = F.count / 3
			buf.verts = for i = 0 to nv - 1 collect [V[3 * i + 1], V[3 * i + 2], V[3 * i + 3]]
			buf.faces = for i = 0 to nf - 1 collect [F[3 * i + 1], F[3 * i + 2], F[3 * i + 3]]
			buf.matIDs = r.GetMatIDs()
			buf.smooth = r.GetSmooth()
			-- UVs stay flat (u, v, u, v, ...): applyToMesh reads them directly
			buf.uv1 = r.GetUV1()
			buf.uv2 = r.GetUV2()
			buf.uvFlat = true
			buf.brickCount = r.BrickCount
			buf.nativeMs = r.Milliseconds
		)
		catch
		(
			failed = true
			buf = undefined
			format "BrickGen: C#-module gaf een fout, verder in MAXScript: %\n" (getCurrentException())
		)
		buf
	)
)

global BrickGenNative = BrickGenNativeStruct()
