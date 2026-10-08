-- BrickGen_Modifier.ms
-- Scripted modifier "BrickGen": put it directly on a spline (instead of
-- Extrude). Every straight segment becomes a brick wall; the bond runs on
-- along the path, so the pattern continues around corners.
--
-- Conventions:
--   * The spline is the OUTSIDE face of the facade; the wall goes in on the
--     left of the drawing direction. Closed splines drawn counter-clockwise
--     (seen from the top) face outwards; tick "Andere kant" to flip.
--   * Segments are treated as straight lines between the knots (curves later).
--   * Corners: v1 simply ends each segment at the knot; real corner bonding is
--     PLAN.md phase 4.
-- Requires BrickGen_Mesh.ms etc. (BrickGen_Startup.ms loads everything).
-- Never change classID; never remove or reorder parameters.

-- Straight segments of the editable spline at the bottom of the node's stack,
-- in the node's local coordinates (system units): #(#(a, b), ...).
fn BrickGen_splineSegments node =
(
	local segs = #()
	for s = 1 to (numSplines node) do
	(
		local n = numKnots node s
		local count = if (isClosed node s) then n else n - 1
		for k = 1 to count do
		(
			local a = in coordsys local getKnotPoint node s k
			local b = in coordsys local getKnotPoint node s (if k == n then 1 else k + 1)
			append segs #(a, b)
		)
	)
	segs
)

global BrickGenModWarned = false

plugin simpleMeshMod BrickGenMod
	name:"BrickGen"
	classID:#(0x5c2e8a13, 0x1f7b3d96)
	category:"BrickGen"
	version:1
(
	-- ------------------------------------------------------------------ Muur
	parameters pWall rollout:rWall
	(
		wallHeight type:#worldUnits ui:spnHeight default:250.0
		flipSide type:#boolean ui:chkFlip default:false
		seed type:#integer ui:spnSeed default:12345
	)
	rollout rWall "Muur"
	(
		spinner spnHeight "Hoogte:" type:#worldUnits range:[0, 1e7, 0]
		checkbox chkFlip "Andere kant (gevel omdraaien)"
		spinner spnSeed "Seed:" type:#integer range:[0, 999999999, 12345]
		button btnNewSeed "Nieuwe seed" width:140
		on btnNewSeed pressed do seed = random 1 999999
	)

	-- ----------------------------------------------------------------- Steen
	parameters pBrick rollout:rBrick
	(
		formatPreset type:#integer ui:ddlFormat default:1
		brickL type:#float ui:spnBrickL default:210.0
		brickB type:#float ui:spnBrickB default:100.0
		brickH type:#float ui:spnBrickH default:50.0
	)
	rollout rBrick "Steen (mm)"
	(
		dropdownlist ddlFormat "Formaat:"
		spinner spnBrickL "Lengte L:" type:#float range:[1, 1000, 210]
		spinner spnBrickB "Breedte B:" type:#float range:[1, 1000, 100]
		spinner spnBrickH "Hoogte H:" type:#float range:[1, 1000, 50]

		on rBrick open do
		(
			ddlFormat.items = BrickGenFormats.names()
			ddlFormat.selection = formatPreset
		)
		-- only on user interaction, so custom L/B/H are never overwritten on load
		on ddlFormat selected i do
		(
			local f = BrickGenFormats.get i
			if f != undefined do
			(
				brickL = f.L
				brickB = f.B
				brickH = f.H
			)
		)
	)

	-- ------------------------------------------------------------------ Voeg
	parameters pJoint rollout:rJoint
	(
		bedJoint type:#float ui:spnBedJoint default:12.0
		headJoint type:#float ui:spnHeadJoint default:12.0
		jointRecess type:#float ui:spnRecess default:5.0
		mortarEnabled type:#boolean ui:chkMortar default:true
	)
	rollout rJoint "Voeg (mm)"
	(
		spinner spnBedJoint "Lintvoeg:" type:#float range:[0, 100, 12]
		spinner spnHeadJoint "Stootvoeg:" type:#float range:[0, 100, 12]
		spinner spnRecess "Terugligging:" type:#float range:[0, 100, 5]
		checkbox chkMortar "Voegvlak" checked:true
	)

	-- --------------------------------------------------------------- Verband
	parameters pBond rollout:rBond
	(
		bondType type:#integer ui:ddlBond default:1
		startOffset type:#float ui:spnStartOffset default:0.0
	)
	rollout rBond "Verband"
	(
		dropdownlist ddlBond "Verband:"
		spinner spnStartOffset "Startoffset (mm):" type:#float range:[-10000, 10000, 0]

		on rBond open do
		(
			ddlBond.items = BrickGenBonds.labels()
			ddlBond.selection = bondType
		)
	)

	-- ----------------------------------------------------- Vorm/imperfectie
	parameters pShape rollout:rShape
	(
		chamfer type:#float ui:spnChamfer default:2.0
		chamferJitter type:#float ui:spnChamferJitter default:0.3
		cornerJitter type:#float ui:spnCornerJitter default:1.0
		depthJitter type:#float ui:spnDepthJitter default:1.5
		rotJitter type:#float ui:spnRotJitter default:0.3
		sizeJitter type:#float ui:spnSizeJitter default:1.0
	)
	rollout rShape "Vorm en imperfectie"
	(
		spinner spnChamfer "Chamfer (mm):" type:#float range:[0, 50, 2]
		spinner spnChamferJitter "Chamfer-variatie:" type:#float range:[0, 1, 0.3] scale:0.01
		spinner spnCornerJitter "Hoeken (mm):" type:#float range:[0, 20, 1]
		spinner spnDepthJitter "Diepte (mm):" type:#float range:[0, 20, 1.5]
		spinner spnRotJitter "Rotatie (graden):" type:#float range:[0, 10, 0.3] scale:0.05
		spinner spnSizeJitter "Maat (mm):" type:#float range:[0, 20, 1]
	)

	-- ------------------------------------------------------------- Materiaal
	parameters pMat rollout:rMat
	(
		matIdCount type:#integer ui:spnMatIdCount default:5
		mortarMatId type:#integer ui:spnMortarMatId default:100
	)
	rollout rMat "Materiaal"
	(
		spinner spnMatIdCount "Steen-ID's (1..N):" type:#integer range:[1, 99, 5]
		spinner spnMortarMatId "Voeg-ID:" type:#integer range:[1, 9999, 100]
	)

	-- -------------------------------------------------------------- Weergave
	parameters pView rollout:rView
	(
		previewMode type:#boolean ui:chkPreview default:false
	)
	rollout rView "Weergave"
	(
		checkbox chkPreview "Snelle preview (geen chamfer/jitter)"
	)

	on create do
	(
		try (wallHeight = units.decodeValue "2500mm") catch ()
	)

	-- ----------------------------------------------------------------- Build
	on modifyMesh do
	(
		local t0 = timeStamp()
		local buf = BrickGenMeshBuffer()
		local node = refs.dependentNodes this firstOnly:true
		local base = if node != undefined then node.baseObject else undefined
		if base != undefined and (isKindOf base SplineShape or isKindOf base line) then
		(
			BrickGenModWarned = false
			local s = units.decodeValue "1mm" -- system units per mm
			local segs = BrickGen_splineSegments node
			if flipSide do
				segs = for i = segs.count to 1 by -1 collect #(segs[i][2], segs[i][1])

			local pathMm = 0.0
			for i = 1 to segs.count do
			(
				local a = segs[i][1]
				local b = segs[i][2]
				local d = b - a
				d.z = 0.0
				local lenMm = (length d) / s
				if lenMm >= 1.0 do
				(
					local X = normalize d
					local Z = [0.0, 0.0, 1.0]
					local Y = cross Z X
					local p = BrickGenWallParams()
					p.unitScale = s
					p.tm = matrix3 (X * s) (Y * s) (Z * s) a
					p.wallLength = lenMm
					p.wallHeight = wallHeight / s
					p.uOffset = pathMm
					p.segIndex = i
					p.seed = seed
					p.brickL = brickL
					p.brickB = brickB
					p.brickH = brickH
					p.bedJoint = bedJoint
					p.headJoint = headJoint
					p.jointRecess = jointRecess
					p.mortarEnabled = mortarEnabled
					p.bondType = bondType
					-- continue the bond along the path
					p.startOffset = startOffset - pathMm
					p.chamfer = chamfer
					p.chamferJitter = chamferJitter
					p.cornerJitter = cornerJitter
					p.depthJitter = depthJitter
					p.rotJitter = rotJitter
					p.sizeJitter = sizeJitter
					p.matIdCount = matIdCount
					p.mortarMatId = mortarMatId
					p.previewMode = previewMode
					BrickGenMesh.buildWallInto buf p
					pathMm += lenMm
				)
			)
		)
		else if not BrickGenModWarned do
		(
			BrickGenModWarned = true
			format "BrickGen: zet de modifier rechtstreeks op een Line of Editable Spline (gevonden: %)\n" \
				(if base == undefined then "geen node" else classOf base)
		)

		local tGeo = timeStamp() - t0
		local tApply = BrickGenMesh.applyToMesh mesh buf
		local ms = timeStamp() - t0
		BrickGenSettings.lastBuildMs = ms
		BrickGenSettings.lastTris = buf.faces.count
		BrickGenSettings.lastPhases = #(tGeo) + tApply
		if BrickGenSettings.logTiming or ms > BrickGenSettings.slowBuildMs do
			format "BrickGen modifier: % stenen, % tris, % ms (geometrie %, setMesh %, smoothing %, uv %)\n" \
				buf.brickCount buf.faces.count ms tGeo tApply[1] tApply[2] tApply[3]
	)
)
