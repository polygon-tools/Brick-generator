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
--
-- Adding a bond = adding one BrickGenBonds.register call at the bottom of this file.
-- The dropdown order is the registration order; never reorder existing bonds,
-- scenes store the index.

struct BrickGenBond
(
	id = #none,
	label = "",
	courses = #(),
	wild = false,           -- random offset per course (wild verband)
	cornerAlternate = true  -- corner bricks alternate stretcher/header per course
)

struct BrickGenBondsStruct
(
	defs = #(),

	fn register def = ( append defs def; defs.count ),

	fn labels = ( for d in defs collect d.label ),

	fn get i = ( if i >= 1 and i <= defs.count then defs[i] else defs[1] ),

	fn unitLength u L B = ( if u == #K or u == #KM then B else L ),

	-- distance from the start of this unit to the start of the next one
	fn unitPitch u L B hj = ( if u == #KM then 0.5 * (L + hj) else (unitLength u L B) + hj ),

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
	),

	-- Lay out one course in [x0, x1] starting with a full unit at x0 (fromLeft)
	-- or ending with one at x1: the bond is set out from a corner.
	-- Same result format as layoutCourse.
	fn anchoredCourse cdef x0 x1 hj L B fromLeft =
	(
		local len = x1 - x0
		for pc in (layoutCourse cdef 0.0 len hj L B) collect
			if fromLeft then #(x0 + pc[1], x0 + pc[2], pc[3], pc[4])
			else #(x1 - pc[2], x1 - pc[1], pc[3], pc[4])
	)
)

global BrickGenBonds = BrickGenBondsStruct()

-- 1. Halfsteens (stretcher bond)
BrickGenBonds.register (BrickGenBond id:#stretcher label:"Halfsteens" courses:#(
	#([0, 0, 0],     #(#S)),
	#([0.5, 0, 0.5], #(#S))
))

-- 2. Staand / stapelverband (stack bond)
BrickGenBonds.register (BrickGenBond id:#stack label:"Staand (stapel)" cornerAlternate:false courses:#(
	#([0, 0, 0], #(#S))
))

-- 3. Vlaams verband: S-K alternating, headers centred on the stretcher below.
BrickGenBonds.register (BrickGenBond id:#flemish label:"Vlaams" courses:#(
	#([0, 0, 0],      #(#S, #K)),
	#([0.5, -0.5, 0], #(#K, #S))
))

-- 4. Kruisverband: stretcher / header courses, every second stretcher course
--    shifted half a brick; headers centred on the head joints below.
BrickGenBonds.register (BrickGenBond id:#englishCross label:"Kruisverband" courses:#(
	#([0, 0, 0],      #(#S)),
	#([1, -0.5, 0.5], #(#KM)),
	#([0.5, 0, 0.5],  #(#S)),
	#([1, -0.5, 0.5], #(#KM))
))

-- 5. Wild verband: stretchers with random offset per course.
BrickGenBonds.register (BrickGenBond id:#wild label:"Wild" wild:true courses:#(
	#([0, 0, 0], #(#S))
))
