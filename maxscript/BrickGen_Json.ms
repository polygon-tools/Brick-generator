-- BrickGen_Json.ms
-- Minimal JSON reader (no external dependencies).
-- Objects -> Dictionary #string, arrays -> Array, null -> undefined
-- (null members are simply not stored; use BrickGenJson_get with a default).
-- Requires 3ds Max 2017.1+ (Dictionary).

struct BrickGenJsonState ( src = "", pos = 1, len = 0 )

-- forward declaration for recursion
global BrickGenJson_parseValue

fn BrickGenJson_fail st msg =
(
	throw ("BrickGen JSON: " + msg + " (at char " + (st.pos as string) + ")")
)

fn BrickGenJson_skipWs st =
(
	while st.pos <= st.len and (findString " \t\r\n" st.src[st.pos]) != undefined do st.pos += 1
)

fn BrickGenJson_parseString st =
(
	st.pos += 1 -- opening quote
	local ss = stringStream ""
	local done = false
	while not done do
	(
		if st.pos > st.len do BrickGenJson_fail st "unterminated string"
		local ch = st.src[st.pos]
		if ch == "\"" then
		(
			done = true
			st.pos += 1
		)
		else if ch == "\\" then
		(
			local e = st.src[st.pos + 1]
			case e of
			(
				"n": format "\n" to:ss
				"t": format "\t" to:ss
				"r": format "\r" to:ss
				"b": ok
				"f": ok
				"u":
				(
					local code = bit.hexAsInt (substring st.src (st.pos + 2) 4)
					format "%" (bit.intAsChar code) to:ss
					st.pos += 4
				)
				default: format "%" e to:ss -- \" \\ \/
			)
			st.pos += 2
		)
		else
		(
			format "%" ch to:ss
			st.pos += 1
		)
	)
	ss as string
)

fn BrickGenJson_parseNumber st =
(
	local start = st.pos
	local isFloat = false
	while st.pos <= st.len and (findString "+-0123456789.eE" st.src[st.pos]) != undefined do
	(
		if (findString ".eE" st.src[st.pos]) != undefined do isFloat = true
		st.pos += 1
	)
	local txt = substring st.src start (st.pos - start)
	local v = if isFloat then (txt as float) else (txt as integer)
	if v == undefined do BrickGenJson_fail st ("bad number '" + txt + "'")
	v
)

fn BrickGenJson_parseArray st =
(
	st.pos += 1 -- [
	local arr = #()
	BrickGenJson_skipWs st
	if st.src[st.pos] == "]" then st.pos += 1
	else
	(
		local done = false
		while not done do
		(
			append arr (BrickGenJson_parseValue st)
			BrickGenJson_skipWs st
			local ch = st.src[st.pos]
			st.pos += 1
			if ch == "]" then done = true
			else if ch != "," do BrickGenJson_fail st "expected , or ]"
		)
	)
	arr
)

fn BrickGenJson_parseObject st =
(
	st.pos += 1 -- {
	local d = Dictionary #string
	BrickGenJson_skipWs st
	if st.src[st.pos] == "}" then st.pos += 1
	else
	(
		local done = false
		while not done do
		(
			BrickGenJson_skipWs st
			if st.src[st.pos] != "\"" do BrickGenJson_fail st "expected key"
			local k = BrickGenJson_parseString st
			BrickGenJson_skipWs st
			if st.src[st.pos] != ":" do BrickGenJson_fail st "expected :"
			st.pos += 1
			local v = BrickGenJson_parseValue st
			if v != undefined do d[k] = v
			BrickGenJson_skipWs st
			local ch = st.src[st.pos]
			st.pos += 1
			if ch == "}" then done = true
			else if ch != "," do BrickGenJson_fail st "expected , or }"
		)
	)
	d
)

fn BrickGenJson_parseValue st =
(
	BrickGenJson_skipWs st
	if st.pos > st.len do BrickGenJson_fail st "unexpected end"
	local ch = st.src[st.pos]
	case of
	(
		(ch == "{"): BrickGenJson_parseObject st
		(ch == "["): BrickGenJson_parseArray st
		(ch == "\""): BrickGenJson_parseString st
		((substring st.src st.pos 4) == "true"): ( st.pos += 4; true )
		((substring st.src st.pos 5) == "false"): ( st.pos += 5; false )
		((substring st.src st.pos 4) == "null"): ( st.pos += 4; undefined )
		default: BrickGenJson_parseNumber st
	)
)

fn BrickGenJson_parseText txt =
(
	local st = BrickGenJsonState src:txt pos:1 len:txt.count
	BrickGenJson_parseValue st
)

-- Returns undefined when the file is missing; throws on invalid JSON.
fn BrickGenJson_parseFile path =
(
	if not (doesFileExist path) do return undefined
	local txt = (dotNetClass "System.IO.File").ReadAllText path
	BrickGenJson_parseText txt
)

-- Safe member access with default.
fn BrickGenJson_get obj key default =
(
	if (classOf obj) == Dictionary and (hasDictValue obj key) then obj[key] else default
)
