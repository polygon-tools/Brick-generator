-- BrickGen_Bonds.ms
-- Bond (verband) definitions as data + course layout (PLAN.md §7).
--
-- A bond is a repeating list of courses. Each course is
--   #(offsetCoeffs, units)
-- offsetCoeffs = [aL, aB, aJ]  ->  offset = aL*L + aB*B + aJ*headJoint  (mm)
-- units        = repeating sequence of
--                  #S  stretcher (length L, followed by headJoint)
--                  #K  header    (length B, followed by headJoint)
--                  #KM header on half a stretcher module: pitch (L + headJoint)/2, so
--                      two headers always line up with one stretcher (kruisverband)
--                  #Q  queen closer (klezoor), (L - B)/2 - headJoint: after a header at
--                      a corner, so the next header is centred on a stretcher
--
-- Corners (next to openings): bond.corners is a cycle of per-course specs
--   #(cornerUnit, prefixUnits, repeatUnits)
-- cornerUnit = what the corner brick shows on the facade (#S or #K; the reveal
-- sees the other one); then prefixUnits once and repeatUnits over and over,
-- set out from the corner. Empty = alternate #S/#K with stretchers (halfsteens).
--
-- Adding a bond = adding one BrickGenBonds.register call at the bottom of this file.
-- The dropdown order is the registration order; never reorder existing bonds,
-- scenes store the index.

struct BrickGenBond
(
	id = #none,
	label = "",
	courses = #(),
	wild = false,   -- random offset per course (wild verband)
	corners = #()   -- corner specs per course, see above
)

struct BrickGenBondsStruct
(
	defs = #(),

	fn register def = ( append defs def; defs.count ),

	fn labels = ( for d in defs collect d.label ),

	fn get i = ( if i >= 1 and i <= defs.count then defs[i] else defs[1] ),

	fn unitLength u L B hj:12.0 =
	(
		case u of
		(
			#K: B
			#KM: B
			#Q: amax 10.0 (0.5 * (L - B) - hj)
			default: L
		)
	),

	-- distance from the start of this unit to the start of the next one
	fn unitPitch u L B hj = ( if u == #KM then 0.5 * (L + hj) else (unitLength u L B hj:hj) + hj ),

	-- Corner spec #(cornerUnit, prefixUnits, repeatUnits) for course c (0-based).
	fn cornerSpec bond c =
	(
		if bond.corners.count == 0 then
			(if (mod c 2) == 0 then #(#S, #(), #(#S)) else #(#K, #(), #(#S)))
		else
		(
			local n = bond.corners.count
			bond.corners[(c - (c / n) * n) + 1]
		)
	),

	-- Spec whose corner unit is u (used in the reveal, which sees the other
	-- face of the corner brick).
	fn cornerSpecFor bond u =
	(
		local found = undefined
		for i = 0 to (amax 2 bond.corners.count) - 1 while found == undefined do
		(
			local s = cornerSpec bond i
			if s[1] == u do found = s
		)
		if found == undefined then #(u, #(), #(#S)) else found
	),

	-- Units set out from a corner in [x0, x1]: prefix once, then repeat.
	-- fromLeft: first unit starts at x0; else last unit ends at x1 (mirrored).
	-- Result #(#(xa, xb, unit, k), ...) like layoutCourse.
	fn anchoredUnits prefix repeatUnits x0 x1 hj L B fromLeft =
	(
		local res = #()
		local len = x1 - x0
		local x = 0.0
		local k = 0
		local nr = amax 1 repeatUnits.count
		while x < len and k < 100000 do
		(
			local u = if k < prefix.count then prefix[k + 1] \
				else repeatUnits[(mod (k - prefix.count) nr) as integer + 1]
			local w = unitLength u L B hj:hj
			if fromLeft then append res #(x0 + x, x0 + x + w, u, k)
			else append res #(x1 - x - w, x1 - x, u, k)
			x += unitPitch u L B hj
			k += 1
		)
		res
	),

	fn courseDef bond c = -- c is 0-based
	(
		local n = bond.courses.count
		bond.courses[(c - (c / n) * n) + 1]
	),

	-- Offsets (mm) for courses 0..nCourses-1, before startOffset.
	fn courseOffsets bond nCourses seed L B hj minOverlap =
	(
		local offs = #()
		if not bond.wild then
		(
			for c = 0 to nCourses - 1 do
			(
				local k = (courseDef bond c)[1]
				append offs (k.x * L + k.y * B + k.z * hj)
			)
		)
		else
		(
			-- Wild: every course shifted by a random step in [minOverlap, 1-minOverlap]
			-- of a stretcher module. Rejected:
			--  * head joints (almost) above those two courses lower;
			--  * three equal steps in a row (visible "trapjes").
			local Lm = L + hj
			local steps = #()
			if nCourses > 0 do append offs 0.0
			for c = 1 to nCourses - 1 do
			(
				local chosen = undefined
				local t = 1
				while chosen == undefined do
				(
					local key = BrickGenRNG.brickKey seed (-1 - c)
					local s = Lm * (minOverlap + (1.0 - 2.0 * minOverlap) * (BrickGenRNG.u01 key t))
					local o = mod (offs[c] + s) Lm
					local ok = true
					if c >= 2 do
					(
						local d = abs (mod (o - offs[c - 1]) Lm)
						d = amin d (Lm - d)
						if d < 0.5 * minOverlap * Lm do ok = false
					)
					if ok and steps.count >= 2 do
					(
						local s1 = steps[steps.count]
						local s2 = steps[steps.count - 1]
						if (abs (s - s1)) < 0.08 * Lm and (abs (s1 - s2)) < 0.08 * Lm do ok = false
					)
					if ok or t >= 16 do chosen = #(o, s)
					t += 1
				)
				append offs chosen[1]
				append steps chosen[2]
			)
		)
		offs
	),

	-- Lay out one course along [0, wallLen].
	-- Returns #(xStart, xEnd, unit, k) per unit that touches the wall; xStart/xEnd
	-- are the unclipped positions, k is the stable index of the unit in the course.
	fn layoutCourse cdef offset wallLen hj L B =
	(
		local units = cdef[2]
		local n = units.count
		local period = 0.0
		for u in units do period += unitPitch u L B hj
		local res = #()
		if period <= 0.0 do return res

		-- start of the pattern at or just left of x = 0
		local x = mod offset period
		if x > 0.0 do x -= period
		-- k counts from the pattern start nearest to offset, so it is stable when
		-- the wall gets longer.
		local k = 0
		while x < wallLen and k < 200000 do
		(
			local u = units[(k - (k / n) * n) + 1]
			local xb = x + (unitLength u L B)
			if xb > 0.0 do append res #(x, xb, u, k)
			x += unitPitch u L B hj
			k += 1
		)
		res
	)
)

global BrickGenBonds = BrickGenBondsStruct()

-- 1. Halfsteens (stretcher bond)
BrickGenBonds.register (BrickGenBond id:#stretcher label:"Halfsteens" courses:#(
	#([0, 0, 0],     #(#S)),
	#([0.5, 0, 0.5], #(#S))
))

-- 2. Staand / stapelverband (stack bond)
BrickGenBonds.register (BrickGenBond id:#stack label:"Staand (stapel)" corners:#(
	#(#S, #(), #(#S))
) courses:#(
	#([0, 0, 0], #(#S))
))

-- 3. Vlaams verband: S-K alternating, headers centred on the stretcher below.
BrickGenBonds.register (BrickGenBond id:#flemish label:"Vlaams" corners:#(
	#(#S, #(), #(#K, #S)),
	#(#K, #(#Q), #(#S, #K))
) courses:#(
	#([0, 0, 0],      #(#S, #K)),
	#([0.5, -0.5, 0], #(#K, #S))
))

-- 4. Kruisverband: stretcher / header courses, every second stretcher course
--    shifted half a brick; headers centred on the head joints below.
BrickGenBonds.register (BrickGenBond id:#englishCross label:"Kruisverband" corners:#(
	#(#S, #(), #(#S)),
	#(#K, #(#Q), #(#KM)),
	#(#K, #(), #(#S)),
	#(#K, #(#Q), #(#KM))
) courses:#(
	#([0, 0, 0],      #(#S)),
	#([1, -0.5, 0.5], #(#KM)),
	#([0.5, 0, 0.5],  #(#S)),
	#([1, -0.5, 0.5], #(#KM))
))

-- 5. Wild verband: stretchers with random offset per course.
BrickGenBonds.register (BrickGenBond id:#wild label:"Wild" wild:true courses:#(
	#([0, 0, 0], #(#S))
))
