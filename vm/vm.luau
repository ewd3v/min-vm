local env = getfenv()

-- This hurts
local _true = true
local _false = false
local _nil

-- lib imports
local table = table
local coroutine = coroutine
local buffer = buffer
local bit32 = bit32

-- // Environment changes in the VM are not supposed to alter the behaviour of the VM so we localise globals beforehand
local type = type
local pcall = pcall
local error = error
local tonumber = tonumber
local assert = assert
local setmetatable = setmetatable

local string_format = string.format

local table_move = table.move
local table_pack = table.pack
local table_unpack = table.unpack
local table_create = table.create
local table_insert = table.insert
-- local table_remove = table.remove
local table_concat = table.concat

local coroutine_create = coroutine.create
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local coroutine_close = coroutine.close

-- local buffer_fromstring = buffer.fromstring
local buffer_len = buffer.len
local buffer_readu8 = buffer.readu8
local buffer_readu32 = buffer.readu32
local buffer_readstring = buffer.readstring
local buffer_readf32 = buffer.readf32
local buffer_readf64 = buffer.readf64

local bit32_bor = bit32.bor
local bit32_band = bit32.band
local bit32_btest = bit32.btest
local bit32_rshift = bit32.rshift
local bit32_lshift = bit32.lshift
local bit32_extract = bit32.extract

local Vector3_new = Vector3.new

local ttisnumber = function(v)
	return type(v) == "number"
end
local ttisstring = function(v)
	return type(v) == "string"
end
local ttisboolean = function(v)
	return type(v) == "boolean"
end
local ttisfunction = function(v)
	return type(v) == "function"
end

-- // opList contains information about the instruction, each instruction is defined in this format:
-- // {OP_NAME, OP_MODE, K_MODE, HAS_AUX}
-- // OP_MODE specifies what type of registers the instruction uses if any
--		0 = NONE
--		1 = A
--		2 = AB
--		3 = ABC
--		4 = AD
--		5 = AE
-- // K_MODE specifies if the instruction has a register that holds a constant table index, which will be directly converted to the constant in the 2nd pass
--		0 = NONE
--		1 = AUX
--		2 = C
--		3 = D
--		4 = AUX import
--		5 = AUX boolean low 1 bit
--		6 = AUX number low 24 bits
-- // HAS_AUX boolean specifies whether the instruction is followed up with an AUX word, which may be used to execute the instruction.

local opList = {
	{ "NOP", 0, 0, _false },
	{ "BREAK", 0, 0, _false },
	{ "LOADNIL", 1, 0, _false },
	{ "LOADB", 3, 0, _false },
	{ "LOADN", 4, 0, _false },
	{ "LOADK", 4, 3, _false },
	{ "MOVE", 2, 0, _false },
	{ "GETGLOBAL", 1, 1, _true },
	{ "SETGLOBAL", 1, 1, _true },
	{ "GETUPVAL", 2, 0, _false },
	{ "SETUPVAL", 2, 0, _false },
	{ "CLOSEUPVALS", 1, 0, _false },
	{ "GETIMPORT", 4, 4, _true },
	{ "GETTABLE", 3, 0, _false },
	{ "SETTABLE", 3, 0, _false },
	{ "GETTABLEKS", 3, 1, _true },
	{ "SETTABLEKS", 3, 1, _true },
	{ "GETTABLEN", 3, 0, _false },
	{ "SETTABLEN", 3, 0, _false },
	{ "NEWCLOSURE", 4, 0, _false },
	{ "NAMECALL", 3, 1, _true },
	{ "CALL", 3, 0, _false },
	{ "RETURN", 2, 0, _false },
	{ "JUMP", 4, 0, _false },
	{ "JUMPBACK", 4, 0, _false },
	{ "JUMPIF", 4, 0, _false },
	{ "JUMPIFNOT", 4, 0, _false },
	{ "JUMPIFEQ", 4, 0, _true },
	{ "JUMPIFLE", 4, 0, _true },
	{ "JUMPIFLT", 4, 0, _true },
	{ "JUMPIFNOTEQ", 4, 0, _true },
	{ "JUMPIFNOTLE", 4, 0, _true },
	{ "JUMPIFNOTLT", 4, 0, _true },
	{ "ADD", 3, 0, _false },
	{ "SUB", 3, 0, _false },
	{ "MUL", 3, 0, _false },
	{ "DIV", 3, 0, _false },
	{ "MOD", 3, 0, _false },
	{ "POW", 3, 0, _false },
	{ "ADDK", 3, 2, _false },
	{ "SUBK", 3, 2, _false },
	{ "MULK", 3, 2, _false },
	{ "DIVK", 3, 2, _false },
	{ "MODK", 3, 2, _false },
	{ "POWK", 3, 2, _false },
	{ "AND", 3, 0, _false },
	{ "OR", 3, 0, _false },
	{ "ANDK", 3, 2, _false },
	{ "ORK", 3, 2, _false },
	{ "CONCAT", 3, 0, _false },
	{ "NOT", 2, 0, _false },
	{ "MINUS", 2, 0, _false },
	{ "LENGTH", 2, 0, _false },
	{ "NEWTABLE", 2, 0, _true },
	{ "DUPTABLE", 4, 3, _false },
	{ "SETLIST", 3, 0, _true },
	{ "FORNPREP", 4, 0, _false },
	{ "FORNLOOP", 4, 0, _false },
	{ "FORGLOOP", 4, 8, _true },
	{ "FORGPREP_INEXT", 4, 0, _false },
	{ "FASTCALL3", 3, 1, _true },
	{ "FORGPREP_NEXT", 4, 0, _false },
	{ "DEP_FORGLOOP_NEXT", 0, 0, _false },
	{ "GETVARARGS", 2, 0, _false },
	{ "DUPCLOSURE", 4, 3, _false },
	{ "PREPVARARGS", 1, 0, _false },
	{ "LOADKX", 1, 1, _true },
	{ "JUMPX", 5, 0, _false },
	{ "FASTCALL", 3, 0, _false },
	{ "COVERAGE", 5, 0, _false },
	{ "CAPTURE", 2, 0, _false },
	{ "SUBRK", 3, 7, _false },
	{ "DIVRK", 3, 7, _false },
	{ "FASTCALL1", 3, 0, _false },
	{ "FASTCALL2", 3, 0, _true },
	{ "FASTCALL2K", 3, 1, _true },
	{ "FORGPREP", 4, 0, _false },
	{ "JUMPXEQKNIL", 4, 5, _true },
	{ "JUMPXEQKB", 4, 5, _true },
	{ "JUMPXEQKN", 4, 6, _true },
	{ "JUMPXEQKS", 4, 6, _true },
	{ "IDIV", 3, 0, _false },
	{ "IDIVK", 3, 2, _false },
}

local LUA_MULTRET = -1
local LUA_GENERALIZED_TERMINATOR = -2

-- local function luau_newsettings()
-- 	return {
-- 		vectorCtor = function()
-- 			error("vectorCtor was not provided")
-- 		end,
-- 		vectorSize = 4,
-- 		useNativeNamecall = _false,
-- 		namecallHandler = function()
-- 			error("Native __namecall handler was not provided")
-- 		end,
-- 		extensions = {},
-- 		callHooks = {},
-- 		errorHandling = _true,
-- 		generalizedIteration = _true,
-- 		allowProxyErrors = _false,
-- 		useImportConstants = _false,
-- 		staticEnvironment = {},
-- 		decodeOp = function(op)
-- 			return op
-- 		end,
-- 	}
-- end

-- local function luau_validatesettings(luau_settings)
-- 	assert(type(luau_settings) == "table", "luau_settings should be a table")
-- 	assert(type(luau_settings.vectorCtor) == "function", "luau_settings.vectorCtor should be a function")
-- 	assert(type(luau_settings.vectorSize) == "number", "luau_settings.vectorSize should be a number")
-- 	assert(type(luau_settings.useNativeNamecall) == "boolean", "luau_settings.useNativeNamecall should be a boolean")
-- 	assert(type(luau_settings.namecallHandler) == "function", "luau_settings.namecallHandler should be a function")
-- 	assert(type(luau_settings.extensions) == "table", "luau_settings.extensions should be a table of functions")
-- 	assert(type(luau_settings.callHooks) == "table", "luau_settings.callHooks should be a table of functions")
-- 	assert(type(luau_settings.errorHandling) == "boolean", "luau_settings.errorHandling should be a boolean")
-- 	assert(
-- 		type(luau_settings.generalizedIteration) == "boolean",
-- 		"luau_settings.generalizedIteration should be a boolean"
-- 	)
-- 	assert(type(luau_settings.allowProxyErrors) == "boolean", "luau_settings.allowProxyErrors should be a boolean")
-- 	assert(type(luau_settings.staticEnvironment) == "table", "luau_settings.staticEnvironment should be a table")
-- 	assert(type(luau_settings.useImportConstants) == "boolean", "luau_settings.useImportConstants should be a boolean")
-- 	assert(type(luau_settings.decodeOp) == "function", "luau_settings.decodeOp should be a function")
-- end

-- local function getmaxline(module, protoid)
-- 	local proto = if protoid == _nil then module.mainProto else module.protoList[protoid]
-- 	local size = -1

-- 	assert(proto.i, "proto must have debug enabled")

-- 	for pc = 1, proto.sizecode do
-- 		local line = proto.j[pc]
-- 		size = if line > size then line else size
-- 	end

-- 	for _, subid in proto.h do
-- 		local maxline = getmaxline(module, subid)
-- 		size = if maxline > size then maxline else size
-- 	end

-- 	return size
-- end

-- local function getcoverage(module, protoid, depth, callback, size)
-- 	local proto = if protoid == _nil then module.mainProto else module.protoList[protoid]

-- 	assert(proto.i, "proto must have debug enabled")

-- 	local cbuffer = {}

-- 	for pc = 1, proto.sizecode do
-- 		local inst = proto.e[pc]
-- 		local line = proto.j[pc]

-- 		if inst.a ~= 69 then --[[ COVERAGE ]]
-- 			continue
-- 		end

-- 		local hits = inst.E

-- 		cbuffer[line] = if (cbuffer[line] or 0) > hits then cbuffer[line] else hits
-- 	end

-- 	callback(proto.d, proto.linedefined, depth, cbuffer, size)

-- 	for _, subid in proto.h do
-- 		getcoverage(module, subid, depth + 1, callback, size)
-- 	end
-- end

-- local function luau_getcoverage(module, protoid, callback)
-- 	assert(type(module) == "table", "module must be a table")
-- 	assert(type(protoid) == "number" or type(protoid) == "_nil", "protoid must be a number or _nil")
-- 	assert(type(callback) == "function", "callback must be a function")
-- 	getcoverage(module, protoid, 0, callback, getmaxline(module))
-- end

-- local function resolveImportConstant(static, count, k0, k1, k2)
-- 	local res = static[k0]
-- 	if count < 2 or res == _nil then
-- 		return res
-- 	end
-- 	res = res[k1]
-- 	if count < 3 or res == _nil then
-- 		return res
-- 	end
-- 	res = res[k2]
-- 	return res
-- end

--@! VM START
-- selene: allow(undefined_variable)
local stream = game:GetService("HttpService")
	:JSONDecode('{"m": null, "t": "buffer", "zbase64": "__bytecode_zbase64__"}')
local cursor = 0

local function readByte()
	local byte = buffer_readu8(stream, cursor)
	cursor = cursor + 1
	return byte
end

local function readWord()
	local word = buffer_readu32(stream, cursor)
	cursor = cursor + 4
	return word
end

local function readFloat()
	local float = buffer_readf32(stream, cursor)
	cursor = cursor + 4
	return float
end

local function readDouble()
	local double = buffer_readf64(stream, cursor)
	cursor = cursor + 8
	return double
end

local function readVarInt()
	local result = 0

	for i = 0, 4 do
		local value = readByte()
		result = bit32_bor(result, bit32_lshift(bit32_band(value, 127), i * 7))
		if not bit32_btest(value, 128) then
			break
		end
	end

	return result
end

local function readString()
	local size = readVarInt()

	if size == 0 then
		return ""
	else
		local str = buffer_readstring(stream, cursor, size)
		cursor = cursor + size

		return str
	end
end

local luauVersion = readByte()
local typesVersion = 0
if luauVersion == 0 then
	error("the provided bytecode is an error message", 0)
elseif luauVersion < 3 or luauVersion > 6 then
	error("the version of the provided bytecode is unsupported", 0)
elseif luauVersion >= 4 then
	typesVersion = readByte()
end

local stringCount = readVarInt()
local stringList = table_create(stringCount)

for i = 1, stringCount do
	stringList[i] = readString()
end

local function readInstruction(codeList)
	local value = readWord()
	local opcode = bit32_band(value, 255)

	local opinfo = opList[opcode + 1]
	local opname = opinfo[1]
	local opmode = opinfo[2]
	local kmode = opinfo[3]
	local usesAux = opinfo[4]

	local inst = {
		a = opcode,
		b = opname,
		-- opname = opmode,
		c = kmode,
		-- d = usesAux,
	}

	table_insert(codeList, inst)

	if opmode == 1 then --[[ A ]]
		inst.A = bit32_band(bit32_rshift(value, 8), 255)
	elseif opmode == 2 then --[[ AB ]]
		inst.A = bit32_band(bit32_rshift(value, 8), 255)
		inst.B = bit32_band(bit32_rshift(value, 16), 255)
	elseif opmode == 3 then --[[ ABC ]]
		inst.A = bit32_band(bit32_rshift(value, 8), 255)
		inst.B = bit32_band(bit32_rshift(value, 16), 255)
		inst.C = bit32_band(bit32_rshift(value, 24), 255)
	elseif opmode == 4 then --[[ AD ]]
		inst.A = bit32_band(bit32_rshift(value, 8), 255)
		local temp = bit32_band(bit32_rshift(value, 16), 65535)
		inst.D = if temp < 32768 then temp else temp - 16 ^ 4
	elseif opmode == 5 then --[[ AE ]]
		local temp = bit32_band(bit32_rshift(value, 8), 16 ^ 6 - 1)
		inst.E = if temp < 8388608 then temp else temp - 16 ^ 6
	end

	if usesAux then
		local aux = readWord()
		inst.d = aux

		table_insert(codeList, { --[[e = aux,]]
			b = "auxvalue",
		})
	end

	return usesAux
end

local function checkkmode(inst, k)
	local kmode = inst.c

	if kmode == 1 then --// AUX
		inst.K = k[inst.d + 1]
	elseif kmode == 2 then --// C
		inst.K = k[inst.C + 1]
	elseif kmode == 3 then --// D
		inst.K = k[inst.D + 1]
	elseif kmode == 4 then --// AUX import
		local extend = inst.d
		local count = bit32_rshift(extend, 30)
		local id0 = bit32_band(bit32_rshift(extend, 20), 1023)

		inst.K0 = k[id0 + 1]
		inst.KC = count
		if count == 2 then
			local id1 = bit32_band(bit32_rshift(extend, 10), 1023)

			inst.K1 = k[id1 + 1]
		elseif count == 3 then
			local id1 = bit32_band(bit32_rshift(extend, 10), 1023)
			local id2 = bit32_band(bit32_rshift(extend, 0), 1023)

			inst.K1 = k[id1 + 1]
			inst.K2 = k[id2 + 1]
		end
		-- if luau_settings.useImportConstants then
		-- 	inst.K = resolveImportConstant(luau_settings.staticEnvironment, count, inst.K0, inst.K1, inst.K2)
		-- end
	elseif kmode == 5 then --// AUX boolean low 1 bit
		inst.K = bit32_extract(inst.d, 0, 1) == 1
		inst.KN = bit32_extract(inst.d, 31, 1) == 1
	elseif kmode == 6 then --// AUX number low 24 bits
		inst.K = k[bit32_extract(inst.d, 0, 24) + 1]
		inst.KN = bit32_extract(inst.d, 31, 1) == 1
	elseif kmode == 7 then --// B
		inst.K = k[inst.B + 1]
	elseif kmode == 8 then --// AUX number low 16 bits
		inst.K = bit32_band(inst.d, 15)
	end
end

local function readProto(--[[bytecodeid]])
	local maxstacksize = readByte()
	local numparams = readByte()
	local nups = readByte()
	--[[local isvararg = ]]
	readByte()--[[ ~= 0]]

	if luauVersion >= 4 then
		readByte() --// flags
		local typesize = readVarInt()
		cursor = cursor + typesize
	end

	local sizecode = readVarInt()
	local codelist = table_create(sizecode)

	local skipnext = _false
	for _ = 1, sizecode do
		if skipnext then
			skipnext = _false
			continue
		end

		skipnext = readInstruction(codelist)
	end

	local debugcodelist = table_create(sizecode)
	for i = 1, sizecode do
		debugcodelist[i] = codelist[i].a
	end

	local sizek = readVarInt()
	local klist = table_create(sizek)

	for i = 1, sizek do
		local kt = readByte()
		local k

		if kt == 0 then --// Nil
			k = _nil
		elseif kt == 1 then --// Bool
			k = readByte() ~= 0
		elseif kt == 2 then --// Number
			k = readDouble()
		elseif kt == 3 then --// String
			k = stringList[readVarInt()]
		elseif kt == 4 then --// Import
			k = readWord()
		elseif kt == 5 then --// Table
			local dataLength = readVarInt()
			k = table_create(dataLength)

			for i2 = 1, dataLength do
				k[i2] = readVarInt()
			end
		elseif kt == 6 then --// Closure
			k = readVarInt()
		elseif kt == 7 then --// Vector
			-- local x, y, z, w = readFloat(), readFloat(), readFloat(), readFloat()

			k = Vector3_new(readFloat(), readFloat(), readFloat(), readFloat())
			-- if luau_settings.vectorSize == 4 then
			-- 	k = luau_settings.vectorCtor(x, y, z, w)
			-- else
			-- 	k = luau_settings.vectorCtor(x, y, z)
			-- end
		end

		klist[i] = k
	end

	-- // 2nd pass to replace constant references in the instruction
	for i = 1, sizecode do
		checkkmode(codelist[i], klist)
	end

	local sizep = readVarInt()
	local protolist = table_create(sizep)

	for i = 1, sizep do
		protolist[i] = readVarInt() + 1
	end

	--[[local linedefined = ]]
	readVarInt()

	local debugnameindex = readVarInt()
	local debugname

	if debugnameindex ~= 0 then
		debugname = stringList[debugnameindex]
	else
		debugname = "(??)"
	end

	-- // lineinfo
	local lineinfoenabled = readByte() ~= 0
	local instructionlineinfo = _nil

	if lineinfoenabled then
		local linegaplog2 = readByte()

		local intervals = bit32_rshift((sizecode - 1), linegaplog2) + 1

		local lineinfo = table_create(sizecode)
		local abslineinfo = table_create(intervals)

		local lastoffset = 0
		for j = 1, sizecode do
			lastoffset += readByte()
			lineinfo[j] = lastoffset
		end

		local lastline = 0
		for j = 1, intervals do
			lastline += readWord()
			abslineinfo[j] = lastline % (2 ^ 32)
		end

		instructionlineinfo = table_create(sizecode)

		for i = 1, sizecode do
			--// p->abslineinfo[pc >> p->linegaplog2] + p->lineinfo[pc];
			table_insert(instructionlineinfo, abslineinfo[bit32_rshift(i - 1, linegaplog2) + 1] + lineinfo[i])
		end
	end

	-- // debuginfo
	if readByte() ~= 0 then
		local sizel = readVarInt()
		for _ = 1, sizel do
			readVarInt()
			readVarInt()
			readVarInt()
			readByte()
		end
		local sizeupvalues = readVarInt()
		for _ = 1, sizeupvalues do
			readVarInt()
		end
	end

	return {
		a = maxstacksize,
		b = numparams,
		c = nups,
		-- isvararg = isvararg,
		-- linedefined = linedefined,
		d = debugname,

		-- sizecode = sizecode,
		e = codelist,
		f = debugcodelist,

		-- sizek = sizek,
		g = klist,

		-- sizep = sizep,
		h = protolist,

		i = lineinfoenabled,
		j = instructionlineinfo,

		-- bytecodeid = bytecodeid,
	}
end

-- userdataRemapping (not used in VM, left unused)
if typesVersion == 3 then
	local index = readByte()

	while index ~= 0 do
		readVarInt()

		index = readByte()
	end
end

local protoCount = readVarInt()
local protolist = table_create(protoCount)

for i = 1, protoCount do
	protolist[i] = readProto(--[[i - 1]])
end

local mainProto = protolist[readVarInt() + 1]

assert(cursor == buffer_len(stream), "deserializer cursor position mismatch")

mainProto.d = "(main)"

-- local module = {
-- 	stringList = stringList,
-- 	protoList = protoList,

-- 	mainProto = mainProto,

-- 	typesVersion = typesVersion,
-- }

-- if luau_settings == _nil then
-- 	luau_settings = luau_newsettings()
-- else
-- 	luau_validatesettings(luau_settings)
-- end

-- if type(module) ~= "table" then
-- 	module = luau_deserialize(module, luau_settings)
-- end

-- local protolist = module.protoList
-- local mainProto = module.mainProto

local function luau_wrapclosure(--[[module, ]]proto, upvals)
	local function luau_execute(debugging, stack, protos, code, varargs)
		-- local debugging, stack, protos, code, varargs

		--if luau_settings.errorHandling then
		--	debugging, stack, protos, code, varargs = ...
		-- else
		-- 	--// Copied from error handling wrapper
		-- 	local passed = table_pack(...)
		-- 	stack = table_create(proto.a)
		-- 	varargs = {
		-- 		a = 0,
		-- 		b = {},
		-- 	}

		-- 	table_move(passed, 1, proto.b, 0, stack)

		-- 	if proto.b < passed.n then
		-- 		local start = proto.b + 1
		-- 		local len = passed.n - proto.b
		-- 		varargs.a = len
		-- 		table_move(passed, start, start + len - 1, 1, varargs.b)
		-- 	end

		-- 	passed = _nil

		-- 	debugging = { a = 0, b = "NONE" }

		-- 	protos = proto.h
		-- 	code = proto.e
		-- end

		local top, pc, open_upvalues, generalized_iterators =
			-1, 1, setmetatable({}, { __mode = "vs" }), setmetatable({}, { __mode = "ks" })
		local constants = proto.g
		local debugopcodes = proto.f

		local handlingBreak = _false
		local inst, op
		while _true do
			if not handlingBreak then
				inst = code[pc]
				op = inst.a
			end

			handlingBreak = _false

			debugging.a = pc
			-- debugging.top = top
			debugging.b = inst.b

			pc += 1

			-- if stepHook then
			-- 	stepHook(stack, debugging, proto, module, upvals)
			-- end

			-- selene: allow(empty_if)
			--[=[if op == 0 then --[[ NOP ]]
				--// Do nothing
        else]=]
			if op == 1 then --[[ BREAK ]]
				-- if breakHook then
				-- 	local results = table.pack(breakHook(stack, debugging, proto, module, upvals))

				-- 	if results[1] then
				-- 		return table_unpack(results, 2, #results)
				-- 	end
				-- end

				pc -= 1
				op = debugopcodes[pc]
				handlingBreak = _true
			elseif op == 2 then --[[ LOADNIL ]]
				stack[inst.A] = _nil
			elseif op == 3 then --[[ LOADB ]]
				stack[inst.A] = inst.B == 1
				pc += inst.C
			elseif op == 4 then --[[ LOADN ]]
				stack[inst.A] = inst.D
			elseif op == 5 then --[[ LOADK ]]
				stack[inst.A] = inst.K
			elseif op == 6 then --[[ MOVE ]]
				stack[inst.A] = stack[inst.B]
			elseif op == 7 then --[[ GETGLOBAL ]]
				local kv = inst.K

				stack[inst.A] = --[[extensions[k0] or]]
					env[kv]

				pc += 1 --// adjust for aux
			elseif op == 8 then --[[ SETGLOBAL ]]
				local kv = inst.K
				env[kv] = stack[inst.A]

				pc += 1 --// adjust for aux
			elseif op == 9 then --[[ GETUPVAL ]]
				local uv = upvals[inst.B + 1]
				stack[inst.A] = uv.s[uv.i]
			elseif op == 10 then --[[ SETUPVAL ]]
				local uv = upvals[inst.B + 1]
				uv.s[uv.i] = stack[inst.A]
			elseif op == 11 then --[[ CLOSEUPVALS ]]
				for i, uv in open_upvalues do
					if uv.i >= inst.A then
						uv.v = uv.s[uv.i]
						uv.s = uv
						uv.i = "v" --// self reference
						open_upvalues[i] = _nil
					end
				end
			elseif op == 12 then --[[ GETIMPORT ]]
				-- if luau_settings.useImportConstants then
				-- 	stack[inst.A] = inst.K
				-- else
				local count = inst.KC
				local k0 = inst.K0
				local import = --[[extensions[k0] or]]
					env[k0]
				if count == 1 then
					stack[inst.A] = import
				elseif count == 2 then
					stack[inst.A] = import[inst.K1]
				elseif count == 3 then
					stack[inst.A] = import[inst.K1][inst.K2]
				end
				-- end

				pc += 1 --// adjust for aux
			elseif op == 13 then --[[ GETTABLE ]]
				stack[inst.A] = stack[inst.B][stack[inst.C]]
			elseif op == 14 then --[[ SETTABLE ]]
				stack[inst.B][stack[inst.C]] = stack[inst.A]
			elseif op == 15 then --[[ GETTABLEKS ]]
				local index = inst.K
				stack[inst.A] = stack[inst.B][index]

				pc += 1 --// adjust for aux
			elseif op == 16 then --[[ SETTABLEKS ]]
				local index = inst.K
				stack[inst.B][index] = stack[inst.A]

				pc += 1 --// adjust for aux
			elseif op == 17 then --[[ GETTABLEN ]]
				stack[inst.A] = stack[inst.B][inst.C + 1]
			elseif op == 18 then --[[ SETTABLEN ]]
				stack[inst.B][inst.C + 1] = stack[inst.A]
			elseif op == 19 then --[[ NEWCLOSURE ]]
				local newPrototype = protolist[protos[inst.D + 1]]

				local nups = newPrototype.c
				local upvalues = table_create(nups)
				stack[inst.A] = luau_wrapclosure(--[[module, ]] newPrototype, upvalues)

				for i = 1, nups do
					local pseudo = code[pc]

					pc += 1

					local uvType = pseudo.A

					if uvType == 0 then --// value
						local upvalue = {
							v = stack[pseudo.B],
							i = "v", --// self reference
						}
						upvalue.s = upvalue

						upvalues[i] = upvalue
					elseif uvType == 1 then --// reference
						local index = pseudo.B
						local prev = open_upvalues[index]

						if prev == _nil then
							prev = {
								i = index,
								s = stack,
							}
							open_upvalues[index] = prev
						end

						upvalues[i] = prev
					elseif uvType == 2 then --// upvalue
						upvalues[i] = upvals[pseudo.B + 1]
					end
				end
			elseif op == 20 then --[[ NAMECALL ]]
				local A = inst.A
				local B = inst.B

				local kv = inst.K

				local sb = stack[B]

				stack[A + 1] = sb

				pc += 1 --// adjust for aux

				--[[local useFallback = _true

				--// Special handling for native namecall behaviour
				local useNativeHandler = luau_settings.useNativeNamecall

				if useNativeHandler then
					local nativeNamecall = luau_settings.namecallHandler

					local callInst = code[pc]
					local callOp = callInst.a

					--// Copied from the CALL handler under
					local callA, callB, callC = callInst.A, callInst.B, callInst.C

					if stepHook then
						stepHook(stack, debugging, proto, module, upvals)
					end

					if interruptHook then
						interruptHook(stack, debugging, proto, module, upvals)
					end

					local params = if callB == 0 then top - callA else callB - 1
					local ret_list = table_pack(nativeNamecall(kv, table_unpack(stack, callA + 1, callA + params)))

					if ret_list[1] == _true then
						useFallback = _false

						pc += 1 --// Skip next CALL instruction

						inst = callInst
						op = callOp
						debugging.pc = pc
						debugging.name = inst.b

						table_remove(ret_list, 1)

						local ret_num = ret_list.n - 1

						if callC == 0 then
							top = callA + ret_num - 1
						else
							ret_num = callC - 1
						end

						table_move(ret_list, 1, ret_num, callA, stack)
					end
				end]]

				--if useFallback then
				stack[A] = sb[kv]
				--end
			elseif op == 21 then --[[ CALL ]]
				-- if interruptHook then
				-- 	interruptHook(stack, debugging, proto, module, upvals)
				-- end

				local A, B, C = inst.A, inst.B, inst.C

				local params = if B == 0 then top - A else B - 1
				local func = stack[A]
				local ret_list = table_pack(func(table_unpack(stack, A + 1, A + params)))

				local ret_num = ret_list.n

				if C == 0 then
					top = A + ret_num - 1
				else
					ret_num = C - 1
				end

				table_move(ret_list, 1, ret_num, A, stack)
			elseif op == 22 then --[[ RETURN ]]
				-- if interruptHook then
				-- 	interruptHook(stack, debugging, proto, module, upvals)
				-- end

				local A = inst.A
				local B = inst.B
				local b = B - 1
				local nresults

				if b == LUA_MULTRET then
					nresults = top - A + 1
				else
					nresults = B - 1
				end

				return table_unpack(stack, A, A + nresults - 1)
			elseif op == 23 or op == 24 then --[[ JUMP ]]
				pc += inst.D
			--[=[elseif op == 24 then --[[ JUMPBACK ]]
				-- if interruptHook then
				-- 	interruptHook(stack, debugging, proto, module, upvals)
				-- end

				pc += inst.D]=]
			elseif op == 25 then --[[ JUMPIF ]]
				if stack[inst.A] then
					pc += inst.D
				end
			elseif op == 26 then --[[ JUMPIFNOT ]]
				if not stack[inst.A] then
					pc += inst.D
				end
			elseif op == 27 then --[[ JUMPIFEQ ]]
				if stack[inst.A] == stack[inst.d] then
					pc += inst.D
				else
					pc += 1
				end
			elseif op == 28 then --[[ JUMPIFLE ]]
				if stack[inst.A] <= stack[inst.d] then
					pc += inst.D
				else
					pc += 1
				end
			elseif op == 29 then --[[ JUMPIFLT ]]
				if stack[inst.A] < stack[inst.d] then
					pc += inst.D
				else
					pc += 1
				end
			elseif op == 30 then --[[ JUMPIFNOTEQ ]]
				if stack[inst.A] == stack[inst.d] then
					pc += 1
				else
					pc += inst.D
				end
			elseif op == 31 then --[[ JUMPIFNOTLE ]]
				if stack[inst.A] <= stack[inst.d] then
					pc += 1
				else
					pc += inst.D
				end
			elseif op == 32 then --[[ JUMPIFNOTLT ]]
				if stack[inst.A] < stack[inst.d] then
					pc += 1
				else
					pc += inst.D
				end
			elseif op == 33 then --[[ ADD ]]
				stack[inst.A] = stack[inst.B] + stack[inst.C]
			elseif op == 34 then --[[ SUB ]]
				stack[inst.A] = stack[inst.B] - stack[inst.C]
			elseif op == 35 then --[[ MUL ]]
				stack[inst.A] = stack[inst.B] * stack[inst.C]
			elseif op == 36 then --[[ DIV ]]
				stack[inst.A] = stack[inst.B] / stack[inst.C]
			elseif op == 37 then --[[ MOD ]]
				stack[inst.A] = stack[inst.B] % stack[inst.C]
			elseif op == 38 then --[[ POW ]]
				stack[inst.A] = stack[inst.B] ^ stack[inst.C]
			elseif op == 39 then --[[ ADDK ]]
				stack[inst.A] = stack[inst.B] + inst.K
			elseif op == 40 then --[[ SUBK ]]
				stack[inst.A] = stack[inst.B] - inst.K
			elseif op == 41 then --[[ MULK ]]
				stack[inst.A] = stack[inst.B] * inst.K
			elseif op == 42 then --[[ DIVK ]]
				stack[inst.A] = stack[inst.B] / inst.K
			elseif op == 43 then --[[ MODK ]]
				stack[inst.A] = stack[inst.B] % inst.K
			elseif op == 44 then --[[ POWK ]]
				stack[inst.A] = stack[inst.B] ^ inst.K
			elseif op == 45 then --[[ AND ]]
				local value = stack[inst.B]
				stack[inst.A] = if value then stack[inst.C] or _false else value
			elseif op == 46 then --[[ OR ]]
				local value = stack[inst.B]
				stack[inst.A] = if value then value else stack[inst.C] or _false
			elseif op == 47 then --[[ ANDK ]]
				local value = stack[inst.B]
				stack[inst.A] = if value then inst.K or _false else value
			elseif op == 48 then --[[ ORK ]]
				local value = stack[inst.B]
				stack[inst.A] = if value then value else inst.K or _false
			elseif op == 49 then --[[ CONCAT ]]
				local B, C = inst.B, inst.C
				local success, s = pcall(table_concat, stack, "", B, C)

				if not success then
					local str = stack[B]

					for i = B + 1, C do
						str ..= stack[i]
					end
				end

				stack[inst.A] = s
			elseif op == 50 then --[[ NOT ]]
				stack[inst.A] = not stack[inst.B]
			elseif op == 51 then --[[ MINUS ]]
				stack[inst.A] = -stack[inst.B]
			elseif op == 52 then --[[ LENGTH ]]
				stack[inst.A] = #stack[inst.B]
			elseif op == 53 then --[[ NEWTABLE ]]
				stack[inst.A] = table_create(inst.d)

				pc += 1 --// adjust for aux
			elseif op == 54 then --[[ DUPTABLE ]]
				local template = inst.K
				local serialized = {}
				for _, id in template do
					serialized[constants[id + 1]] = _nil
				end
				stack[inst.A] = serialized
			elseif op == 55 then --[[ SETLIST ]]
				local A = inst.A
				local B = inst.B
				local c = inst.C - 1

				if c == LUA_MULTRET then
					c = top - B + 1
				end

				table_move(stack, B, B + c - 1, inst.d, stack[A])

				pc += 1 --// adjust for aux
			elseif op == 56 then --[[ FORNPREP ]]
				local A = inst.A

				local limit = stack[A]
				if not ttisnumber(limit) then
					local number = tonumber(limit)

					if number == _nil then
						error("invalid 'for' limit (number expected)")
					end

					stack[A] = number
					limit = number
				end

				local step = stack[A + 1]
				if not ttisnumber(step) then
					local number = tonumber(step)

					if number == _nil then
						error("invalid 'for' step (number expected)")
					end

					stack[A + 1] = number
					step = number
				end

				local index = stack[A + 2]
				if not ttisnumber(index) then
					local number = tonumber(index)

					if number == _nil then
						error("invalid 'for' index (number expected)")
					end

					stack[A + 2] = number
					index = number
				end

				if step > 0 then
					if not (index <= limit) then
						pc += inst.D
					end
				else
					if not (limit <= index) then
						pc += inst.D
					end
				end
			elseif op == 57 then --[[ FORNLOOP ]]
				-- if interruptHook then
				-- 	interruptHook(stack, debugging, proto, module, upvals)
				-- end

				local A = inst.A
				local limit = stack[A]
				local step = stack[A + 1]
				local index = stack[A + 2] + step

				stack[A + 2] = index

				if step > 0 then
					if index <= limit then
						pc += inst.D
					end
				else
					if limit <= index then
						pc += inst.D
					end
				end
			elseif op == 58 then --[[ FORGLOOP ]]
				-- if interruptHook then
				-- 	interruptHook(stack, debugging, proto, module, upvals)
				-- end

				local A = inst.A
				local res = inst.K

				top = A + 6

				local it = stack[A]

				if --[[(luau_settings.generalizedIteration == _false) or]]
					ttisfunction(it)
				then
					local vals = { it(stack[A + 1], stack[A + 2]) }
					table_move(vals, 1, res, A + 3, stack)

					if stack[A + 3] ~= _nil then
						stack[A + 2] = stack[A + 3]
						pc += inst.D
					else
						pc += 1
					end
				else
					local ok, vals = coroutine_resume(generalized_iterators[inst], it, stack[A + 1], stack[A + 2])
					if not ok then
						error(vals)
					end
					if vals == LUA_GENERALIZED_TERMINATOR then
						generalized_iterators[inst] = _nil
						pc += 1
					else
						table_move(vals, 1, res, A + 3, stack)

						stack[A + 2] = stack[A + 3]
						pc += inst.D
					end
				end
			elseif op == 59 or op == 61 then --[[ FORGPREP_INEXT ]]
				if not ttisfunction(stack[inst.A]) then
					error(string_format("attempt to iterate over a %s value", type(stack[inst.A]))) -- FORGPREP_INEXT encountered non-function value
				end

				pc += inst.D
			elseif op == 60 or op == 74 or op == 75 then --[[ FASTCALL3 ]]
				--[[ Skipped ]]
				pc += 1 --// adjust for aux
				--[=[elseif op == 61 then --[[ FORGPREP_NEXT ]]
					if not ttisfunction(stack[inst.A]) then
						error(string_format("attempt to iterate over a %s value", type(stack[inst.A]))) -- FORGPREP_NEXT encountered non-function value
					end

					pc += inst.D]=]
			elseif op == 63 then --[[ GETVARARGS ]]
				local A = inst.A
				local b = inst.B - 1

				if b == LUA_MULTRET then
					b = varargs.a
					top = A + b - 1
				end

				table_move(varargs.b, 1, b, A, stack)
			elseif op == 64 then --[[ DUPCLOSURE ]]
				local newPrototype = protolist[inst.K + 1] --// correct behavior would be to reuse the prototype if possible but it would not be useful here

				local nups = newPrototype.c
				local upvalues = table_create(nups)
				stack[inst.A] = luau_wrapclosure(--[[module, ]] newPrototype, upvalues)

				for i = 1, nups do
					local pseudo = code[pc]
					pc += 1

					local uvType = pseudo.A
					if uvType == 0 then --// value
						local upvalue = {
							v = stack[pseudo.B],
							i = "v", --// self reference
						}
						upvalue.s = upvalue

						upvalues[i] = upvalue

						--// references dont get handled by DUPCLOSURE
					elseif uvType == 2 then --// upvalue
						upvalues[i] = upvals[pseudo.B + 1]
					end
				end
			elseif op == 65 then --[[ PREPVARARGS ]]
				--[[ Handled by wrapper ]]
			elseif op == 66 then --[[ LOADKX ]]
				local kv = inst.K
				stack[inst.A] = kv

				pc += 1 --// adjust for aux
			elseif op == 67 then --[[ JUMPX ]]
				-- if interruptHook then
				-- 	interruptHook(stack, debugging, proto, module, upvals)
				-- end

				pc += inst.E
				--[=[elseif op == 68 then --[[ FASTCALL ]]
					--[[ Skipped ]]]=]
			elseif op == 69 then --[[ COVERAGE ]]
				inst.E += 1
			elseif op == 70 then --[[ CAPTURE ]]
				--[[ Handled by CLOSURE ]]
				error("encountered unhandled CAPTURE")
			elseif op == 71 then --[[ SUBRK ]]
				stack[inst.A] = inst.K - stack[inst.C]
			elseif op == 72 then --[[ DIVRK ]]
				stack[inst.A] = inst.K / stack[inst.C]
				--[=[elseif op == 73 then --[[ FASTCALL1 ]]
					--[[ Skipped ]]]=]
				--[=[elseif op == 74 then --[[ FASTCALL2 ]]
					--[[ Skipped ]]
					pc += 1 --// adjust for aux]=]
				--[=[elseif op == 75 then --[[ FASTCALL2K ]]
					--[[ Skipped ]]
					pc += 1 --// adjust for aux]=]
			elseif op == 76 then --[[ FORGPREP ]]
				local iterator = stack[inst.A]

				if --[[luau_settings.generalizedIteration and]]
					not ttisfunction(iterator)
				then
					local loopInstruction = code[pc + inst.D]
					if generalized_iterators[loopInstruction] == _nil then
						local function gen_iterator(...)
							for
								r1,
								r2,
								r3,
								r4,
								r5,
								r6,
								r7,
								r8,
								r9,
								r10,
								r11,
								r12,
								r13,
								r14,
								r15,
								r16,
								r17,
								r18,
								r19,
								r20,
								r21,
								r22,
								r23,
								r24,
								r25,
								r26,
								r27,
								r28,
								r29,
								r30,
								r31,
								r32,
								r33,
								r34,
								r35,
								r36,
								r37,
								r38,
								r39,
								r40,
								r41,
								r42,
								r43,
								r44,
								r45,
								r46,
								r47,
								r48,
								r49,
								r50,
								r51,
								r52,
								r53,
								r54,
								r55,
								r56,
								r57,
								r58,
								r59,
								r60,
								r61,
								r62,
								r63,
								r64,
								r65,
								r66,
								r67,
								r68,
								r69,
								r70,
								r71,
								r72,
								r73,
								r74,
								r75,
								r76,
								r77,
								r78,
								r79,
								r80,
								r81,
								r82,
								r83,
								r84,
								r85,
								r86,
								r87,
								r88,
								r89,
								r90,
								r91,
								r92,
								r93,
								r94,
								r95,
								r96,
								r97,
								r98,
								r99,
								r100,
								r101,
								r102,
								r103,
								r104,
								r105,
								r106,
								r107,
								r108,
								r109,
								r110,
								r111,
								r112,
								r113,
								r114,
								r115,
								r116,
								r117,
								r118,
								r119,
								r120,
								r121,
								r122,
								r123,
								r124,
								r125,
								r126,
								r127,
								r128,
								r129,
								r130,
								r131,
								r132,
								r133,
								r134,
								r135,
								r136,
								r137,
								r138,
								r139,
								r140,
								r141,
								r142,
								r143,
								r144,
								r145,
								r146,
								r147,
								r148,
								r149,
								r150,
								r151,
								r152,
								r153,
								r154,
								r155,
								r156,
								r157,
								r158,
								r159,
								r160,
								r161,
								r162,
								r163,
								r164,
								r165,
								r166,
								r167,
								r168,
								r169,
								r170,
								r171,
								r172,
								r173,
								r174,
								r175,
								r176,
								r177,
								r178,
								r179,
								r180,
								r181,
								r182,
								r183,
								r184,
								r185,
								r186,
								r187,
								r188,
								r189,
								r190,
								r191,
								r192,
								r193,
								r194,
								r195,
								r196,
								r197,
								r198,
								r199,
								r200
							in ... do
								coroutine_yield({
									r1,
									r2,
									r3,
									r4,
									r5,
									r6,
									r7,
									r8,
									r9,
									r10,
									r11,
									r12,
									r13,
									r14,
									r15,
									r16,
									r17,
									r18,
									r19,
									r20,
									r21,
									r22,
									r23,
									r24,
									r25,
									r26,
									r27,
									r28,
									r29,
									r30,
									r31,
									r32,
									r33,
									r34,
									r35,
									r36,
									r37,
									r38,
									r39,
									r40,
									r41,
									r42,
									r43,
									r44,
									r45,
									r46,
									r47,
									r48,
									r49,
									r50,
									r51,
									r52,
									r53,
									r54,
									r55,
									r56,
									r57,
									r58,
									r59,
									r60,
									r61,
									r62,
									r63,
									r64,
									r65,
									r66,
									r67,
									r68,
									r69,
									r70,
									r71,
									r72,
									r73,
									r74,
									r75,
									r76,
									r77,
									r78,
									r79,
									r80,
									r81,
									r82,
									r83,
									r84,
									r85,
									r86,
									r87,
									r88,
									r89,
									r90,
									r91,
									r92,
									r93,
									r94,
									r95,
									r96,
									r97,
									r98,
									r99,
									r100,
									r101,
									r102,
									r103,
									r104,
									r105,
									r106,
									r107,
									r108,
									r109,
									r110,
									r111,
									r112,
									r113,
									r114,
									r115,
									r116,
									r117,
									r118,
									r119,
									r120,
									r121,
									r122,
									r123,
									r124,
									r125,
									r126,
									r127,
									r128,
									r129,
									r130,
									r131,
									r132,
									r133,
									r134,
									r135,
									r136,
									r137,
									r138,
									r139,
									r140,
									r141,
									r142,
									r143,
									r144,
									r145,
									r146,
									r147,
									r148,
									r149,
									r150,
									r151,
									r152,
									r153,
									r154,
									r155,
									r156,
									r157,
									r158,
									r159,
									r160,
									r161,
									r162,
									r163,
									r164,
									r165,
									r166,
									r167,
									r168,
									r169,
									r170,
									r171,
									r172,
									r173,
									r174,
									r175,
									r176,
									r177,
									r178,
									r179,
									r180,
									r181,
									r182,
									r183,
									r184,
									r185,
									r186,
									r187,
									r188,
									r189,
									r190,
									r191,
									r192,
									r193,
									r194,
									r195,
									r196,
									r197,
									r198,
									r199,
									r200,
								})
							end

							coroutine_yield(LUA_GENERALIZED_TERMINATOR)
						end

						generalized_iterators[loopInstruction] = coroutine_create(gen_iterator)
					end
				end

				pc += inst.D
			elseif op == 77 then --[[ JUMPXEQKNIL ]]
				local kn = inst.KN

				if (stack[inst.A] == _nil) ~= kn then
					pc += inst.D
				else
					pc += 1
				end
			elseif op == 78 then --[[ JUMPXEQKB ]]
				local kv = inst.K
				local kn = inst.KN
				local ra = stack[inst.A]

				if (ttisboolean(ra) and (ra == kv)) ~= kn then
					pc += inst.D
				else
					pc += 1
				end
			elseif op == 79 or op == 80 then --[[ JUMPXEQKN ]]
				local kv = inst.K
				local kn = inst.KN
				local ra = stack[inst.A]

				if (ra == kv) ~= kn then
					pc += inst.D
				else
					pc += 1
				end
				--[=[elseif op == 80 then --[[ JUMPXEQKS ]]
					local kv = inst.K
					local kn = inst.KN
					local ra = stack[inst.A]

					if (ra == kv) ~= kn then
						pc += inst.D
					else
						pc += 1
					end]=]
			elseif op == 81 then --[[ IDIV ]]
				stack[inst.A] = stack[inst.B] // stack[inst.C]
			elseif op == 82 then --[[ IDIVK ]]
				stack[inst.A] = stack[inst.B] // inst.K
				--[=[else
					error("Unsupported Opcode: " .. inst.b .. " op: " .. op)]=]
			end
		end

		for i, uv in open_upvalues do
			uv.v = uv.s[uv.i]
			uv.s = uv
			uv.i = "v" --// self reference
			open_upvalues[i] = _nil
		end

		for i, iter in generalized_iterators do
			coroutine_close(iter)
			generalized_iterators[i] = _nil
		end
	end

	local function wrapped(...)
		local passed = table_pack(...)
		local stack = table_create(proto.a)
		local varargs = {
			a = 0,
			b = {},
		}

		table_move(passed, 1, proto.b, 0, stack)

		if proto.b < passed.n then
			local start = proto.b + 1
			local len = passed.n - proto.b
			varargs.a = len
			table_move(passed, start, start + len - 1, 1, varargs.b)
		end

		passed = _nil -- we'll keep this, even though it is removable

		local debugging = { a = 0, b = "NONE" }
		local result = table_pack(pcall(luau_execute, debugging, stack, proto.h, proto.e, varargs))
		--if luau_settings.errorHandling then
		--	result = table_pack(pcall(luau_execute, debugging, stack, proto.h, proto.e, varargs))
		-- else
		-- 	result = table_pack(_true, luau_execute(debugging, stack, proto.h, proto.e, varargs))
		-- end

		if result[1] then
			return table_unpack(result, 2, result.n)
		else
			local message = result[2]

			-- if panicHook then
			-- 	panicHook(message, stack, debugging, proto, module, upvals)
			-- end

			if not ttisstring(message) then
				-- if luau_settings.allowProxyErrors then
				-- 	error(message)
				-- else
				message = type(message)
				-- end
			end

			if proto.i then
				return error(
					string_format(
						"Fiu VM Error { Name: %s Line: %s PC: %s Opcode: %s }: %s",
						proto.d,
						proto.j[debugging.a],
						debugging.a,
						debugging.b,
						message
					),
					0
				)
			else
				return error(
					string_format(
						"Fiu VM Error { Name: %s PC: %s Opcode: %s }: %s",
						proto.d,
						debugging.a,
						debugging.b,
						message
					),
					0
				)
			end
		end
	end

	-- if luau_settings.errorHandling then
	return wrapped
	-- else
	-- 	return luau_execute
	-- end
end

return luau_wrapclosure(mainProto)(...)
