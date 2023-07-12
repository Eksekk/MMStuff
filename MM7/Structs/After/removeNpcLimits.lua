local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

function replacePtrs(addr, offset)
	for i, v in ipairs(addr) do
		i4[v] = i4[addr] + offset
	end
end

-- DataTables.ComputeRowCountInPChar(p, minCols, needCol)
-- minCols is minimum cell count - if less, function stops reading file and returns current count
-- if row has at least needCol cols, current count is updated to its index, otherwise nothing is done

local newNpcDataAddress
do
	local npcLimitRefs = { -- [offset from start] = {addresses...}
		[0] = {0x416AE6, 0x416B3F}
	}
	local gameNpcRefs = {0x416AF0}
	local npcProfRefs = {
		[-4] = {0x416B8F}
	}
	autohook(0x476CD5, function(d)
		-- just loaded npcdata.txt, eax = data pointer, esi = space for processed data
		local count = DataTables.ComputeRowCountInPChar(d.eax, 16, 16)
		newNpcDataAddress = mem.StaticAlloc(1024 * 1024) -- megabyte
		d.esi = newNpcDataAddress
		-- 0x73C028 - text data ptrs, in order: npcdata, npc names, npcprof, npcnews, npctopic, npctext, (empty), npcgreeting, npcgroup
	end)
end

mem.autohook(0x476A81, function(d) -- load npctopic
	
end)

--print((Game.NPCDataTxt.?ptr - Game.NPCDataTxt[0].?size):tohex(), Game.Npc