-- BrickGen_Atlas.ms
-- Texture atlas (PLAN.md §9): read an atlas JSON and map every brick's
-- 0..1 UV (channel 1) onto a random cell of the source texture.
-- Atlases are cached per file (reloaded when the file changes).

struct BrickGenAtlas
(
	path = "", dir = "", name = "",
	maps = undefined,    -- Dictionary: diffuse / normal / roughness / bump -> absolute path or undefined
	stretchers = #(),    -- cells #(u0, v0, u1, v1, aspect) in UV, v up
	headers = #(),
	realL = 210.0, realH = 50.0
)

struct BrickGenAtlasLibStruct
(
	cache = Dictionary #string,

	fn resolve dir f =
	(
		if f == undefined or f == "" then undefined
		else if (pathIsNetworkPath f) or (findString f ":") != undefined then f
		else pathConfig.appendPath dir f
	),

	fn load path =
	(
		local data = BrickGenJson_parseFile path
		if data == undefined do return undefined
		local a = BrickGenAtlas path:path dir:(getFilenamePath path)
		a.name = BrickGenJson_get data "name" (getFilenameFile path)
		local img = BrickGenJson_get data "image" undefined
		-- MAXScript is case-insensitive: imgW/imgH must not be called W/H, they
		-- would be the same variables as the cell's w/h below.
		local imgW = (BrickGenJson_get img "width" 1) as float
		local imgH = (BrickGenJson_get img "height" 1) as float
		local rb = BrickGenJson_get data "realBrick" undefined
		a.realL = (BrickGenJson_get rb "L" 210) as float
		a.realH = (BrickGenJson_get rb "H" 50) as float
		local m = BrickGenJson_get data "maps" undefined
		a.maps = Dictionary #string
		for k in #("diffuse", "normal", "roughness", "bump") do
		(
			local f = resolve a.dir (BrickGenJson_get m k undefined)
			if f != undefined do a.maps[k] = f
		)
		for c in (BrickGenJson_get data "cells" #()) where not (BrickGenJson_get c "disabled" false) do
		(
			local cx = (BrickGenJson_get c "x" 0) as float
			local cy = (BrickGenJson_get c "y" 0) as float
			local cw = (BrickGenJson_get c "w" 1) as float
			local ch = (BrickGenJson_get c "h" 1) as float
			-- pixel origin top-left -> UV origin bottom-left
			local cell = #(cx / imgW, 1.0 - (cy + ch) / imgH, (cx + cw) / imgW, 1.0 - cy / imgH, cw / ch)
			if (BrickGenJson_get c "kind" "stretcher") == "header" then append a.headers cell
			else append a.stretchers cell
		)
		if a.stretchers.count == 0 and a.headers.count == 0 do return undefined
		a
	),

	-- Absolute path of a map ("diffuse", "normal", ...) or undefined.
	fn mapPath atlas k = ( if hasDictValue atlas.maps k then atlas.maps[k] else undefined ),

	-- Cached load; undefined when the file is missing or unreadable.
	fn get path =
	(
		if path == undefined or path == "" or not (doesFileExist path) do return undefined
		local k = path + "|" + (getFileModDate path)
		if hasDictValue cache k then cache[k]
		else
		(
			local a = undefined
			try ( a = load path )
			catch ( format "BrickGen: atlas % niet leesbaar: %\n" path (getCurrentException()) )
			if a != undefined do cache[k] = a
			a
		)
	),

	-- Map a brick's 0..1 UVs (array of point3, in place) onto a random cell.
	-- r = BrickGenRNG.u01x3 of the brick's atlas channel: cell, flip, rotate.
	-- unit: #S / #K / #KM; aspect = nominal brick length / height (mm).
	-- When cell and brick proportions differ, the cell is cropped around its
	-- centre (never stretched).
	fn mapBrick atlas uvs r unit aspect allowFlip allowRotate =
	(
		local pool = if (unit == #K or unit == #KM) and atlas.headers.count > 0 then atlas.headers
			else if atlas.stretchers.count > 0 then atlas.stretchers else atlas.headers
		local cell = pool[amin pool.count (1 + ((floor (r.x * pool.count)) as integer))]
		local u0 = cell[1]
		local v0 = cell[2]
		local du = cell[3] - cell[1]
		local dv = cell[4] - cell[2]
		-- centre crop to the brick's proportions
		if cell[5] > aspect then
		(
			local f = aspect / cell[5]
			u0 += 0.5 * du * (1.0 - f)
			du *= f
		)
		else
		(
			local f = cell[5] / aspect
			v0 += 0.5 * dv * (1.0 - f)
			dv *= f
		)
		local flipU = allowFlip and r.y >= 0.5
		local rot = allowRotate and r.z >= 0.5
		for i = 1 to uvs.count do
		(
			local u = uvs[i].x
			local v = uvs[i].y
			if flipU do u = 1.0 - u
			if rot do ( u = 1.0 - u; v = 1.0 - v )
			uvs[i] = [u0 + u * du, v0 + v * dv, 0.0]
		)
		uvs
	)
)

global BrickGenAtlasLib = BrickGenAtlasLibStruct()
