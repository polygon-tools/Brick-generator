-- BrickGen_RNG.ms
-- Deterministic, hash-based random numbers (PLAN.md §5).
--
-- Every random value is derived from (seed, brickIndex, channel), so adding a
-- new random parameter (= a new channel) never shifts existing randomness.
-- Arithmetic is done in Integer64 modulo the Mersenne prime 2^31-1; every
-- product stays below 2^63, so there is no overflow anywhere.
-- Never use the global `random` for geometry.

struct BrickGenRNGStruct
(
	P = 2147483647L,

	fn modP x = ( x - (x / P) * P ),

	-- Non-linear mixing of an Integer64 value into [0, P).
	fn mix x =
	(
		x = modP (abs (x as integer64))
		x = modP (x * x + 1013904223L)
		x = modP (x * 48271L)
		x = modP (x * x + 362437L)
		x
	),

	-- Per-brick key: compute once per brick, then draw channels from it.
	fn brickKey seed idx =
	(
		mix ((mix ((seed as integer64) + 9973L)) + (idx as integer64) * 7919L + 1L)
	),

	-- Uniform float in [0, 1) for a channel of a brick key.
	fn u01 key ch =
	(
		local x = key + (ch as integer64) * 104729L + 7L
		x = modP (x * x + 1013904223L)
		x = modP (x * 48271L)
		x = modP (x * x + 362437L)
		local r = (x as float) / 2147483647.0
		if r >= 1.0 then 0.9999999 else r
	),

	-- Uniform float in [-1, 1).
	fn sym key ch = ( 2.0 * (u01 key ch) - 1.0 ),

	-- Uniform integer in [lo, hi].
	fn randInt key ch lo hi =
	(
		local v = lo + ((floor ((u01 key ch) * (hi - lo + 1))) as integer)
		if v > hi then hi else v
	),

	-- Convenience: one-off value without keeping the key.
	fn rand01 seed idx ch = ( u01 (brickKey seed idx) ch )
)

global BrickGenRNG = BrickGenRNGStruct()
