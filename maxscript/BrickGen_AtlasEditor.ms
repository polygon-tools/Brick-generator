-- BrickGen_AtlasEditor.ms
-- "Stenen controleren" (PLAN.md fase 3): shows the brick photo with a frame
-- around every detected brick (green = stretcher, blue = header, red = off).
-- Click a brick to switch it off/on; "Opslaan" writes the atlas JSON
-- ("disabled": true is skipped by BrickGen_Atlas.ms).

global BrickGenAtlasRev = 0 -- bumped on save; part of the modifier's cache signature
global BrickGenAtlasEditorState = undefined
global BrickGenAtlasEditorRollout

struct BrickGenAtlasEditorStateStruct
(
	jsonPath = "", data = undefined, cells = #(),
	photo = undefined, bm = undefined, sc = 1.0,
	owner = undefined, changed = false
)

fn BrickGenAtlasEditor_cellColor c =
(
	if (BrickGenJson_get c "disabled" false) then (color 230 30 30)
	else if (BrickGenJson_get c "kind" "stretcher") == "header" then (color 40 160 255)
	else (color 40 220 60)
)

fn BrickGenAtlasEditor_hline bm x0 x1 y col =
(
	if y >= 0 and y < bm.height do
	(
		local a = amax 0 x0
		local b = amin (bm.width - 1) x1
		if b >= a do
		(
			local row = #()
			for i = a to b do append row col
			setPixels bm [a, y] row
		)
	)
)

fn BrickGenAtlasEditor_vline bm x y0 y1 col =
(
	if x >= 0 and x < bm.width do
	(
		local one = #(col)
		for y = (amax 0 y0) to (amin (bm.height - 1) y1) do setPixels bm [x, y] one
	)
)

-- cell rectangle in display pixels: #(x0, y0, x1, y1)
fn BrickGenAtlasEditor_rect c sc =
(
	local x = BrickGenJson_get c "x" 0
	local y = BrickGenJson_get c "y" 0
	local cw = BrickGenJson_get c "w" 1
	local ch = BrickGenJson_get c "h" 1
	#((x * sc) as integer, (y * sc) as integer, ((x + cw) * sc) as integer - 1, ((y + ch) * sc) as integer - 1)
)

fn BrickGenAtlasEditor_drawCell bm c sc =
(
	local r = BrickGenAtlasEditor_rect c sc
	local col = BrickGenAtlasEditor_cellColor c
	for t = 0 to 1 do
	(
		BrickGenAtlasEditor_hline bm r[1] r[3] (r[2] + t) col
		BrickGenAtlasEditor_hline bm r[1] r[3] (r[4] - t) col
		BrickGenAtlasEditor_vline bm (r[1] + t) r[2] r[4] col
		BrickGenAtlasEditor_vline bm (r[3] - t) r[2] r[4] col
	)
	-- a cross on switched-off bricks
	if (BrickGenJson_get c "disabled" false) do
	(
		local n = amax 1 (r[3] - r[1])
		for i = 0 to n do
		(
			local yy = r[2] + ((i * (r[4] - r[2])) / n)
			local one = #(col)
			if yy >= 0 and yy < bm.height and r[1] + i < bm.width do
			(
				setPixels bm [r[1] + i, yy] one
				setPixels bm [r[3] - i, yy] one
			)
		)
	)
)

-- Redraw everything from the photo.
fn BrickGenAtlasEditor_redraw st =
(
	st.bm = copy st.photo
	for c in st.cells do BrickGenAtlasEditor_drawCell st.bm c st.sc
)

fn BrickGenAtlasEditor_counts st =
(
	local nOn = 0
	local nOff = 0
	for c in st.cells do if (BrickGenJson_get c "disabled" false) then nOff += 1 else nOn += 1
	#(nOn, nOff)
)

rollout BrickGenAtlasEditorRollout "BrickGen: stenen controleren"
(
	label lblHelp "Klik op een steen om hem uit of aan te zetten.  Groen = strek, blauw = kop, rood = uit." align:#left
	imgTag img "" width:800 height:750 align:#left
	label lblCount "" align:#left across:3
	button btnSave "Opslaan" width:100 align:#right
	button btnCancel "Annuleren" width:100 align:#right

	fn updateCount =
	(
		local n = BrickGenAtlasEditor_counts BrickGenAtlasEditorState
		lblCount.text = (n[1] as string) + " stenen gebruikt, " + (n[2] as string) + " uit"
	)

	on BrickGenAtlasEditorRollout open do
	(
		local st = BrickGenAtlasEditorState
		img.bitmap = st.bm
		updateCount()
	)

	on img lbuttonup pos flags do
	(
		local st = BrickGenAtlasEditorState
		local hit = 0
		for i = 1 to st.cells.count do
		(
			local r = BrickGenAtlasEditor_rect st.cells[i] st.sc
			if hit == 0 and pos.x >= r[1] and pos.x <= r[3] and pos.y >= r[2] and pos.y <= r[4] do hit = i
		)
		if hit > 0 do
		(
			local c = st.cells[hit]
			c["disabled"] = not (BrickGenJson_get c "disabled" false)
			st.changed = true
			if c["disabled"] then BrickGenAtlasEditor_drawCell st.bm c st.sc
			else BrickGenAtlasEditor_redraw st -- to remove the cross
			img.bitmap = st.bm
			updateCount()
		)
	)

	on btnSave pressed do
	(
		local st = BrickGenAtlasEditorState
		local n = BrickGenAtlasEditor_counts st
		if n[1] == 0 then messageBox "Laat minstens een steen aan." title:"BrickGen"
		else
		(
			if BrickGenJson_writeFile st.jsonPath st.data then
			(
				BrickGenAtlasRev += 1
				-- forget cached atlases: the file may keep the same date stamp
				BrickGenAtlasLib.cache = Dictionary #string
				if st.owner != undefined do try (notifyDependents st.owner) catch ()
				format "BrickGen: atlas bewaard (% stenen, % uit) -> %\n" n[1] n[2] st.jsonPath
				destroyDialog BrickGenAtlasEditorRollout
			)
			else messageBox ("Kan niet schrijven:\n" + st.jsonPath) title:"BrickGen"
		)
	)

	on btnCancel pressed do destroyDialog BrickGenAtlasEditorRollout
)

-- Open the editor for an atlas JSON. owner = the modifier to rebuild on save.
fn BrickGenAtlasEditor_open jsonPath owner =
(
	local data = try (BrickGenJson_parseFile jsonPath) catch undefined
	if data == undefined do ( messageBox ("Atlas niet leesbaar:\n" + jsonPath) title:"BrickGen"; return false )
	local maps = BrickGenJson_get data "maps" undefined
	local imgPath = BrickGenAtlasLib.resolve (getFilenamePath jsonPath) (BrickGenJson_get maps "diffuse" undefined)
	if imgPath == undefined or not (doesFileExist imgPath) do
	(
		messageBox ("Foto niet gevonden:\n" + (imgPath as string)) title:"BrickGen"
		return false
	)
	local src = openBitMap imgPath
	if src == undefined do return false
	-- scaled to fit 800 x 750 px, top-left on a dark canvas of exactly the
	-- control's size (so click positions are canvas pixels)
	local sc = amin 1.0 (amin (800.0 / src.width) (750.0 / src.height))
	local pw = amax 1 ((src.width * sc) as integer)
	local ph = amax 1 ((src.height * sc) as integer)
	local small = bitmap pw ph
	copy src small
	free src
	local photo = bitmap 800 750 color:(color 45 45 45)
	pasteBitmap small photo (box2 0 0 pw ph) [0, 0]
	free small
	local st = BrickGenAtlasEditorStateStruct jsonPath:jsonPath data:data owner:owner \
		cells:(BrickGenJson_get data "cells" #()) photo:photo sc:sc
	BrickGenAtlasEditor_redraw st
	BrickGenAtlasEditorState = st
	try (destroyDialog BrickGenAtlasEditorRollout) catch ()
	createDialog BrickGenAtlasEditorRollout 830 830 modal:false
	true
)
