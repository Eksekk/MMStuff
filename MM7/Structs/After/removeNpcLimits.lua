local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

function replacePtrs(addrTable, newAddr, origin, cmdSize)
	for i, oldAddr in ipairs(addrTable) do
		i4[oldAddr + cmdSize] = newAddr - (origin - i4[oldAddr + cmdSize])
	end
end

-- DataTables.ComputeRowCountInPChar(p, minCols, needCol)
-- minCols is minimum cell count - if less, function stops reading file and returns current count
-- if row has at least needCol cols, current count is updated to its index, otherwise nothing is done

do
	--[[
		local format = string.format
		local arrs = {"NPCDataTxt", "NPC", "NPCProfTxt", "NPCProfNames", "NPCTopic", "NPCText", "NPCNews", "NPCGroup", "NPCGreet", "StreetNPC", "NPCNames"}
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
		NPCDataTxt:     low = 0x724050    high = 0x72D50C   size = 0x94BC     itemSize = 0x4C
		NPC:            low = 0x72D50C    high = 0x7369C8   size = 0x94BC     itemSize = 0x4C
		NPCNames:       low = 0x7369C8    high = 0x737AA8   size = 0x10E0     itemSize = 0x8
		NPCProfTxt:     low = 0x737AA8    high = 0x737F44   size = 0x49C      itemSize = 0x14
		StreetNPC:      low = 0x737F44    high = 0x739CF4   size = 0x0        itemSize = 0x4C
		NPCNews:        low = 0x739CF4    high = 0x739DC0   size = 0xCC       itemSize = 0x4
		NPCGreet:       low = 0x73B8D4    high = 0x73BF44   size = 0x670      itemSize = 0x8
		NPCGroup:       low = 0x73BFAA    high = 0x73C010   size = 0x66       itemSize = 0x2
		NPCProfNames:   low = 0x73C110    high = 0x73C1FC   size = 0xEC       itemSize = 0x4
	]]

	-- maybe unrelated addresses: 0x4764B4, 0x4BC81E, 0x4BC82C - reference 0x724048

	-- FIXME: NPCProfNames wasn't included in initial search!
	
	-- npc tables data range: 0x724004 - 0x73C027
	
	local gameNpcRefs = { -- [cmd offset] = {addresses...}
		[1] = {0x00445B41, 0x00445C9D, 0x416AEF, 0x00420C20, 0x00445A69, 0x00445AD5, 0x00445BA2, 0x00445C15, 0x00445D0E, 0x0044A5A0, 0x0045F1C3, 0x0045F91E, 0x0044BF16, 0x0044613D, 0x00463528, 0x00491B23, 0x00491FCA, 0x00494156, 0x004BC484, 0x004BC589},
		[2] = {0x420C90, 0x00446DC1, 0x004326A8, 0x00446D68, 0x0044A2E1, 0x0044AD77, 0x0044B73C, 0x0044BFA8, 0x0044713B, 0x00446D6F, 0x004763B3, 0x0049214F,
			0x00491B3E, -- directly references Margaret the Docent's hired bit
			0x0047638B, -- directly references Baby Dragon's hired bit
			},
		[3] = {0042E269},
		[4] = {0x00430687},
	}

	local npcDataRefs = {
		[1] = {0x0045F1D0, 0x004613B2, 0x004646DD, 0x00465EBE, 0x00491B1E},
		size = { -- npc data size and game.npc size is same (at least should be)
			[1] = {0x00491B19}
		},
		limit = { -- same as above
			[2] = {0x416AE4, 0x416B3D, 0x420C18, 0x420C6F, 0x0042E25B, 0x0042E2D0, 0x0043067B, 0x004306F0, 0x00445AC4, 0x00445B1F, 0x00445C06, 0x00445C67, 0x00445CFE, 0x00445D53, 0x00446132, 0x00446187, 0x0044A597, 0x0044A5E3, 0x0044BF0E, 0x0044BF2E, 0x00463520, 0x00463539, 0x004763A7, 0x00491FC2, 0x00492017, 0x00494142, 0x00494161, 0x004BC478, 0x004BC4A7, 0x004BC581, 0x004BC5A8},
		}
	}

	-- REMEMBER TO make code copying new npcs from npcdata to savegame npcs if new added

	-- TODO? Grayface removed npc prof limits? might be unnecessary
	local npcProfRefs = {
		[3] = {0x737AB7, 0x416B8C, 0x420CA8, 0x00445523, 0x44536B, 0x00445545, 0x004455AD, 0x0044551A, 0x004455A4, 0x0049597C, 0x004B1FE2, 0x004B228C, 0x004B2295, 0x004B22EA, 0x004B2364, 0x004B3DD9, 0x004B4101, 0x004BC67D},
	}

	local npcGroupRefs = {
		[1] = {0x0045F229, 0x0045F98A, 0x00491B34},
		[4] = {0x4224F5, 0x00446FD1, 0x0046A572},
		size = {
			[1] = {0x00491B2D,},
		}
	}
	-- TODO: 0x491B2F has npc groups, which are copied into Game.NPCGroup (or vice versa) at 0x491B2D. Investigate this

	local npcNewsRefs = {
		[3] = {0x422509, 0x0046A586},
	}

	local streetNpcRefs = {
		[1] = {0x00445A84, 0x00445BA2, 0x004613AB},
		count = {
			[1] = {0x0046139E, 0x004613BC},
			[2] = {0x0046117C, 0x004613C6},
		},
	}

	local npcNamesRefs = {
		-- TODO: forgot about this table
		[2] = {0x004953BD},
		[3] = {0x0049543D},
		count = {
			[2] = {0x004953B5, 0x004953FD, 0x00495427},
			[3] = {0x0048E9CA}
		}
	}

	--[[
	NPCTopic:       low = 0x7214E8    high = 0x722D90   size = 0x18A8     itemSize = 0x8
	NPCText:        low = 0x7214EC    high = 0x722D94   size = 0x18A8     itemSize = 0x8
	]]

	-- NPC TOPIC ref ends with 8 or 0, NPC TEXT with 4 or C

	local npcTopicRefs = {

	}

	local npcTextRefs = {

	}

	autohook(0x476CD5, function(d)
		-- just loaded npcdata.txt, eax = data pointer, esi = space for processed data
		local count = DataTables.ComputeRowCountInPChar(d.eax, 16, 16)
		local newNpcDataAddress = mem.StaticAlloc(count * Game.NPCDataTxt.ItemSize)
		d.esi = newNpcDataAddress
		-- 0x73C028 - text data ptrs, in order: npcdata, npc names, npcprof, npcnews, npctopic, npctext, (empty), npcgreeting, npcgroup
	end)
end

mem.autohook(0x476A81, function(d) -- load npctopic
	
end)

--print((Game.NPCDataTxt.?ptr - Game.NPCDataTxt[0].?size):tohex(), Game.Npc