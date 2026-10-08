-- BrickGen_Tests.ms
-- Phase 1 checks (PLAN.md §12, §13). Run in 3ds Max after BrickGen_Startup.ms:
--   Scripting > Run Script... > BrickGen_Tests.ms
-- Works in a new, empty scene; deletes the objects it creates. Prints PASS/FAIL
-- and timings to the MAXScript Listener; please send the output back.

(
	local passed = 0
	local failed = 0

	fn check name ok detail:"" =
	(
		if ok then (passed += 1; format "PASS  %\n" name)
		else (failed += 1; format "FAIL  %  %\n" name detail)
		ok
	)

	fn mm v = units.decodeValue ((v as string) + "mm")

	fn makeWall lenMm hMm seedVal:12345 bond:1 =
	(
		local w = BrickWall()
		w.wallLength = mm lenMm
		w.wallHeight = mm hMm
		w.seed = seedVal
		w.bondType = bond
		w
	)

	fn vertsOf obj =
	(
		local m = snapshotAsMesh obj
		local r = for i = 1 to m.numverts collect getVert m i
		delete m
		r
	)

	fn sameVerts a b tol:0.0001 =
	(
		if a.count != b.count then false
		else
		(
			local ok = true
			for i = 1 to a.count while ok do if (distance a[i] b[i]) > tol do ok = false
			ok
		)
	)

	fn buildMs obj =
	(
		local t0 = timeStamp()
		local m = snapshotAsMesh obj
		local ms = timeStamp() - t0
		local nf = m.numfaces
		delete m
		#(ms, nf)
	)

	format "\n===== BrickGen tests (% , systeemeenheid %) =====\n" (maxVersion())[1] units.SystemType
	local created = #()

	-- 1. determinism, per bond
	for b = 1 to BrickGenBonds.defs.count do
	(
		local w1 = makeWall 3000 2500 seedVal:42 bond:b
		local w2 = makeWall 3000 2500 seedVal:42 bond:b
		local w3 = makeWall 3000 2500 seedVal:43 bond:b
		local v1 = vertsOf w1
		check ("zelfde seed = zelfde muur (" + BrickGenBonds.defs[b].label + ")") (sameVerts v1 (vertsOf w2))
		check ("andere seed = andere muur (" + BrickGenBonds.defs[b].label + ")") (not (sameVerts v1 (vertsOf w3)))
		join created #(w1, w2, w3)
	)

	-- 2. triangle budget: 18 per brick + 2 mortar
	(
		local w = makeWall 3000 2500
		local m = snapshotAsMesh w
		local nf = m.numfaces
		check "18 tris per steen (+2 voeg)" (nf > 2 and (mod (nf - 2) 18) == 0) detail:(nf as string)
		-- material IDs in 1..N and mortar
		local ids = #()
		for f = 1 to nf do appendIfUnique ids (getFaceMatID m f)
		local okIds = true
		for i in ids do if not ((i >= 1 and i <= w.matIdCount) or i == w.mortarMatId) do okIds = false
		check "material ID's 1..N + voeg" (okIds and (findItem ids w.mortarMatId) > 0) detail:(ids as string)
		check "UV-kanaal 2 aanwezig" (meshop.getMapSupport m 2)
		-- bounding box = exact wall size (mm)
		local bb = nodeGetBoundingBox w (matrix3 1)
		local sizeX = (bb[2].x - bb[1].x) / (mm 1)
		local sizeZ = (bb[2].z - bb[1].z) / (mm 1)
		check "breedte = wallLength" ((abs (sizeX - 3000)) < 3.0) detail:(sizeX as string)
		check "hoogte = wallHeight" ((abs (sizeZ - 2500)) < 3.0) detail:(sizeZ as string)
		delete m
		append created w
	)

	-- 3. edge cases: must not crash, must give geometry where expected
	local cases = #(
		#("muur korter dan 1 steen", 120, 500, undefined),
		#("lengte geen veelvoud steenmaat", 3017.3, 2501.7, undefined),
		#("zeer hoge muur", 600, 12000, undefined),
		#("voeg 0 mm", 1000, 1000, #headJoint0),
		#("chamfer 0", 1000, 1000, #chamfer0),
		#("chamfer > halve steenhoogte (geklemd)", 1000, 1000, #chamferBig),
		#("lengte 0", 0, 1000, undefined)
	)
	for cs in cases do
	(
		local ok = true
		local err = ""
		try
		(
			local w = makeWall cs[2] cs[3]
			case cs[4] of
			(
				#headJoint0: (w.headJoint = 0; w.bedJoint = 0)
				#chamfer0: w.chamfer = 0
				#chamferBig: (w.chamfer = 40; w.chamferJitter = 1.0)
				default: ok
			)
			local m = snapshotAsMesh w
			if cs[2] > 0 and m.numfaces == 0 do (ok = false; err = "geen geometrie")
			delete m
			append created w
		)
		catch (ok = false; err = getCurrentException())
		check ("rand: " + cs[1]) ok detail:err
	)

	-- 4. units: same wall in mm, cm and m -> same real size and vertex count
	(
		local oldUnit = units.SystemType
		local results = #()
		for u in #(#millimeters, #centimeters, #meters) do
		(
			units.SystemType = u
			local w = makeWall 3000 2500
			local m = snapshotAsMesh w
			local bb = nodeGetBoundingBox w (matrix3 1)
			append results #(u, m.numverts, (bb[2].x - bb[1].x) / (mm 1))
			delete m
			delete w
		)
		units.SystemType = oldUnit
		local ok = true
		for r in results do
			if r[2] != results[1][2] or (abs (r[3] - results[1][3])) > 0.5 do ok = false
		check "eenheden mm/cm/m geven dezelfde muur" ok detail:(results as string)
	)

	-- 5. timing (PLAN.md §8: 7.5 m2 < 0.2 s, 200 m2 < 3 s)
	(
		local small = makeWall 3000 2500
		local r1 = buildMs small
		format "TIME  7,5 m2 (3 x 2,5 m): % ms, % tris\n" r1[1] r1[2]
		check "7,5 m2 onder 200 ms" (r1[1] < 200) detail:((r1[1] as string) + " ms")
		local big = makeWall 20000 10000
		local r2 = buildMs big
		format "TIME  200 m2 (20 x 10 m): % ms, % tris\n" r2[1] r2[2]
		check "200 m2 onder 3000 ms" (r2[1] < 3000) detail:((r2[1] as string) + " ms")
		join created #(small, big)
	)

	for o in created where isValidNode o do delete o
	format "===== % geslaagd, % mislukt =====\n" passed failed
)
