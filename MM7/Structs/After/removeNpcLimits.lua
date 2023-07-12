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
		local format = string.format
		local arrs = {"NPCDataTxt", "NPC", "NPCProfTxt", "NPCProfNames", "NPCTopic", "NPCText", "NPCNews", "NPCGroup", "NPCGreet", "StreetNPC"}
		local out = {}
		for k, name in pairs(arrs) do
			local s = Game[name]
			local low, high, size, itemSize = s["?ptr"], s["?ptr"] + s.Limit * s.ItemSize, s.Size, s.ItemSize
			table.insert(out, {name = name, low = low, high = high, size = size, itemSize = itemSize})
		end
		table.sort(out, function(a, b) return a.low < b.low end)
		for _, data in ipairs(out) do
			print(format("%-15s %-17s %-17s %-17s itemSize = 0x%X", data.name .. ":", format("low = 0x%X", data.low), format("high = 0x%X", data.high), format("size = 0x%X", data.size), data.itemSize))
		end
	]]

	--[[
		NPCTopic:       low = 0x7214E8    high = 0x722D90   size = 0x18A8     itemSize = 0x8
		NPCText:        low = 0x7214EC    high = 0x722D94   size = 0x18A8     itemSize = 0x8
		NPCDataTxt:     low = 0x724050    high = 0x72D50C   size = 0x94BC     itemSize = 0x4C
		NPC:            low = 0x72D50C    high = 0x7369C8   size = 0x94BC     itemSize = 0x4C
		NPCProfTxt:     low = 0x737AA8    high = 0x737F44   size = 0x49C      itemSize = 0x14
		StreetNPC:      low = 0x737F44    high = 0x739CF4   size = 0x0        itemSize = 0x4C
		NPCNews:        low = 0x739CF4    high = 0x739DC0   size = 0xCC       itemSize = 0x4
		NPCGreet:       low = 0x73B8D4    high = 0x73BF44   size = 0x670      itemSize = 0x8
		NPCGroup:       low = 0x73BFAA    high = 0x73C010   size = 0x66       itemSize = 0x2
		NPCProfNames:   low = 0x73C110    high = 0x73C1FC   size = 0xEC       itemSize = 0x4
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