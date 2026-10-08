-- BrickGen_MakeTestScene.ms
-- Builds testscenes/test_gevel.max (PLAN.md §12 fase 0): camera, light, ground
-- plane and a 3 x 2.5 m BrickWall. Run after BrickGen_Startup.ms in an empty scene.
-- The .max file is binary and version-specific, so this script is the source;
-- re-run it to regenerate the scene.

(
	fn mm v = units.decodeValue ((v as string) + "mm")

	resetMaxFile #noPrompt
	units.SystemType = #millimeters

	Plane name:"BG_Ground" length:(mm 8000) width:(mm 10000) pos:[(mm 1500), -(mm 2000), 0]

	local wall = BrickWall name:"BG_TestWall" pos:[0, 0, 0]
	wall.wallLength = mm 3000
	wall.wallHeight = mm 2500

	-- camera in front of the wall (wall faces -Y), at eye height
	local cam = Targetcamera name:"BG_Cam" fov:45 \
		pos:[(mm 1500), -(mm 5500), (mm 1600)] \
		target:(Targetobject name:"BG_Cam.Target" pos:[(mm 1500), 0, (mm 1250)])

	-- grazing sun from the left so chamfers and recessed joints read clearly
	local sunPos = [-(mm 6000), -(mm 4000), (mm 5000)]
	try ( VRaySun name:"BG_Sun" pos:sunPos target:(Targetobject pos:[(mm 1500), 0, 0]) )
	catch ( Directionallight name:"BG_Sun" pos:sunPos )

	viewport.setCamera cam
	local f = pathConfig.appendPath (getFilenamePath (getThisScriptFilename())) "test_gevel.max"
	saveMaxFile f quiet:true
	format "Testscene opgeslagen: %\n" f
)
