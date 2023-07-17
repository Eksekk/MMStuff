local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

if offsets.MMVersion ~= 7 then return end

function arrayFieldOffsetName(arr, offset)
	local i = offset:div(arr.ItemSize)
	local off = offset % arr.ItemSize
	for k, v in pairs(structs.o[structs.name(arr[0])]) do
		if v == off then
			print(k)
			return
		end
	end
	print("not found")
end

local arrs = {"ItemsTxt", "StdItemsTxt", "SpcItemsTxt", "PotionTxt", "ScrollTxt"}
local arrPtrs = {}
for i, v in ipairs(arrs) do
	arrPtrs[i] = Game[v]["?ptr"]
end
local npcDataPtr = Game.NPCDataTxt["?ptr"]
function npcArrayFieldOffsetName(offset)
	for i, v in ipairs(arrs) do
		local dataOffset = arrPtrs[i] - npcDataPtr
		local nextOffset = (i ~= #arrs and (arrPtrs[i + 1] - npcDataPtr) or 0)
		if offset >= dataOffset and offset <= nextOffset then
			print(v)
			arrayFieldOffsetName(Game[v], offset - dataOffset)
			return
		end
	end
	print("Couldn't find NPC array for given offset")
end

function replacePtrs(addrTable, newAddr, origin, cmdSize, check)
	for i, oldAddr in ipairs(addrTable) do
		local old = u4[oldAddr + cmdSize]
		local new = newAddr - (origin - old)
		check(old, new, cmdSize, i)
		u4[oldAddr + cmdSize] = new
	end
end

-- DataTables.ComputeRowCountInPChar(p, minCols, needCol)
-- minCols is minimum cell count - if less, function stops reading file and returns current count
-- if col #needCol is not empty, current count is updated to its index, otherwise nothing is done - meant to exclude empty entries at the end of some files

do
	--[[
		local format = string.format
		local arrs = {"ItemsTxt", "StdItemsTxt", "SpcItemsTxt", "PotionTxt", "ScrollTxt"}
		local out = {}
		for k, name in pairs(arrs) do
			local s = Game[name]
			local low, high, size, itemSize, dataOffset = s["?ptr"], s["?ptr"] + s.Limit * s.ItemSize, s.Size, s.ItemSize, s["?ptr"] - Game.ItemsTxt["?ptr"]
			table.insert(out, {name = name, low = low, high = high, size = size, itemSize = itemSize, dataOffset = dataOffset})
		end
		table.sort(out, function(a, b) return a.low < b.low end)
		for _, data in ipairs(out) do
			print(format("%-15s %-17s %-17s %-17s %-17s %-17s",
				data.name .. ":",
				format("low = 0x%X", data.low),
				format("high = 0x%X", data.high),
				format("size = 0x%X", data.size),
				format("itemSize = 0x%X", data.itemSize), 
				format("dataOffset = 0x%X", data.dataOffset)
			))
		end
	]]

	--[[
		ItemsTxt:       low = 0x560C14    high = 0x5666DC   size = 0x5AC8     itemSize = 0x28   dataOffset = 0x0 
        StdItemsTxt:    low = 0x5666DC    high = 0x5667F4   size = 0x118      itemSize = 0x14   dataOffset = 0x5AC8
        SpcItemsTxt:    low = 0x5667F4    high = 0x566E68   size = 0x674      itemSize = 0x1C   dataOffset = 0x5BE0
        PotionTxt:      low = 0x56A780    high = 0x56AAC9   size = 0x349      itemSize = 0x1D   dataOffset = 0x9B6C
        ScrollTxt:      low = 0x6A86A8    high = 0x6A8804   size = 0x15C      itemSize = 0x4    dataOffset = 0x147A94
	]]

    local scrollTxtRefs = {
        [3] = {0x458EDD, 0x459010},
        [4] = {0x468097},
        End = {
            [1] = {0x46810E}
        }
    }

    local spcItemsTxtRefs = {
        [2] = {0x0042574E, 0x00425A07},
        [3] = {0x0041CB6E, 0x0042576C, 0x004257C6, 0x0042580C, 0x00425A25, 0x00425A7F, 0x00425AC5, 0x00448640, 0x00448754}
    }

    local stdItemsTxtRefs = {
        [2] = {0x004256CE, 0x00425987, 0x00425C2A},
        [3] = {0x0041CB34, 0x004256F7, 0x004259B0, 0x00425C53, 0x0044870B}
    }

    local itemsTxtRefs = {
        [1] = {},
        [2] = {},
        [3] = {},
        [4] = {},
        [5] = {},
        [6] = {},
    }

	--[[
		REMOVE LIMITS WORKFLOW:
		1) generate above text to facilitate finding references
		2) find all references which are findable by search
		3) patch each place where files are loaded, allocating space for data, asmpatching some addresses to use new data, and replace all references with function call
		4) test and fix all bugs you can find
	]]

	-- maybe unrelated addresses: 0x4764B4, 0x4BC81E, 0x4BC82C - reference 0x724048
	
	-- npc tables data range: 0x724004 - 0x73C027
	
	local gameNpcRefs = { -- [cmd offset] = {addresses...}
        }

	local function processReferencesTable(arrName, newAddress, newCount, addressTable)
		local arr = Game[arrName]
		local origin = arr["?ptr"]
		local lowerBoundIncrease = (addressTable.lowerBoundIncrease or 0) * arr.ItemSize
		addressTable.lowerBoundIncrease = nil -- eliminate special case in loop below
		local oldMin, oldMax = origin - arr.ItemSize - lowerBoundIncrease, origin + arr.Size + arr.ItemSize
		local newMin, newMax = newAddress - arr.ItemSize - lowerBoundIncrease, newAddress + arr.ItemSize * (newCount + 1)
		local function check(old, new, cmdSize, i)
			assert(old >= oldMin and old <= oldMax, format("[%s] old address 0x%X [cmdSize %d; array index %d] is outside array bounds [0x%X, 0x%X] (new entry count: %d)", arrName, old, cmdSize, i, oldMin, oldMax, newCount))
			assert(new >= newMin and new <= newMax, format("[%s] new address 0x%X [cmdSize %d; array index %d] is outside array bounds [0x%X, 0x%X] (new entry count: %d)", arrName, new, cmdSize, i, newMin, newMax, newCount))
		end
		mem.prot(true)
		for cmdSize, addresses in pairs(addressTable) do
			if type(cmdSize) == "number" then
				-- normal refs
				replacePtrs(addresses, newAddress, origin, cmdSize, check)
			else
				-- special refs
				local what = cmdSize
				local memArr = addresses.arr or i4
				for cmdSize, addresses in pairs(addresses) do
					for i, data in ipairs(addresses) do
						-- support per-address mem array types
						local memArr, addr = memArr -- intentionally override local
						if type(data) == "table" then
							memArr = data.arr or memArr
							addr = data[1]
						else
							addr = data
						end
						if what == "limit" then
							memArr[addr + cmdSize] = memArr[addr + cmdSize] - arr.Limit + newCount
						elseif what == "count" then
							-- skip (I don't move count addresses atm)
						elseif what == "size" then
							memArr[addr + cmdSize] = arr.ItemSize * newCount
						elseif what == "End" then
							memArr[addr + cmdSize] = newAddress + arr.ItemSize * newCount
						end
					end
				end
			end
		end
		mem.ChangeGameArray(arrName, newAddress, newCount)
		mem.prot()
	end
end