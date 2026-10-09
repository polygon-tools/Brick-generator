-- BrickGen_Detect.ms
-- Automatic atlas from a plain brick photo (jpg/png/tif), PLAN.md fase 3:
-- finds the bricks in the photo and writes the atlas JSON as a cache next to
-- the photo ("<foto>.brickgen.json"), so the user never needs a JSON file.
-- Same method as tools/detect_atlas.py (reference), on a reduced copy of the
-- photo (max 900 px) for speed; cell coordinates are scaled back to full size.

struct BrickGenDetectStruct
(
	maxDim = 900,
	memo = Dictionary #string, -- input signature -> JSON path (this session)

	-- percentile with linear interpolation (like numpy); p in 0..100
	fn pct arr p =
	(
		-- (no "copy": on an array it returned OK in 3ds Max 2026)
		local a = for v in arr collect v
		sort a
		local f = (p / 100.0) * (a.count - 1)
		local i = (floor f) as integer
		if i + 1 >= a.count then a[a.count] else a[i + 1] + (f - i) * (a[i + 2] - a[i + 1])
	),

	-- runs of true values, at least minLen long: #(#(start, end), ...) 0-based
	fn runs mask minLen =
	(
		local out = #()
		local s = 0
		for i = 1 to mask.count do
		(
			if mask[i] and s == 0 do s = i
			if not mask[i] and s > 0 do
			(
				if i - s >= minLen do append out #(s - 1, i - 2)
				s = 0
			)
		)
		if s > 0 and mask.count - s + 1 >= minLen do append out #(s - 1, mask.count - 1)
		out
	),

	-- cands #(#(x, strength), ...) sorted by x: highest-scoring chain whose
	-- spacings are (close to) one of the pitches. Returns the x values.
	fn bestChain cands pitches tol =
	(
		local n = cands.count
		if n == 0 do return #()
		local score = for c in cands collect c[2]
		local prev = for c in cands collect 0
		for j = 1 to n do for i = 1 to j - 1 do
		(
			local d = cands[j][1] - cands[i][1]
			local ok = false
			for p in pitches where (abs (d - p)) <= tol do ok = true
			if ok and score[i] + cands[j][2] > score[j] do
			(
				score[j] = score[i] + cands[j][2]
				prev[j] = i
			)
		)
		local j = 1
		for k = 2 to n where score[k] > score[j] do j = k
		local chain = #()
		while j > 0 do
		(
			insertItem cands[j][1] chain 1
			j = prev[j]
		)
		chain
	),

	-- Note: never pass a "for ... collect" that uses outer locals directly as a
	-- function argument in this file; 3ds Max 2026 then fails with "Bad free
	-- thunk local member index". Build the array in a local first.
	fn maskBelow arr t = ( local m = #(); for v in arr do append m (v < t); m ),

	fn columnValues g r0 r1 x = ( local vals = #(); for r = r0 to r1 do append vals g[r + 1][x]; vals ),

	fn runMin vals a b = ( local m = 1e9; for i = a to b do m = amin m vals[i + 1]; m ),

	-- Grey values of the photo on a reduced copy: #(g, W, H, sw, fs, fx, fy)
	-- with g[row][col], or undefined.
	fn readGray imgPath =
	(
		local src = openBitMap imgPath
		if src == undefined do return undefined
		local W = src.width
		local Hh = src.height
		local fs = amin 1.0 (maxDim / ((amax W Hh) as float))
		local sw = amax 1 ((W * fs) as integer)
		local sh = amax 1 ((Hh * fs) as integer)
		local sm = src
		if fs < 1.0 do
		(
			sm = bitmap sw sh
			copy src sm
		)
		local g = for y = 0 to sh - 1 collect
			for c in (getPixels sm [0, y] sw) collect (0.299 * c.r + 0.587 * c.g + 0.114 * c.b)
		if sm != src do free sm
		free src
		#(g, W, Hh, sw, fs, sw as float / W, sh as float / Hh)
	),

	-- Brick cells in grey image g, assuming joints darker than the bricks.
	-- Returns #(x, y, w, h, kind) per cell in full-size pixels (maybe empty).
	fn detectGray g sw fs fx fy L B H =
	(
		local mn = amax 1 ((2.0 * fs + 0.5) as integer)

		-- bed joints: dark rows
		local rowp = for r in g collect pct r 80
		local thr = pct rowp 18
		local rowMask = maskBelow rowp thr
		local beds = runs rowMask mn
		if beds.count < 3 do return #()
		local d = for i = 1 to beds.count - 1 collect 0.5 * (beds[i + 1][1] + beds[i + 1][2] - beds[i][1] - beds[i][2])
		local m0 = pct d 50
		-- drop spurious beds (dark specks inside a course): keep the darker one
		local keep = #(beds[1])
		for i = 2 to beds.count do
		(
			-- (no "b"/"k" names here: MAXScript is case-insensitive and B is a parameter)
			local bed = beds[i]
			local last = keep[keep.count]
			if 0.5 * (bed[1] + bed[2] - last[1] - last[2]) < 0.6 * m0 then
			(
				if (runMin rowp bed[1] bed[2]) < (runMin rowp last[1] last[2]) do keep[keep.count] = bed
			)
			else append keep bed
		)
		beds = keep
		if beds.count < 3 do return #()
		d = for i = 1 to beds.count - 1 collect 0.5 * (beds[i + 1][1] + beds[i + 1][2] - beds[i][1] - beds[i][2])
		local coursePx = pct d 50
		-- brick height and joint measured in the photo itself (the joints of
		-- the photo need not match the joints set in BrickGen)
		local gaps = for i = 1 to beds.count - 1 collect beds[i + 1][1] - beds[i][2] - 1
		local brickPx = pct gaps 50
		local jointPx = amax 1.0 (coursePx - brickPx)
		local s = brickPx / H -- px per mm
		local jw = jointPx

		-- per course: head-joint candidates #(x, strength)
		local courses = #()
		for bi = 1 to beds.count - 1 do
		(
			local y0 = beds[bi][2] + 1
			local y1 = beds[bi + 1][1] - 1
			if (y1 - y0) >= (amax 4.0 (8.0 * fs)) do
			(
				local r0 = y0 + mn
				local r1 = y1 - mn
				if r1 < r0 do ( r0 = y0; r1 = y1 )
				local col = #()
				for x = 1 to sw do
				(
					local vals = columnValues g r0 r1 x
					append col (pct vals 85)
				)
				local med = pct col 50
				local t = pct col 15
				local cands = #()
				local colMask = maskBelow col t
				local colRuns = runs colMask mn
				for q in colRuns where (q[2] - q[1]) <= 2.5 * jw do
					append cands #(0.5 * (q[1] + q[2]), med - (runMin col q[1] q[2]))
				-- every joint costs a penalty, so a weak dark spot inside a
				-- stretcher does not split it into two headers
				if cands.count > 0 do
				(
					local st = for c in cands collect c[2]
					sort st
					local strong = for i = (st.count / 2) + 1 to st.count collect st[i]
					local pen = 0.6 * (pct strong 50)
					for c in cands do c[2] -= pen
				)
				append courses #(y0, y1, cands)
			)
		)

		-- stretcher pitch measured in the photo: distances between strong
		-- head-joint candidates vote for a pitch (a distance d may be one
		-- stretcher or one header, so it votes for d and 2d); the brick
		-- format only gives the search range. Header pitch = half of it.
		local expect = L * s + jointPx
		local lo = (0.55 * expect) as integer
		local hi = (1.6 * expect) as integer
		local votes = for i = 0 to hi + 1 collect 0.0
		for crs in courses do
		(
			local xs = #()
			for c in crs[3] where c[2] > 0.0 do append xs c[1]
			for i = 1 to xs.count do
				for j = i + 1 to (amin (i + 3) xs.count) do
				(
					local dd = xs[j] - xs[i]
					for pv in #(dd, 2.0 * dd) do
					(
						local pi0 = (pv + 0.5) as integer
						if pi0 >= lo and pi0 <= hi do votes[pi0 + 1] += 1.0
					)
				)
		)
		local ps = expect
		local bestV = -1.0
		for v = lo to hi do
		(
			local sm = 0.0
			for k = v - 2 to v + 2 where k >= 0 and k <= hi + 1 do sm += votes[k + 1]
			if sm > bestV do ( bestV = sm; ps = v as float )
		)
		local tol = 0.12 * 0.5 * ps

		local cells = #()
		for pass = 1 to 2 do
		(
			-- pass 2 only when headers are rare: then they are split
			-- stretchers (stretcher bond), so chain stretchers only
			local pitches = if pass == 1 then #(ps, 0.5 * ps) else #(ps)
			local found = #()
			for crs in courses do
			(
				local y0 = crs[1]
				local y1 = crs[2]
				local ch = bestChain crs[3] pitches tol
				for i = 1 to ch.count - 1 do
				(
					local x0 = (ch[i] + 0.5 * jw + 0.5) as integer
					local x1 = (ch[i + 1] - 0.5 * jw + 0.5) as integer
					if (x1 - x0) >= 0.8 * (y1 - y0) do
					(
						local kind = if (x1 - x0 + 1) > 0.75 * ps then "stretcher" else "header"
						append found #((x0 / fx + 0.5) as integer, (y0 / fy + 0.5) as integer, \
							((x1 - x0 + 1) / fx + 0.5) as integer, ((y1 - y0 + 1) / fy + 0.5) as integer, kind)
					)
				)
			)
			local nk = 0
			for c in found where c[5] == "header" do nk += 1
			if pass == 1 then
			(
				cells = found
				if nk >= 0.2 * found.count do exit
			)
			else cells = found
		)
		cells
	),

	-- Detect the brick cells. Sizes in mm (the real brick). Joints may be
	-- darker (usual) or lighter (light mortar) than the bricks: both are tried
	-- and the result covering the largest area wins.
	-- Returns #(imageWidth, imageHeight, cells) or undefined.
	fn detect imgPath L B H bedJoint headJoint =
	(
		local info = readGray imgPath
		if info == undefined do return undefined
		local g = info[1]
		local best = #()
		local bestArea = 0.0
		for pass = 1 to 2 do
		(
			local gp = g
			if pass == 2 do gp = for r in g collect (for v in r collect 255.0 - v)
			local cells = detectGray gp info[4] info[5] info[6] info[7] L B H
			local area = 0.0
			for c in cells do area += c[3] * c[4]
			if area > bestArea do ( best = cells; bestArea = area )
		)
		#(info[2], info[3], best)
	),

	fn jsonStr s = ( "\"" + (substituteString (substituteString s "\\" "\\\\") "\"" "\\\"") + "\"" ),

	-- Sibling map next to the photo by name: foto_normal.png, foto_rough.jpg ...
	fn findSibling imgPath suffixes =
	(
		local dir = getFilenamePath imgPath
		local stem = getFilenameFile imgPath
		local res = undefined
		for sfx in suffixes do
			for ext in #(".jpg", ".jpeg", ".png", ".tif", ".tiff", ".exr") do
				if res == undefined and doesFileExist (dir + stem + sfx + ext) do res = dir + stem + sfx + ext
		res
	),

	-- file name only when the map sits next to the JSON, else the full path
	fn relPath f dirA dirB = ( if f == undefined then undefined else if (stricmp dirA dirB) == 0 then filenameFromPath f else f ),

	-- Where the cache goes: next to the photo, or in the temp folder when that
	-- folder is read-only.
	fn cachePath imgPath =
	(
		local p = (getFilenamePath imgPath) + (getFilenameFile imgPath) + ".brickgen.json"
		local ok = doesFileExist p
		if not ok do
		(
			local f = try (createFile p) catch undefined
			if f != undefined do ( close f; deleteFile p; ok = true )
		)
		if ok then p
		else
		(
			local dir = (getDir #temp) + "\\BrickGen\\"
			makeDir dir all:true
			dir + (getFilenameFile imgPath) + "_" + ((getHashValue imgPath 0) as string) + ".brickgen.json"
		)
	),

	-- signature of the detection input: photo date + brick sizes
	fn inputSig imgPath L B H bedJoint headJoint =
	(
		-- "v3": light mortar, brick length from the photo; older caches are detected again
		"v3|" + (getFileModDate imgPath) + "|" + (L as string) + "|" + (B as string) + "|" + \
			(H as string) -- joints are measured in the photo, not taken from BrickGen
	),

	-- The atlas JSON for a photo: from the cache when the photo and brick sizes
	-- are unchanged, otherwise detected and written. Returns the JSON path or
	-- undefined (message in the Listener).
	fn atlasFor imgPath L B H bedJoint headJoint =
	(
		if not (doesFileExist imgPath) do return undefined
		local out = cachePath imgPath
		local sig = inputSig imgPath L B H bedJoint headJoint
		if hasDictValue memo (sig + "|" + imgPath) and doesFileExist out do return out
		if doesFileExist out do
		(
			local old = try (BrickGenJson_parseFile out) catch undefined
			if old != undefined and (BrickGenJson_get old "source" "") == sig do
			(
				memo[sig + "|" + imgPath] = out
				return out
			)
		)
		local t0 = timeStamp()
		local res = detect imgPath L B H bedJoint headJoint
		if res == undefined or res[3].count == 0 do
		(
			format "BrickGen: geen stenen gevonden in %\n" imgPath
			return undefined
		)
		local outDir = getFilenamePath out
		local imgDir = getFilenamePath imgPath
		local maps = #( \
			#("diffuse", imgPath), \
			#("normal", findSibling imgPath #("_normal", "_nrm", "_n")), \
			#("roughness", findSibling imgPath #("_roughness", "_rough")), \
			#("bump", findSibling imgPath #("_bump", "_height", "_disp")))
		local ss = stringStream ""
		format "{\n \"version\": 1,\n \"name\": %,\n \"source\": %,\n" (jsonStr (getFilenameFile imgPath)) (jsonStr sig) to:ss
		format " \"image\": {\"width\": %, \"height\": %},\n \"maps\": {" res[1] res[2] to:ss
		for i = 1 to maps.count do
		(
			local f = relPath maps[i][2] outDir imgDir
			format "%\"%\": %" (if i > 1 then ", " else "") maps[i][1] (if f == undefined then "null" else jsonStr f) to:ss
		)
		format "},\n \"realBrick\": {\"L\": %, \"H\": %},\n \"cells\": [\n" L H to:ss
		local cells = res[3]
		local ns = 0
		for i = 1 to cells.count do
		(
			local c = cells[i]
			if c[5] == "stretcher" do ns += 1
			format "  {\"id\": %, \"x\": %, \"y\": %, \"w\": %, \"h\": %, \"kind\": \"%\", \"disabled\": false}%\n" \
				(i - 1) c[1] c[2] c[3] c[4] c[5] (if i < cells.count then "," else "") to:ss
		)
		format " ]\n}\n" to:ss
		local fh = createFile out
		if fh == undefined do ( format "BrickGen: kan % niet schrijven\n" out; return undefined )
		format "%" (ss as string) to:fh
		close fh
		memo[sig + "|" + imgPath] = out
		format "BrickGen: % stenen gevonden in % (% strek, % kop), % ms -> %\n" \
			cells.count (filenameFromPath imgPath) ns (cells.count - ns) (timeStamp() - t0) out
		out
	),

	fn isImage f = ( f != undefined and (findItem #(".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".tga") (toLower (getFilenameType f))) > 0 ),

	-- The atlas JSON for what the user picked: a JSON as is, a photo via
	-- detection (cached). Sizes in mm. undefined when nothing usable.
	fn atlasJsonFor f L B H bedJoint headJoint =
	(
		if f == undefined or f == "" then undefined
		else if isImage f then atlasFor f L B H bedJoint headJoint
		else f
	)
)

global BrickGenDetect = BrickGenDetectStruct()
