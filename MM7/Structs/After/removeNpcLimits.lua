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
		[1] = {0x445B41, 0x445C9D, 0x416AEF, 0x420C20, 0x445A69, 0x445AD5, 0x445BA2, 0x445C15, 0x445D0E, 0x44A5A0, 0x45F1C3, 0x45F91E, 0x44BF16, 0x44613D, 0x463528, 0x491B23, 0x491FCA, 0x494156, 0x4BC484, 0x4BC589},
		[2] = {0x420C90, 0x446DC1, 0x4326A8, 0x446D68, 0x44A2E1, 0x44AD77, 0x44B73C, 0x44BFA8, 0x44713B, 0x446D6F, 0x4763B3, 0x49214F,
			0x491B3E, -- directly references Margaret the Docent's hired bit
			0x47638B, -- directly references Baby Dragon's hired bit
			},
		[3] = {0042E269},
		[4] = {0x430687},
	}

	local npcDataRefs = {
		[1] = {0x45F1D0, 0x4613B2, 0x4646DD, 0x465EBE, 0x491B1E},
		size = { -- npc data size and game.npc size is same (at least should be)
			[1] = {0x491B19}
		},
		limit = { -- same as above
			[2] = {0x416AE4, 0x416B3D, 0x420C18, 0x420C6F, 0x42E25B, 0x42E2D0, 0x43067B, 0x4306F0, 0x445AC4, 0x445B1F, 0x445C06, 0x445C67, 0x445CFE, 0x445D53, 0x446132, 0x446187, 0x44A597, 0x44A5E3, 0x44BF0E, 0x44BF2E, 0x463520, 0x463539, 0x4763A7, 0x491FC2, 0x492017, 0x494142, 0x494161, 0x4BC478, 0x4BC4A7, 0x4BC581, 0x4BC5A8},
		}
	}

	-- REMEMBER TO make code copying new npcs from npcdata to savegame npcs if new added

	-- TODO? Grayface removed npc prof limits? might be unnecessary
	local npcProfRefs = {
		[3] = {0x737AB7, 0x416B8C, 0x420CA8, 0x445523, 0x44536B, 0x445545, 0x4455AD, 0x44551A, 0x4455A4, 0x49597C, 0x4B1FE2, 0x4B228C, 0x4B2295, 0x4B22EA, 0x4B2364, 0x4B3DD9, 0x4B4101, 0x4BC67D},
	}

	local npcGroupRefs = {
		[1] = {0x45F229, 0x45F98A, 0x491B34},
		[4] = {0x4224F5, 0x446FD1, 0x46A572},
		size = {
			[1] = {0x491B2D,},
		}
	}
	-- TODO: 0x491B2F has npc groups, which are copied into Game.NPCGroup (or vice versa) at 0x491B2D. Investigate this

	local npcNewsRefs = {
		[3] = {0x422509, 0x46A586},
	}

	local streetNpcRefs = {
		[1] = {0x445A84, 0x445BA2, 0x4613AB},
		count = {
			[1] = {0x46139E, 0x4613BC},
			[2] = {0x46117C, 0x4613C6},
		},
	}

	local npcNamesRefs = {
		[2] = {0x4953BD},
		[3] = {0x49543D, 0x48E9DA},
		count = {
			[2] = {0x4953B5, 0x4953FD, 0x495427},
			[3] = {0x48E9CA}
		}
	}

	--[[
	NPCTopic:       low = 0x7214E8    high = 0x722D90   size = 0x18A8     itemSize = 0x8
	NPCText:        low = 0x7214EC    high = 0x722D94   size = 0x18A8     itemSize = 0x8
	]]

	-- NPC TOPIC ref ends with 8 or 0, NPC TEXT with 4 or C

	-- command sizes below 3 seem to use hardcoded values, 3 and above uses variable topic/text index
	local npcTopicRefs = {
		[1] = {0x445362, },
		[2] = {},
		[3] = {0x4212F7, 0x4457B9, 0x46ABDE, 0x4B2CFF, 0x4B2D80},
		[4] = {0x476A8F0, 0x476B13},
	}

	local npcTextRefs = {
		[1] = {0x416B7F, 0x446EFA, 0x4B1E37, 0x4B24DC, 0x4B262D, 0x4B263B, 0x4B26E9, 0x4B298B, 0x4B29A8, 0x4B29BC, 0x4BBC20, 0x4BBC2A, 0x4BBC31, 0x4BD241, 0x4BD2C9, 0x4BD2D0},
		[2] = {0x431DF1, 0x4956B6, 0x4B1EB0, 0x4B4A56, 0x4B638E, 0x4B6800, 0x4B8CA8},
		[3] = {0x447BEE, 0x447C0D, 0x447C65, 0x4B2654, 0x4B29C3, 0x4B3E61, 0x4B3F57, 0x4B6800, 0x4B8BF5},
		[4] = {0x4769C4},
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