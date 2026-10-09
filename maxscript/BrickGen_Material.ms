-- BrickGen_Material.ms
-- "Maak materiaal" (PLAN.md §10): a Multi/Sub-Object material for a BrickGen
-- wall. IDs 1..N = bricks (atlas maps on UV channel 1; the variation comes from
-- the atlas, every ID gets the same brick material), mortarMatId = mortar.
-- V-Ray when installed, otherwise Physical Material.

struct BrickGenMaterialStruct
(
	fn hasVRay = ( (try (VRayMtl()) catch undefined) != undefined ),

	fn bitmapOn f ch =
	(
		if f == undefined or not (doesFileExist f) then undefined
		else
		(
			local b = Bitmaptexture fileName:f name:(getFilenameFile f)
			-- the atlas UVs are exact 0..1 image coordinates: no real-world
			-- scale, no tiling, no offset
			try (b.coords.realWorldScale = false) catch ()
			b.coords.mapChannel = ch
			b.coords.U_Tiling = 1.0
			b.coords.V_Tiling = 1.0
			b.coords.U_Offset = 0.0
			b.coords.V_Offset = 0.0
			b.coords.blur = 0.2
			b
		)
	),

	-- gloss 0..100 (%): strength of the brick's reflection
	fn reflColor gloss = ( local g = 255.0 * (amax 0.0 (amin 100.0 gloss)) / 100.0; color g g g ),

	-- Fine fractal noise in object space (size in mm): sand grain of the mortar.
	fn mortarNoise =
	(
		local n = Noise name:"BrickGen_VoegKorrel"
		n.type = 1 -- fractal
		n.size = units.decodeValue "2.5mm"
		n.levels = 4.0
		n
	),

	-- Relief: bump (always, cheap) and optionally displacement (render time,
	-- no viewport geometry). Works on VRayMtl and Physical Material.
	-- relief 0..100 (%); map = the height source (brick photo / mortar noise).
	fn setRelief m map relief disp =
	(
		if classOf m == VRayMtl then
		(
			-- an atlas normal map (VRayNormalMap) keeps its own bump slot
			if classOf m.texmap_bump != VRayNormalMap do
			(
				m.texmap_bump = map
				try (m.texmap_bump_on = map != undefined) catch ()
			)
			m.texmap_bump_multiplier = relief
			try
			(
				m.texmap_displacement = if disp then map else undefined
				m.texmap_displacement_on = disp and map != undefined
				m.texmap_displacement_multiplier = relief
			) catch ()
		)
		else if classOf m == PhysicalMaterial do
		(
			if classOf m.bump_map != Normal_Bump do m.bump_map = map
			m.bump_map_amt = relief / 100.0
			try
			(
				m.displacement_map = if disp then map else undefined
				m.displacement_map_on = disp and map != undefined
			) catch ()
		)
	),

	-- The height source of a BrickGen sub-material: the brick photo, or the
	-- mortar noise (created once and kept).
	fn reliefSource m isMortar =
	(
		local map = undefined
		if isMortar then
		(
			map = if classOf m == VRayMtl then m.texmap_bump else if classOf m == PhysicalMaterial then m.bump_map else undefined
			if classOf map != Noise do map = mortarNoise()
		)
		else
		(
			map = if classOf m == VRayMtl then m.texmap_diffuse else if classOf m == PhysicalMaterial then m.base_color_map else undefined
		)
		map
	),

	fn brickMaterial atlas vray gloss:30.0 =
	(
		local diff = if atlas != undefined then bitmapOn (BrickGenAtlasLib.mapPath atlas "diffuse") 1 else undefined
		local nrm = if atlas != undefined then bitmapOn (BrickGenAtlasLib.mapPath atlas "normal") 1 else undefined
		local rough = if atlas != undefined then bitmapOn (BrickGenAtlasLib.mapPath atlas "roughness") 1 else undefined
		local m = undefined
		if vray then
		(
			m = VRayMtl name:"BrickGen_Steen"
			m.diffuse = color 150 75 55
			if diff != undefined do m.texmap_diffuse = diff
			m.reflection = reflColor gloss
			m.reflection_glossiness = 0.45
			if rough != undefined do
			(
				m.brdf_useRoughness = true
				m.texmap_reflectionGlossiness = rough
			)
			if nrm != undefined do
			(
				m.texmap_bump = VRayNormalMap normal_map:nrm
				m.texmap_bump_multiplier = 100.0
			)
		)
		else
		(
			m = PhysicalMaterial name:"BrickGen_Steen"
			m.base_color = color 150 75 55
			if diff != undefined do m.base_color_map = diff
			m.roughness = 0.8
			m.reflectivity = gloss / 100.0
			if rough != undefined do m.roughness_map = rough
			if nrm != undefined do m.bump_map = Normal_Bump normal_map:nrm
		)
		showTextureMap m true
		m
	),

	fn mortarMaterial vray c:(color 120 115 108) =
	(
		local m = if vray then (VRayMtl name:"BrickGen_Voeg" diffuse:c reflection:(color 40 40 40) reflection_glossiness:0.3)
			else (PhysicalMaterial name:"BrickGen_Voeg" base_color:c roughness:0.95)
		m
	),

	-- Sub-materials of a material made by makeFor: #(brick, mortar), either
	-- may be undefined. Found by name, so a material from elsewhere is ignored.
	fn findSubs mm =
	(
		local brick = undefined
		local mortar = undefined
		if classOf mm == Multimaterial do
			for sub in mm.materialList where sub != undefined do
			(
				if sub.name == "BrickGen_Steen" do brick = sub
				if sub.name == "BrickGen_Voeg" do mortar = sub
			)
		#(brick, mortar)
	),

	-- Current settings of a BrickGen material, for the UI:
	-- #(mortarColour, gloss %, brick relief %, mortar relief %, displacement)
	-- or undefined when mm is not a BrickGen material.
	fn readSettings mm =
	(
		local subs = findSubs mm
		local b = subs[1]
		local v = subs[2]
		if b == undefined and v == undefined do return undefined
		local res = #(color 120 115 108, 30.0, 30.0, 60.0, false)
		if v != undefined do
		(
			if classOf v == VRayMtl then ( res[1] = v.diffuse; res[4] = v.texmap_bump_multiplier )
			else if classOf v == PhysicalMaterial do ( res[1] = v.base_color; res[4] = v.bump_map_amt * 100.0 )
		)
		if b != undefined do
		(
			if classOf b == VRayMtl then
			(
				res[2] = 100.0 * b.reflection.value / 255.0
				res[3] = b.texmap_bump_multiplier
				res[5] = try (b.texmap_displacement != undefined and b.texmap_displacement_on) catch false
			)
			else if classOf b == PhysicalMaterial do
			(
				res[2] = 100.0 * b.reflectivity
				res[3] = b.bump_map_amt * 100.0
				res[5] = try (b.displacement_map != undefined and b.displacement_map_on) catch false
			)
		)
		res
	),

	-- Live update of a material made by makeFor (only its BrickGen_Steen and
	-- BrickGen_Voeg sub-materials). Never touches the geometry.
	fn update mm mortarCol gloss reliefBrick reliefMortar disp =
	(
		local subs = findSubs mm
		local b = subs[1]
		local v = subs[2]
		if v != undefined do
		(
			if classOf v == VRayMtl then v.diffuse = mortarCol
			else if classOf v == PhysicalMaterial do v.base_color = mortarCol
			setRelief v (reliefSource v true) reliefMortar disp
		)
		if b != undefined do
		(
			if classOf b == VRayMtl then b.reflection = reflColor gloss
			else if classOf b == PhysicalMaterial do b.reflectivity = gloss / 100.0
			setRelief b (reliefSource b false) reliefBrick disp
		)
	),

	-- After "Kies textuur": point the brick photo of an existing BrickGen
	-- material to the new atlas' diffuse map (the relief uses the same bitmap).
	-- Returns true when a material was updated.
	fn setTexture mm atlas =
	(
		local b = (findSubs mm)[1]
		local f = if atlas != undefined then BrickGenAtlasLib.mapPath atlas "diffuse" else undefined
		if b == undefined or f == undefined or not (doesFileExist f) then false
		else
		(
			local map = if classOf b == VRayMtl then b.texmap_diffuse
				else if classOf b == PhysicalMaterial then b.base_color_map else undefined
			if classOf map == Bitmaptexture then
			(
				map.fileName = f
				map.name = getFilenameFile f
				true
			)
			else false
		)
	),

	-- Builds the material and assigns it to node. Returns the material.
	fn makeFor node atlas matIdCount mortarMatId mortarCol:(color 120 115 108) gloss:30.0 \
		reliefBrick:30.0 reliefMortar:60.0 disp:false =
	(
		local vray = hasVRay()
		local brick = brickMaterial atlas vray gloss:gloss
		local mortar = mortarMaterial vray c:mortarCol
		setRelief brick (reliefSource brick false) reliefBrick disp
		setRelief mortar (reliefSource mortar true) reliefMortar disp
		local n = amax 1 matIdCount
		local mname = "BrickGen_" + (if atlas != undefined then atlas.name else "Gevel")
		local mm = Multimaterial name:mname numsubs:(n + 1)
		local sparse = true
		try ( mm.materialIDList = (for i = 1 to n collect i) + #(mortarMatId) ) catch ( sparse = false )
		if sparse then
		(
			for i = 1 to n do ( mm.materialList[i] = brick; mm.names[i] = "Steen " + (i as string) )
			mm.materialList[n + 1] = mortar
			mm.names[n + 1] = "Voeg"
		)
		else
		(
			-- fallback: one slot per ID up to the mortar ID
			mm = Multimaterial name:mname numsubs:(amax (n + 1) mortarMatId)
			for i = 1 to n do mm.materialList[i] = brick
			mm.materialList[mortarMatId] = mortar
		)
		if node != undefined do node.material = mm
		format "BrickGen: materiaal % aangemaakt (%)\n" mm.name (if vray then "V-Ray" else "Physical")
		mm
	)
)

global BrickGenMaterial = BrickGenMaterialStruct()
