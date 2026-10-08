-- BrickGen_ProbeModifier.ms
-- Feasibility probe (not part of the plugin): can a MAXScript modifier on a
-- spline read that spline and output new geometry?
-- If yes, BrickGen can become a modifier: spline -> BrickGen (instead of Extrude).
--
-- Test in an EMPTY scene (save other work first):
--   1. Scripting > Run Script... > this file
--   2. Draw a Line in the Top view (a few clicks, right-click to finish)
--   3. Modify panel > Modifier List > "BrickGen Probe"
--   4. Expected: vertical planes 250 units high along every segment.
--      Move a vertex of the line: the planes should follow.
--   5. Send the Listener output (lines starting with "BrickGen probe").

plugin simpleMeshMod BrickGenProbeMod
	name:"BrickGen Probe"
	classID:#(0x3d5a1f27, 0x6b2c8e41)
	category:"BrickGen"
(
	parameters main rollout:params
	(
		height type:#worldUnits ui:spnH default:250.0
	)
	rollout params "BrickGen Probe"
	(
		spinner spnH "Hoogte:" type:#worldUnits range:[0, 1e6, 250]
	)

	on modifyMesh do
	(
		local node = refs.dependentNodes this firstOnly:true
		local verts = #()
		local faces = #()
		local base = if node != undefined then node.baseObject else undefined
		if base != undefined and (isKindOf base SplineShape or isKindOf base line) then
		(
			local ns = numSplines node
			for s = 1 to ns do
			(
				local n = numKnots node s
				local segs = if (isClosed node s) then n else n - 1
				for k = 1 to segs do
				(
					local a = in coordsys local getKnotPoint node s k
					local b = in coordsys local getKnotPoint node s (if k == n then 1 else k + 1)
					local i = verts.count
					append verts a
					append verts b
					append verts (b + [0, 0, height])
					append verts (a + [0, 0, height])
					append faces [i + 1, i + 2, i + 3]
					append faces [i + 1, i + 3, i + 4]
				)
			)
			format "BrickGen probe: % spline(s), % segment(en)\n" ns (faces.count / 2)
		)
		else
			format "BrickGen probe: geen editable spline onder de modifier (%)\n" \
				(if base == undefined then "geen node" else classOf base)
		setMesh mesh verts:verts faces:faces
	)
)

format "BrickGen probe geladen. Teken een Line en zet de modifier 'BrickGen Probe' erop.\n"
