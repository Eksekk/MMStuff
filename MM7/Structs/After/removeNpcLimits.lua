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

do
	--[[
		local arrs = {"NPCDataTxt", "NPC", "NPCProfTxt", "NPCProfNames", "NPCTopic", "NPCText", "NPCNews", "NPCGroup", "NPCGreet", "StreetNPC"}
		local out = {}
		for k, name in pairs(arrs) do
			local s = Game[name]
			local low, high, size, itemSize = s["?ptr"], s["?ptr"] + s.Limit * s.ItemSize, s.Size, s.ItemSize
			table.insert(out, {name = name, low = low, high = high, size = size, itemSize = itemSize})
			print(string.format("%s: low = 0x%X, high = 0x%X, size = 0x%X, itemSize = 0x%X", name, low, high, size, itemSize))
		end
		table.sort(out, function(a, b) return a.low < b.low end)
		for _, data in ipairs(out) do
			print(string.format("%s: low = 0x%X, high = 0x%X, size = 0x%X, itemSize = 0x%X", data.name, data.low, data.high, data.size, data.itemSize))
		end
	]]
	
	-- npc tables data range: 0x724004 - 0x73C027
	local npcLimitRefs = { -- [cmd offset] = {[offset from data start] = {addresses...}}
		[2] = {
			[0] = {0x416AE4, 0x416B3D, 0x420C18, 0x420C6F, 0x0042E25B, 0x0042E2D0, 0x0043067B, 0x004306F0},
		},
		--[0] = {0x416AE4, 0x416B3F}
	}
	local gameNpcRefs = {
		[1] = {
			[0] = {0x416AEF, 0x00420C20},
		},
		[2] = {
			[-0x98] = {0x420C90},
			[8] = {0x004326A8},
		},
		[3] = {
			[0] = {0042E269},
		},
		[4] = {
			[0] = {0x00430687},
		},
	}
	local npcProfRefs = {
		[3] = {
			[0] = {0x420CA8},
			[-4] = {0x416B8C},
			[-12] = {0x737AB7},
		},
	}
	local npcGroupRefs = {
		[4] = {
			[0] = {0x4224F5},
		},
	}
	local npcNewsRefs = {
		[3] = {
			[0] = {0x422509},
		},
	}
	autohook(0x476CD5, function(d)
		-- just loaded npcdata.txt, eax = data pointer, esi = space for processed data
		local count = DataTables.ComputeRowCountInPChar(d.eax, 16, 16)
		local newNpcDataAddress = mem.StaticAlloc(count * Game.NPCDataTxt["?size"])
		d.esi = newNpcDataAddress
		-- 0x73C028 - text data ptrs, in order: npcdata, npc names, npcprof, npcnews, npctopic, npctext, (empty), npcgreeting, npcgroup
	end)
end

mem.autohook(0x476A81, function(d) -- load npctopic
	
end)

--print((Game.NPCDataTxt.?ptr - Game.NPCDataTxt[0].?size):tohex(), Game.Npc