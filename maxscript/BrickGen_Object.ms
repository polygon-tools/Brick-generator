-- BrickGen_Object.ms
-- Scripted plugin BrickWall (Create panel > Geometry > BrickGen).
-- Requires BrickGen_RNG/Json/Presets/Bonds/UV/Mesh to be loaded first
-- (BrickGen_Startup.ms does this).
--
-- Never change classID; scenes use it to find the plugin.
-- Never remove or reorder parameters; add new ones at the end of a block.

struct BrickGenSettingsStruct ( logTiming = false, slowBuildMs = 500 )
global BrickGenSettings
if BrickGenSettings == undefined do BrickGenSettings = BrickGenSettingsStruct()

plugin simpleObject BrickWall
	name:"BrickWall"
	classID:#(0x6a3f2b11, 0x4c7d19e5)
	category:"BrickGen"
	version:1
(
	-- ------------------------------------------------------------------ Muur
	parameters pWall rollout:rWall
	(
		wallLength type:#worldUnits ui:spnLength default:3000.0
		wallHeight type:#worldUnits ui:spnHeight default:2500.0
		seed type:#integer ui:spnSeed default:12345
	)
	rollout rWall "Muur"
	(
		spinner spnLength "Lengte:" type:#worldUnits range:[0, 1e7, 0]
		spinner spnHeight "Hoogte:" type:#worldUnits range:[0, 1e7, 0]
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

	-- ----------------------------------------------------------------- Build
	on buildMesh do
	(
		local t0 = timeStamp()
		local s = units.decodeValue "1mm" -- system units per mm
		local p = BrickGenWallParams()
		p.unitScale = s
		p.wallLength = wallLength / s
		p.wallHeight = wallHeight / s
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

		local buf = BrickGenMesh.buildWall p
		BrickGenMesh.applyToMesh mesh buf

		local ms = timeStamp() - t0
		if BrickGenSettings.logTiming or ms > BrickGenSettings.slowBuildMs do
			format "BrickGen: % x % mm, % stenen, % tris, % ms\n" \
				(p.wallLength as integer) (p.wallHeight as integer) buf.brickCount buf.faces.count ms
	)

	on create do
	(
		local s = units.decodeValue "1mm"
		wallLength = 3000.0 * s
		wallHeight = 2500.0 * s
	)

	-- draw: click = start, drag = length (X), move = height, click = done
	tool create
	(
		on mousePoint click do
			case click of
			(
				1: nodeTM.translation = gridPoint
				3: #stop
			)
		on mouseMove click do
			case click of
			(
				2: wallLength = abs gridDist.x
				3: wallHeight = abs gridDist.y
			)
	)
)
