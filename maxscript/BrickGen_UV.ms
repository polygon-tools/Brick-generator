-- BrickGen_UV.ms
-- UV channels (PLAN.md §9).
--   channel 1: per brick 0..1 over the *unclipped* brick (front face), so a
--              sawn brick shows only part of the texture. Phase 2 maps this
--              0..1 square onto an atlas cell.
--   channel 2: wall-planar, real size, 1 UV unit = 1 m.

struct BrickGenUVStruct
(
	-- x, z in mm (wall-local); nomX0/nomZ0/nomL/nomH describe the unclipped brick
	fn brickUV x z nomX0 nomZ0 nomL nomH =
	(
		[(x - nomX0) / nomL, (z - nomZ0) / nomH, 0.0]
	),

	fn planarUV x z = ( [x * 0.001, z * 0.001, 0.0] )
)

global BrickGenUV = BrickGenUVStruct()
