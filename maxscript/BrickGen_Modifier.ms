-- BrickGen_Modifier.ms
-- Scripted modifier "BrickGen": put it on a closed spline drawn over a facade
-- elevation (in the Front/Left/Right/Back view). The whole area inside the
-- outline is filled with bricks; extra closed splines inside it (windows,
-- doors) become openings, like Extrude would do.
--
-- Conventions:
--   * The spline lies in its local XY plane (that is how 3ds Max creates a
--     shape in any view): local X = along the facade, local Y = up. Bricks
--     face local +Z (towards the view it was drawn in); "Andere kant" flips.
--   * Segments are straight lines between the knots (curves later).
--   * Slanted edges (gables) are sawn per course with a vertical cut (v1).
-- Requires BrickGen_Region.ms and BrickGen_Mesh.ms (BrickGen_Startup.ms).
-- Never change classID; never remove or reorder parameters.

-- All splines of the editable spline at the bottom of the node's stack, as
-- closed polygons in the node's local coordinates (system units).
fn BrickGen_splinePolygons node =
(
	for s = 1 to (numSplines node) collect
		for k = 1 to (numKnots node s) collect (in coordsys local getKnotPoint node s k)
)

global BrickGenModWarned = false

plugin simpleMeshMod BrickGenMod
	name:"BrickGen"
	classID:#(0x5c2e8a13, 0x1f7b3d96)
	category:"BrickGen"
	version:1
(
	-- ------------------------------------------------------------------ Gevel
	parameters pWall rollout:rWall
	(
		flipSide type:#boolean ui:chkFlip default:false
		seed type:#integer ui:spnSeed default:12345
		revealDepth type:#worldUnits ui:spnReveal default:30.0
		revealOuter type:#boolean ui:chkRevealOuter default:false
		revealOffset type:#worldUnits ui:spnRevealOffset default:0.0
	)
	rollout rWall "Gevel"
	(
		checkbox chkFlip "Andere kant (gevel omdraaien)"
		spinner spnSeed "Seed:" type:#integer range:[0, 999999999, 12345]
		button btnNewSeed "Nieuwe seed" width:140
		on btnNewSeed pressed do seed = random 1 999999
		spinner spnReveal "Dagkantdiepte:" type:#worldUnits range:[0, 1e6, 30]
		checkbox chkRevealOuter "Ook langs de buitenrand"
		spinner spnRevealOffset "Dagkant offset:" type:#worldUnits range:[-1e6, 1e6, 0]
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
		atlasFile type:#string ui:edtAtlasPath default:""
		atlasFlip type:#boolean ui:chkAtlasFlip default:true
		atlasRotate type:#boolean ui:chkAtlasRotate default:true
		mortarColor type:#color ui:cpMortar default:(color 120 115 108)
		brickGloss type:#float ui:spnGloss default:30.0
	)
	rollout rMat "Materiaal en textuur"
	(
		spinner spnMatIdCount "Steen-ID's (1..N):" type:#integer range:[1, 99, 5]
		spinner spnMortarMatId "Voeg-ID:" type:#integer range:[1, 9999, 100]
		group "Textuur-atlas"
		(
			edittext edtAtlas "" readOnly:true width:140
			edittext edtAtlasPath "" readOnly:true visible:false
			button btnAtlas "Kies atlas..." width:90 across:2
			button btnAtlasClear "Geen" width:50
			checkbox chkAtlasFlip "Random spiegelen"
			checkbox chkAtlasRotate "Random 180 graden draaien"
		)
		group "Materiaal"
		(
			colorpicker cpMortar "Voegkleur:" color:(color 120 115 108) modal:false
			spinner spnGloss "Glans steen (%):" type:#float range:[0, 100, 30]
		)
		button btnMakeMat "Maak materiaal" width:140 height:26

		-- colour and gloss also update a material that was already made
		fn updateMaterial col gloss =
		(
			local node = refs.dependentNodes this firstOnly:true
			if node != undefined do BrickGenMaterial.updateColors node.material col gloss
		)
		on cpMortar changed c do updateMaterial c brickGloss
		on spnGloss changed v do updateMaterial mortarColor v

		fn refresh = ( edtAtlas.text = if atlasFile == "" then "(geen atlas)" else filenameFromPath atlasFile )
		on rMat open do refresh()
		on btnAtlas pressed do
		(
			local startDir = if atlasFile != "" then getFilenamePath atlasFile
				else pathConfig.appendPath ::BrickGenRoot "presets\\atlases\\"
			local f = getOpenFileName caption:"BrickGen atlas kiezen" filename:startDir \
				types:"BrickGen atlas (*.json)|*.json|Alle bestanden (*.*)|*.*"
			if f != undefined do
			(
				if (BrickGenAtlasLib.get f) == undefined then
					messageBox ("Dit is geen bruikbare BrickGen-atlas:\n" + f) title:"BrickGen"
				else
				(
					atlasFile = f
					try (notifyDependents this) catch ()
					refresh()
				)
			)
		)
		on btnAtlasClear pressed do
		(
			atlasFile = ""
			try (notifyDependents this) catch ()
			refresh()
		)
		on btnMakeMat pressed do
		(
			local node = refs.dependentNodes this firstOnly:true
			local atlas = BrickGenAtlasLib.get atlasFile
			if atlas == undefined and atlasFile != "" do
				messageBox "De atlas kon niet gelezen worden; het materiaal krijgt een effen kleur." title:"BrickGen"
			if atlas != undefined and (BrickGenAtlasLib.mapPath atlas "diffuse") != undefined and \
				not (doesFileExist (BrickGenAtlasLib.mapPath atlas "diffuse")) do
				messageBox ("Textuur niet gevonden:\n" + (BrickGenAtlasLib.mapPath atlas "diffuse") + \
					"\n\nZet de afbeelding naast het atlas-bestand.") title:"BrickGen"
			BrickGenMaterial.makeFor node atlas matIdCount mortarMatId mortarCol:mortarColor gloss:brickGloss
		)
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
		try (revealDepth = units.decodeValue "300mm") catch ()
	)

	-- Cache: the geometry is only rebuilt when a parameter or the spline changes.
	local cacheSig = ""
	local cacheBuf = undefined
	local lastAtlasInfo = "geen atlas"


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
			local raw = BrickGen_splinePolygons node

			local ss = stringStream ""
			format "%|" s to:ss
			for n in (getPropNames this) do format "%=%|" n (getProperty this n) to:ss
			for poly in raw do (for pt in poly do format "%," pt to:ss; format ";" to:ss)
			if atlasFile != "" and doesFileExist atlasFile do format "%" (getFileModDate atlasFile) to:ss
			local sig = ss as string
			if sig == cacheSig and cacheBuf != undefined then buf = cacheBuf
			else
			(
				-- bounding box in mm
				local minX = 1e30
				local minY = 1e30
				local maxX = -1e30
				for poly in raw do for pt in poly do
				(
					if pt.x / s < minX do minX = pt.x / s
					if pt.y / s < minY do minY = pt.y / s
					if pt.x / s > maxX do maxX = pt.x / s
				)
				-- to wall mm coordinates: x along (mirrored when flipped), y up
				local polys = for poly in raw where poly.count >= 3 collect
					for pt in poly collect
						[(if flipSide then maxX - pt.x / s else pt.x / s - minX), pt.y / s - minY, 0.0]

				local p = BrickGenWallParams()
				p.unitScale = s
				-- wall-local (x along, y depth, z up) mm -> spline-local system units.
				-- Front faces local +Z, or -Z when flipped.
				p.tm = if flipSide then
					matrix3 [-s, 0, 0] [0, 0, s] [0, s, 0] [maxX * s, minY * s, 0]
				else
					matrix3 [s, 0, 0] [0, 0, -s] [0, s, 0] [minX * s, minY * s, 0]
				p.seed = seed
				p.brickL = brickL
				p.brickB = brickB
				p.brickH = brickH
				p.bedJoint = bedJoint
				p.headJoint = headJoint
				p.jointRecess = jointRecess
				p.mortarEnabled = mortarEnabled
				p.bondType = bondType
				p.startOffset = startOffset
				p.chamfer = chamfer
				p.chamferJitter = chamferJitter
				p.cornerJitter = cornerJitter
				p.depthJitter = depthJitter
				p.rotJitter = rotJitter
				p.sizeJitter = sizeJitter
				p.matIdCount = matIdCount
				p.mortarMatId = mortarMatId
				p.previewMode = previewMode
			p.atlas = BrickGenAtlasLib.get atlasFile
			lastAtlasInfo = if p.atlas == undefined then "geen atlas" else \
				(p.atlas.name + ", " + ((p.atlas.stretchers.count + p.atlas.headers.count) as string) + " cellen")
			p.atlasFlip = atlasFlip
			p.atlasRotate = atlasRotate
				if polys.count > 0 do
				(
					BrickGenMesh.buildRegionInto buf p polys
					BrickGenMesh.buildRevealsInto buf (copy p) polys (revealDepth / s) revealOuter \
						jambOffsetMm:(revealOffset / s)
				)
				cacheSig = sig
				cacheBuf = buf
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
			format "BrickGen modifier: % stenen, % tris, % ms (geometrie %, setMesh %, smoothing %, uv %), %\n" \
				buf.brickCount buf.faces.count ms tGeo tApply[1] tApply[2] tApply[3] lastAtlasInfo
	)
)
