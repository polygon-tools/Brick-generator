-- BrickGen_Presets.ms
-- Brick format presets (presets/formats.json), with built-in fallback.

struct BrickGenFormat ( name = "", L = 210.0, B = 100.0, H = 50.0 )

struct BrickGenFormatsStruct
(
	items = #(),

	fn builtin =
	(
		#(
			BrickGenFormat name:"Waalformaat"  L:210.0 B:100.0 H:50.0,
			BrickGenFormat name:"Dikformaat"   L:210.0 B:100.0 H:65.0,
			BrickGenFormat name:"Vechtformaat" L:210.0 B:100.0 H:40.0,
			BrickGenFormat name:"Modulair"     L:190.0 B:90.0  H:50.0
		)
	),

	fn load path =
	(
		items = #()
		try
		(
			local data = BrickGenJson_parseFile path
			for f in (BrickGenJson_get data "formats" #()) do
				append items (BrickGenFormat \
					name:(BrickGenJson_get f "name" "?") \
					L:((BrickGenJson_get f "L" 210) as float) \
					B:((BrickGenJson_get f "B" 100) as float) \
					H:((BrickGenJson_get f "H" 50) as float))
		)
		catch
		(
			format "BrickGen: kon % niet lezen: %\n" path (getCurrentException())
		)
		if items.count == 0 do items = builtin()
		items.count
	),

	fn names = ( for f in items collect f.name ),

	fn get i = ( if i >= 1 and i <= items.count then items[i] else undefined )
)

global BrickGenFormats = BrickGenFormatsStruct()
BrickGenFormats.items = BrickGenFormats.builtin()
