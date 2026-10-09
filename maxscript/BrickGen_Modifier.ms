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
	-- ============================================================ parameters
	-- Never reorder these blocks or their parameters (scenes store them);
	-- only append. The rollouts below may be laid out freely.
	parameters pWall rollout:rWall
	(
		flipSide type:#boolean ui:chkFlip default:false
		seed type:#integer ui:spnSeed default:12345
		revealDepth type:#worldUnits ui:spnReveal default:30.0
		revealOuter type:#boolean ui:chkRevealOuter default:false
		revealOffset type:#worldUnits ui:spnRevealOffset default:0.0
	)
	parameters pBrick rollout:rBrick
	(
		formatPreset type:#integer ui:ddlFormat default:1
		brickL type:#float ui:spnBrickL default:210.0
		brickB type:#float ui:spnBrickB default:100.0
		brickH type:#float ui:spnBrickH default:50.0
	)
	parameters pJoint rollout:rJoint
	(
		bedJoint type:#float ui:spnBedJoint default:12.0
		headJoint type:#float ui:spnHeadJoint default:12.0
		jointRecess type:#float ui:spnRecess default:5.0
		mortarEnabled type:#boolean ui:chkMortar default:true
	)
	parameters pBond rollout:rBond
	(
		bondType type:#integer ui:ddlBond default:1
		startOffset type:#float ui:spnStartOffset default:0.0
	)
	parameters pShape rollout:rShape
	(
		chamfer type:#float ui:spnChamfer default:2.0
		chamferJitter type:#float ui:spnChamferJitter default:0.3
		cornerJitter type:#float ui:spnCornerJitter default:1.0
		depthJitter type:#float ui:spnDepthJitter default:1.5
		rotJitter type:#float ui:spnRotJitter default:0.3
		sizeJitter type:#float ui:spnSizeJitter default:1.0
	)
	parameters pMat rollout:rMat
	(
		matIdCount type:#integer ui:spnMatIdCount default:5
		mortarMatId type:#integer ui:spnMortarMatId default:100
		atlasFile type:#string ui:edtAtlasPath default:""
		atlasFlip type:#boolean ui:chkAtlasFlip default:true
		atlasRotate type:#boolean ui:chkAtlasRotate default:true
		-- not bound to the UI: the material holds the live values (changing a
		-- parameter would re-evaluate the modifier). Kept for older scenes.
		mortarColor type:#color default:(color 120 115 108)
		brickGloss type:#float default:30.0
	)
	parameters pView rollout:rView
	(
		previewMode type:#boolean ui:chkPreview default:false
	)

	-- ===================================================== material settings
	-- Mortar colour, gloss and relief live in the material (made by "Maak
	-- materiaal"); the controls in "Steen: textuur" and "Voeg" change it
	-- directly, without rebuilding the geometry.
	local uiMortarCol = color 120 115 108
	local uiGloss = 30.0
	local uiReliefBrick = 30.0
	local uiReliefMortar = 60.0

	fn bgNode = ( refs.dependentNodes this firstOnly:true )
	fn bgReadMaterial =
	(
		local node = bgNode()
		local st = if node != undefined then BrickGenMaterial.readSettings node.material else undefined
		if st != undefined do
		(
			uiMortarCol = st[1]
			uiGloss = st[2]
			uiReliefBrick = st[3]
			uiReliefMortar = st[4]
		)
	)
	fn bgUpdateMaterial =
	(
		local node = bgNode()
		if node != undefined do BrickGenMaterial.update node.material uiMortarCol uiGloss \
			uiReliefBrick uiReliefMortar false
	)

	-- ============================================================== rollouts
	rollout rWall "Gevel"
	(
		checkbox chkFlip "Andere kant (gevel omdraaien)"
		spinner spnSeed "Seed:" type:#integer range:[0, 999999999, 12345] across:2
		button btnNewSeed "Nieuwe" width:60 align:#right
		on btnNewSeed pressed do seed = random 1 999999
		group "Dagkanten (openingen)"
		(
			spinner spnReveal "Diepte:" type:#worldUnits range:[0, 1e6, 30]
			spinner spnRevealOffset "Offset zijkant:" type:#worldUnits range:[-1e6, 1e6, 0]
			checkbox chkRevealOuter "Ook langs de buitenrand"
		)
	)

	rollout rBond "Verband"
	(
		dropdownlist ddlBond ""
		spinner spnStartOffset "Startoffset (mm):" type:#float range:[-10000, 10000, 0]

		on rBond open do
		(
			ddlBond.items = BrickGenBonds.labels()
			ddlBond.selection = bondType
		)
	)

	rollout rBrick "Steen"
	(
		dropdownlist ddlFormat "Formaat:"
		spinner spnBrickL "Lengte L (mm):" type:#float range:[1, 1000, 210]
		spinner spnBrickB "Breedte B (mm):" type:#float range:[1, 1000, 100]
		spinner spnBrickH "Hoogte H (mm):" type:#float range:[1, 1000, 50]

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

	rollout rMat "Steen: textuur en materiaal"
	(
		group "Textuur (foto van een gevel)"
		(
			edittext edtAtlas "" readOnly:true width:140
			edittext edtAtlasPath "" readOnly:true visible:false
			button btnAtlas "Kies textuur..." width:90 across:2
			button btnAtlasClear "Geen" width:50
			button btnAtlasCheck "Stenen controleren..." width:140
			checkbox chkAtlasFlip "Random spiegelen"
			checkbox chkAtlasRotate "Random 180 graden draaien"
		)
		group "Uitzicht steen"
		(
			spinner spnGloss "Glans (%):" type:#float range:[0, 100, 30]
			spinner spnReliefBrick "Relief (%):" type:#float range:[0, 200, 30]
		)
		group "Materiaal"
		(
			button btnMakeMat "Maak materiaal" width:140 height:26
			spinner spnMatIdCount "Steen-ID's (1..N):" type:#integer range:[1, 99, 5]
			spinner spnMortarMatId "Voeg-ID:" type:#integer range:[1, 9999, 100]
		)

		fn refresh = ( edtAtlas.text = if atlasFile == "" then "(geen textuur)" else filenameFromPath atlasFile )
		on rMat open do
		(
			refresh()
			bgReadMaterial()
			spnGloss.value = uiGloss
			spnReliefBrick.value = uiReliefBrick
		)
		on spnGloss changed v do ( uiGloss = v; bgUpdateMaterial() )
		on spnReliefBrick changed v do ( uiReliefBrick = v; bgUpdateMaterial() )
		on btnAtlas pressed do
		(
			local startDir = if atlasFile != "" then getFilenamePath atlasFile
				else pathConfig.appendPath ::BrickGenRoot "presets\\atlases\\"
			local f = getOpenFileName caption:"BrickGen: baksteenfoto kiezen" filename:startDir \
				types:"Baksteenfoto (*.jpg;*.png;*.tif)|*.jpg;*.jpeg;*.png;*.tif;*.tiff|BrickGen atlas (*.json)|*.json|Alle bestanden (*.*)|*.*"
			if f != undefined do
			(
				local js = BrickGenDetect.atlasJsonFor f brickL brickB brickH bedJoint headJoint
				if js == undefined or (BrickGenAtlasLib.get js) == undefined then
					messageBox ("BrickGen vond geen bruikbare stenen in:\n" + f + \
						"\n\nGebruik een recht, vlak gefotografeerde gevel (geen perspectief) met hetzelfde steenformaat als ingesteld bij Steen.") title:"BrickGen"
				else
				(
					atlasFile = f
					try (notifyDependents this) catch ()
					refresh()
					-- an existing BrickGen material gets the new photo too
					local node = bgNode()
					if node != undefined and (BrickGenMaterial.setTexture node.material (BrickGenAtlasLib.get js)) do
						format "BrickGen: materiaal gebruikt nu %\n" (filenameFromPath f)
				)
			)
		)
		on btnAtlasCheck pressed do
		(
			local js = BrickGenDetect.atlasJsonFor atlasFile brickL brickB brickH bedJoint headJoint
			if js == undefined then messageBox "Kies eerst een textuur." title:"BrickGen"
			else BrickGenAtlasEditor_open js this
		)
		on btnAtlasClear pressed do
		(
			atlasFile = ""
			try (notifyDependents this) catch ()
			refresh()
		)
		on btnMakeMat pressed do
		(
			local node = bgNode()
			local atlas = BrickGenAtlasLib.get (BrickGenDetect.atlasJsonFor atlasFile brickL brickB brickH bedJoint headJoint)
			if atlas == undefined and atlasFile != "" do
				messageBox "De atlas kon niet gelezen worden; het materiaal krijgt een effen kleur." title:"BrickGen"
			if atlas != undefined and (BrickGenAtlasLib.mapPath atlas "diffuse") != undefined and \
				not (doesFileExist (BrickGenAtlasLib.mapPath atlas "diffuse")) do
				messageBox ("Textuur niet gevonden:\n" + (BrickGenAtlasLib.mapPath atlas "diffuse") + \
					"\n\nZet de afbeelding naast het atlas-bestand.") title:"BrickGen"
			BrickGenMaterial.makeFor node atlas matIdCount mortarMatId mortarCol:uiMortarCol gloss:uiGloss \
				reliefBrick:uiReliefBrick reliefMortar:uiReliefMortar disp:false
		)
	)

	rollout rShape "Steen: vorm en imperfectie"
	(
		spinner spnChamfer "Afronding (mm):" type:#float range:[0, 50, 2]
		spinner spnChamferJitter "Afronding-variatie:" type:#float range:[0, 1, 0.3] scale:0.01
		spinner spnCornerJitter "Hoeken (mm):" type:#float range:[0, 20, 1]
		spinner spnDepthJitter "Diepte (mm):" type:#float range:[0, 20, 1.5]
		spinner spnRotJitter "Rotatie (graden):" type:#float range:[0, 10, 0.3] scale:0.05
		spinner spnSizeJitter "Maat (mm):" type:#float range:[0, 20, 1]
	)

	rollout rJoint "Voeg"
	(
		spinner spnBedJoint "Lintvoeg (mm):" type:#float range:[0, 100, 12]
		spinner spnHeadJoint "Stootvoeg (mm):" type:#float range:[0, 100, 12]
		spinner spnRecess "Terugligging (mm):" type:#float range:[0, 100, 5]
		checkbox chkMortar "Voegvlak" checked:true
		group "Uitzicht voeg"
		(
			colorpicker cpMortar "Kleur:" color:(color 120 115 108) modal:false
			spinner spnReliefMortar "Relief (%):" type:#float range:[0, 200, 60]
		)

		on rJoint open do
		(
			bgReadMaterial()
			cpMortar.color = uiMortarCol
			spnReliefMortar.value = uiReliefMortar
		)
		on cpMortar changed c do ( uiMortarCol = c; bgUpdateMaterial() )
		on spnReliefMortar changed v do ( uiReliefMortar = v; bgUpdateMaterial() )
	)

	rollout rView "Weergave"
	(
		checkbox chkPreview "Snelle preview (geen afronding/variatie)"
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
	on modifyMesh do if mesh != undefined do
	(
		-- (mesh is undefined when 3ds Max evaluates during a rollout open)
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
			-- material-only parameters do not change the geometry
			for n in (getPropNames this) where n != #mortarColor and n != #brickGloss do format "%=%|" n (getProperty this n) to:ss
			for poly in raw do (for pt in poly do format "%," pt to:ss; format ";" to:ss)
			if atlasFile != "" and doesFileExist atlasFile do format "%|%" (getFileModDate atlasFile) ::BrickGenAtlasRev to:ss
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
			p.atlas = BrickGenAtlasLib.get (BrickGenDetect.atlasJsonFor atlasFile brickL brickB brickH bedJoint headJoint)
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
		-- (A cached TriMesh copied with meshop.attach lost its UV channels in
		-- 3ds Max 2026, so the buffer is always written; ~1 s per 15k bricks.)
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
