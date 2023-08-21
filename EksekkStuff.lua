dofile"C:\\Users\\Eksekk\\Documents\\GitHub\\MMStuff\\A_EksekkFunctions.lua"
dofile"C:\\Users\\Eksekk\\Documents\\GitHub\\MMStuff\\GenerateStructInfo.lua"
PGenEditData = PGenEditData or {}

local M = {dll = _G.oldDll}
mem.dll.kernel32.SetDllDirectoryA("C:\\Users\\Eksekk\\source\\repos\\PGenEdit\\Debug\\")
function events.GameInitialized1()
	-- speed up loading and unloading my dll by not unloading dependencies which don't change
	-- (they won't unload because this increments reference count)
	--mem.LoadDll "wxmsw321ud_core_vc_custom.dll"
	--mem.LoadDll "wxbase321ud_vc_custom.dll"
end
local runEventLoopOnce
local getLuaState
function M.unloadDll()
	if M.dll then
		local ptr = M.dll["?ptr"]
		M.dll.unloadCleanup()
		mem.UnloadDll(M.dll)
		M.dll = nil
		_G.oldDll = nil
		d = nil
		-- loads twice for some reason
		if mem.dll.kernel32.GetModuleHandleA("PGenEdit.dll") ~= 0 then
			mem.dll.kernel32.FreeLibrary(ptr)
		end
		events.Tick.Remove(runEventLoopOnce)
		runEventLoopOnce = nil
	end
end
-- M.dll.setClassData(json.encode(M.C()))

local FORMAT_MESSAGE_FROM_SYSTEM = 0x00001000
function M.loadDll()
	if offsets.MMVersion ~= 7 then return end
	if not M.dll then
		M.dll = mem.LoadDll("PGenEdit.dll")
		if not M.dll then
			local err = mem.dll.kernel32.GetLastError()
			local buffer = mem.allocMM(500)
            mem.dll.kernel32.FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, 0, err, 0, buffer, 500, 0);
			local str = mem.string(buffer)
			mem.freeMM(buffer)
			error(string.format("Couldn't load party generator dll! Error %d (message: %q)", err, str))
			return
		end
		d = M.dll
		_G.oldDll = M.dll
		M.dll.setLuaState(getLuaState())
		M.dll.setClassData(json.encode(M.C())) -- SET DATA BEFORE INIT
		M.dll.setSkillData(json.encode(M.Sk()))
		M.dll.setMiscData(json.encode(M.getMiscData()))
		M.dll.init()
		runEventLoopOnce = function() M.dll.runEventLoopOnce() end
		events.Tick = runEventLoopOnce
		--function events.AfterLoadMap() M.dll.runTests() end
		rawset(M.dll, "runLua", M.dll.runLuaScriptFromDLL)
	end
end

function getLuaState()
	for k, v in pairs(debug.getregistry()) do
		if type(k) == "userdata" and getU(v, "HookData") then
			return
			mem.u4[
				tonumber(
					tostring(k):match("x([%dA-Fa-f]+)")
					, 16
				)
			]
		end
	end
end

if PGenEditData.ptrs then
	events.LoadMap.Remove(PGenEditData.ptrs)
	PGenEditData.ptrs = nil
end
function M.ptrs()
	if M.dll then
		local ptrs = mem.allocMM(4 * Party.Count)
		for i = 0, Party.Count - 1 do
			mem.u4[i * 4 + ptrs] = Party[i]["?ptr"]
		end
		M.dll.setPlayerPointers(ptrs)
		mem.freeMM(ptrs)
	end
end
--PGenEditData.ptrs = M.ptrs

--events.LoadMap = PGenEditData.ptrs

function M.reloadDll()
	M.unloadDll()
	M.loadDll()
end

function M.C()
	local ok
	ok, M.classData = pcall2(require, "PGenEditData\\classData");
	package.loaded["PGenEditData\\classData"] = nil -- allow always reloading module
	return M.classData
end

function M.Sk()
	local ok
	ok, M.skillData = pcall2(require, "PGenEditData\\skillData");
	package.loaded["PGenEditData\\skillData"] = nil
	return M.skillData
end

function M.getMiscData()
	local ok
	ok, M.miscData = pcall2(require, "PGenEditData\\miscData");
	package.loaded["PGenEditData\\miscData"] = nil
	return M.miscData
end

M.playerTypes = {caster = "caster", melee = "melee", ranged = "ranged", defensive = "defensive", utility = "utility"}

PGenEditData = PGenEditData or {}
function M.installKeyboardHandlers()
	M.removeKeyboardHandlers()
	PGenEditData.handlers = {}
	local function loadUnload(t)
		if t.Key == const.Keys.F3 and Game.CtrlPressed then
			t.Handled = true
			M.dll.displayEditorMainWindow(true)
		elseif t.Key == const.Keys.F4 and Game.CtrlPressed then
			t.Handled = true
			if M.dll then
				M.unloadDll()
			else
				M.loadDll()
			end
		elseif t.Key == const.Keys.F5 and Game.CtrlPressed then
			t.Handled = true
			if M.dll.setClassData(json.encode(M.C())) then
				--MessageBox("Success!")
			end
		elseif t.Key == const.Keys.F6 and Game.CtrlPressed then
			t.Handled = true
			if M.dll.setSkillData(json.encode(M.Sk())) then
				--MessageBox("Success!")
			end
		end
	end
	table.insert(PGenEditData.handlers, loadUnload)
	events.AddFirst("KeyDown", loadUnload)
end

function M.removeKeyboardHandlers()
	if PGenEditData.handlers then
		for i, v in ipairs(PGenEditData.handlers) do
			events.Remove(v)
		end
	end
end
M.installKeyboardHandlers()

M.deepcopyMM = deepcopyMM

local function GetPlayer(ptr)
	local i = (ptr - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]
	return i, Party.PlayersArray[i]
end

mmvAssert = function(ver)
	assert(Game.Version == ver, string.format("Wrong MM version, this script is for MM%d", ver))
end

function M.reloadApi()
	dofile "E:\\Documents\\GitHub\\MMStuff\\pgenedit\\PGenEditApi.lua"
end
M.reloadApi()

--[[
	MAW resurrection tests:
	> Party[3].Eradicated = -500000
	> Party[3].Eradicated = -50000000
	> Party[3].Eradicated = -50000000; Party[3].Dead = Game.Time
	> Party[3].Eradicated = Game.Time; Party[3].Dead = -9999999999
	> Party[3].Dead = -99999999
	> Party[3].Dead = -99999999
	> Party[3].Dead = -99999999; Party[3].Eradicated = 0
]]

-- MM6
-- 00417FD5
function keybindStruct(define)
	define[0x20].u4("action").u4("actionParam")
	[0x2C].u4("prevPtr").u4("nextPtr")
	[0x50].u1("virtualKeyCode")
end

return M