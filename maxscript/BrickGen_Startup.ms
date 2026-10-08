-- BrickGen_Startup.ms
-- Loads BrickGen and registers macroscripts.
--
-- Install: put a one-line script in your user startup folder
--   (#userStartupScripts, e.g. %LOCALAPPDATA%\Autodesk\3dsMax\<ver>\ENU\scripts\startup\BrickGen_Loader.ms):
--     fileIn @"<pad naar repo>\maxscript\BrickGen_Startup.ms"
-- It must run at startup: scenes with BrickWall objects need the plugin
-- definition before they are opened.

(
	local dir = getFilenamePath (getThisScriptFilename())
	global BrickGenRoot = pathConfig.removePathLeaf (trimRight dir "\\/")

	for f in #(
		"BrickGen_RNG.ms",
		"BrickGen_Json.ms",
		"BrickGen_Presets.ms",
		"BrickGen_Bonds.ms",
		"BrickGen_UV.ms",
		"BrickGen_Mesh.ms",
		"BrickGen_Object.ms",
		"BrickGen_Modifier.ms"
	) do fileIn (dir + f)

	::BrickGenFormats.load (pathConfig.appendPath BrickGenRoot "presets\\formats.json")
	format "BrickGen geladen uit %\n" ::BrickGenRoot
)

macroScript BrickGen_CreateWall
	category:"BrickGen"
	buttonText:"BrickWall"
	tooltip:"BrickGen: baksteenmuur tekenen"
(
	startObjectCreation BrickWall
)
