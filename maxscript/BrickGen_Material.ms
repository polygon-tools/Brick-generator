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

	-- Live update of a material made by makeFor: mortar colour and brick gloss.
	-- Only touches sub-materials named BrickGen_Voeg / BrickGen_Steen.
	fn updateColors mm mortarCol gloss =
	(
		if classOf mm == Multimaterial do
		(
			local done = #()
			for sub in mm.materialList where sub != undefined and (findItem done sub) == 0 do
			(
				append done sub
				if sub.name == "BrickGen_Voeg" do
				(
					if isProperty sub #diffuse then sub.diffuse = mortarCol
					else if isProperty sub #base_color do sub.base_color = mortarCol
				)
				if sub.name == "BrickGen_Steen" do
				(
					if isProperty sub #reflection then sub.reflection = reflColor gloss
					else if isProperty sub #reflectivity do sub.reflectivity = gloss / 100.0
				)
			)
		)
	),

	-- Builds the material and assigns it to node. Returns the material.
	fn makeFor node atlas matIdCount mortarMatId mortarCol:(color 120 115 108) gloss:30.0 =
	(
		local vray = hasVRay()
		local brick = brickMaterial atlas vray gloss:gloss
		local mortar = mortarMaterial vray c:mortarCol
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
