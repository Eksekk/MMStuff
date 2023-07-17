local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

if offsets.MMVersion ~= 6 then return end

function arrayFieldOffsetName(arr, offset)
    if offset >= arr["?ptr"] then
        offset = offset - arr["?ptr"]
    end
    if offset < 0 then
        offset = offset + arr.ItemSize
    end
	local i = offset:div(arr.ItemSize)
	local off = offset % arr.ItemSize
    local minDiffBelow, minDiffBelowName
	for k, v in pairs(structs.o[structs.name(arr[0])]) do
		if v == off then
			return k
        elseif not minDiffBelow or off - v < minDiffBelow then
            minDiffBelow = off - v
            minDiffBelowName = k
        end
	end
    return minDiffBelowName, true
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

local itemsTxtRawAddresses = {
    0x40FEE0, 0x40FF00, 0x410FF2, 0x4123DC, 0x4123E2, 0x4123E9, 0x412497, 0x41249E, 0x412657, 0x41265E, 0x412708, 0x41270F, 0x41271D, 0x41289C, 0x4128A5, 0x41292F, 0x412936, 0x4129BC, 0x4129C3, 0x4129CA, 0x412A43, 0x412A4C, 0x412B14, 0x412B1D, 0x412C20, 0x412C30, 0x412C37, 0x412CA1, 0x412E58, 0x412F10, 0x412FAA, 0x4166A0, 0x41C4F2, 0x41C4FA, 0x41C57D, 0x41CB34, 0x41DECB, 0x41E0D6, 0x41E288, 0x41EB7A, 0x41ECF9, 0x41F11F, 0x41FE88, 0x41FFA4, 0x420569, 0x4205B0, 0x4206A8, 0x4207D0, 0x4207FC, 0x4208E1, 0x421700, 0x4217E5, 0x4218DB, 0x4218EE, 0x42558B, 0x425592, 0x4256AB, 0x4256C5, 0x4256CE, 0x4256EC, 0x4256F7, 0x425763, 0x4257BE, 0x425801, 0x42584F, 0x425964, 0x42597E, 0x425987, 0x4259A5, 0x4259B0, 0x425A1C, 0x425A77, 0x425ABA, 0x425B08, 0x425C07, 0x425C21, 0x425C2A, 0x425C48, 0x425C53, 0x427BAC, 0x427BDD, 0x429FAB, 0x42A396, 0x42AAF5, 0x42AB01, 0x42C706, 0x431CA0, 0x43E050, 0x44861A, 0x448670, 0x44868D, 0x448696, 0x4486B8, 0x44870B, 0x448B46, 0x448BD2, 0x44A089, 0x44A09A, 0x44C2F0, 0x44F0D6, 0x450D39, 0x4528BD, 0x452970, 0x4532B2, 0x453800, 0x454290, 0x454B62, 0x45609A, 0x456192, 0x4561B0, 0x45625A, 0x4564F2, 0x45664C, 0x457C66, 0x458A2D, 0x458B53, 0x458F91, 0x45907B, 0x45997F, 0x45A040, 0x45A063, 0x45A06D, 0x45A967, 0x45BB89, 0x45BD12, 0x46CC95, 0x47D697, 0x47D6EA, 0x47E462, 0x47E468, 0x47E47E, 0x47E4A8, 0x47E501, 0x47E578, 0x47E589, 0x47E58F, 0x47E5C2, 0x47E625, 0x47EB11, 0x47EB17, 0x47EB36, 0x480BEF, 0x480C60, 0x480CB9, 0x480CBF, 0x481AF4, 0x481AFB, 0x481B4A, 0x481B51, 0x481B9C, 0x481BC0, 0x481BFB, 0x481C60, 0x481C72, 0x482EEC, 0x482F00, 0x482F06, 0x4833A6, 0x4833B0, 0x4833EC, 0x4833FB, 0x483439, 0x483445, 0x48344B, 0x483453, 0x48349F, 0x4834AF, 0x4834B5, 0x4834F7, 0x4834FF, 0x483514, 0x48351D, 0x483529, 0x48352F, 0x48353A, 0x483578, 0x483588, 0x48358E, 0x48359A, 0x4835E5, 0x48362A, 0x483630, 0x48366E, 0x483674, 0x48367F, 0x483A2A, 0x483A34, 0x483B11, 0x483B1B, 0x483B87, 0x483B91, 0x483C16, 0x483C98, 0x48513F, 0x485164, 0x4857C2, 0x485826, 0x48588F, 0x4858F8, 0x485961, 0x4859B8, 0x485A0F, 0x485A66, 0x485ABD, 0x485B14, 0x485B6B, 0x485BC2, 0x486CFF, 0x486E43, 0x486F37, 0x4870E4, 0x4872B2, 0x48B2F3, 0x496E9E, 0x49758B, 0x49FCDD, 0x49FEDD, 0x4A4434, 0x4A46E6, 0x4A47F6, 0x4A499A, 0x4A4C42, 0x4A4C85,
}

function processRawAddresses(arrayName)
    -- 1. command size
    -- 2. array offset and field name
    
    -- only processes direct references - count, limit, size still need to be done manually
    local results = {}
    local arr = Game[arrayName]
    local lower, upper = arr["?ptr"] - arr.ItemSize, arr["?ptr"] + arr.Size + arr.ItemSize
    for i, addr in ipairs(itemsTxtRawAddresses) do
        local len = mem.GetInstructionSize(addr)
        if len < 5 then -- minimum size
            error(format("Address 0x%X has instruction size less than 5", addr))
        end
        -- find command size and if there are instruction bytes after memory offsets
        local cmdSize, hasFreeBytes
        for i = 0, len - 4 do
            local val = u4[addr + i]
            if val >= lower and val <= upper then -- found
                if cmdSize then -- found twice
                    error(format("Address 0x%X has two valid references to array", addr))
                end
                cmdSize = i
                hasFreeBytes = (addr + i + 4 ~= len)
            end
        end
        if not cmdSize then
            error(format("No array reference found at address 0x%X", addr))
        end
        local name, notBeginning = arrayFieldOffsetName(arr, u4[addr + cmdSize])
        if not name then
            error(format("Couldn't find structure field for reference at address 0x%X", addr))
        end
        print(format("Address 0x%X, cmdSize %d, references 0x%X, field name %q (%s)",
            addr, cmdSize, u4[addr + cmdSize], name, notBeginning and "NB" or "B"))
        
        table.insert(results, {address = addr, cmdSize = cmdSize, reference = u4[addr + cmdSize], fieldName = name, notFieldBeginning = notBeginning, hasFreeBytes = hasFreeBytes})
    end
    local output = {}
    local ptr = arr["?ptr"]
    local justBeforeEnd = ptr + arr.Size - arr.ItemSize
    for _, data in ipairs(results) do
        if data.address == ptr + arr.ItemSize then -- end reference?
            table.insert(tget(output, "End"), data.address)
        elseif data.notFieldBeginning then
            table.insert(tget(output, "verify"), data.address)
        else
            if data.address >= justBeforeEnd then
                table.insert(tget(output, data.cmdSize), {addr = data.address, verifyMe = true})
            else
                table.insert(tget(output, data.cmdSize), data.address)
            end
        end
    end
    local text = dump(output, nil, true):gsub("%d+", function(num) return format("0x%X", num) end)
    --print(text)
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
		local arrs = {"ItemsTxt", "StdItemsTxt", "SpcItemsTxt", "Rnd" "PotionTxt", "ScrollTxt"}
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
        [1] = {
            0x4218DB, 0x42AB01, 0x43E050, 0x44A09A, 0x450D39, 0x4528BD, 0x452970, 0x4532B2, 0x453800, 0x454290, 0x454B62, 0x456192, 0x4564F2, 0x45664C, 0x457C66, 0x458A2D, 0x458B53, 0x4857C2, 0x49FCDD, 0x49FEDD
        },
        [2] = {
            0x4123DC, 0x41271D, 0x41289C, 0x4128A5, 0x4129CA, 0x412A43, 0x412A4C, 0x412B14, 0x412B1D, 0x412C20, 0x412CA1, 0x4207D0, 0x4207FC, 0x427BAC, 0x427BDD, 0x42AAF5, 0x42C706, 0x44868D, 0x448696, 0x4486B8, 0x44A089, 0x45A063, 0x45A06D, 0x47D697, 0x47D6EA, 0x47E462, 0x47E468, 0x47E47E, 0x47E4A8, 0x47E578, 0x47E589, 0x47E58F, 0x47E5C2, 0x47EB11, 0x47EB17, 0x47EB36, 0x480CB9, 0x480CBF, 0x481C60, 0x481C72, 0x482EEC, 0x482F00, 0x482F06, 0x4833A6, 0x4833B0, 0x4833EC, 0x4833FB, 0x483439, 0x483445, 0x48344B, 0x483453, 0x48349F, 0x4834AF, 0x4834B5, 0x4834F7, 0x4834FF, 0x483514, 0x48351D, 0x483529, 0x48352F, 0x48353A, 0x483578, 0x483588, 0x48358E, 0x48359A, 0x48362A, 0x483630, 0x48366E, 0x483674, 0x48367F, 0x483A2A, 0x483A34, 0x483B11, 0x483B1B, 0x483B87, 0x483B91, 0x48513F, 0x485164, 0x485826, 0x48588F, 0x4858F8, 0x485961, 0x4859B8, 0x485A0F, 0x485A66, 0x485ABD, 0x485B14, 0x485B6B, 0x485BC2, 0x4A4C42, 0x4A4C85
        },
        [3] = {
            0x40FEE0, 0x40FF00, 0x410FF2, 0x4123E2, 0x4123E9, 0x412497, 0x41249E, 0x412657, 0x41265E, 0x412708, 0x41270F, 0x41292F, 0x412936, 0x4129BC, 0x4129C3, 0x412C30, 0x412C37, 0x412E58, 0x412F10, 0x412FAA, 0x4166A0, 0x41C4F2, 0x41C4FA, 0x41C57D, 0x41CB34, 0x41DECB, 0x41E0D6, 0x41E288, 0x41EB7A, 0x41ECF9, 0x41F11F, 0x41FE88, 0x420569, 0x4205B0, 0x4206A8, 0x421700, 0x4217E5, 0x4218EE, 0x42558B, 0x425592, 0x4256AB, 0x4256C5, 0x4256EC, 0x425763, 0x4257BE, 0x425801, 0x42584F, 0x425964, 0x42597E, 0x4259A5, 0x425A1C, 0x425A77, 0x425ABA, 0x425B08, 0x425C07, 0x425C21, 0x425C48, 0x429FAB, 0x42A396, 0x431CA0, 0x44861A, 0x448670, 0x44870B, 0x448B46, 0x448BD2, 0x44F0D6, 0x458F91, 0x45907B, 0x45997F, 0x45A040, 0x45A967, 0x45BB89, 0x45BD12, 0x47E501, 0x47E625, 0x480BEF, 0x480C60, 0x481AF4, 0x481AFB, 0x481B4A, 0x481B51, 0x481B9C, 0x481BC0, 0x481BFB, 0x4835E5, 0x483C16, 0x483C98, 0x486CFF, 0x486E43, 0x486F37, 0x4870E4, 0x4872B2, 0x496E9E, 0x49758B, 0x4A4434, 0x4A46E6, 0x4A47F6, 0x4A499A
        },
        [5] = {
            0x41FFA4, 0x4208E1, 0x44C2F0, 0x45609A, 0x4561B0, 0x45625A, 0x46CC95, 0x48B2F3
        },
        verify = {
            0x4256CE, 0x4256F7, 0x425987, 0x4259B0, 0x425C2A, 0x425C53
        }
    }

    -- rnditems.txt is ChanceByLevel field of ItemsTxtItem

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

    -- 0x6BA998 is scroll.txt contents
    autohook(0x468084, function(d)
        -- just loaded scroll.txt
        
        -- needs consideration: make item id be binding instead of row index?
        local count = DataTables.ComputeRowCountInPChar(d.eax, 1, 1)
        local newScrollSpaceAddr = mem.StaticAlloc(count * 4) -- editpchar size
        processReferencesTable("ScrollTxt", newScrollSpaceAddr, count, scrollTxtRefs)
    end)

    -- MEMORY LAYOUT:
    -- items.txt size, items.txt, stditems.txt, spcitems.txt

    local tablePtrs = mem.StaticAlloc(12)

    local NOP = string.char(0x90)

    autohook(0x448F8F, function(d)
        -- just loaded items.txt

        -- ebx points at items.txt limit, ebx + 4 contains data
        local dataPtrs = 0x56AACC -- data pointers: items.txt, rnditems.txt, stditems.txt, spcitems.txt
        local hooks = HookManager{itemsTxtDataPtr = dataPtrs, stdItemsTxtDataPtr = dataPtrs + 8, spcItemsTxtDataPtrs = dataPtrs + 12, itemsTxtFileName = 0x4BFE04, stdItemsTxtFileName = 0x4BFCD8, spcItemsTxtFileName = 0x4BFCC8, iconsLod = Game.IconsLod["?ptr"], loadFileFromLod = 0x40C1A0}

        -- load tables
        local addr = hooks.asmpatch(0x448F79, [[
            ; esi = 0

            ; items.txt
            mov ecx, %iconsLod%
            push esi
            push %itemsTxtFileName%
            call absolute %loadFileFromLod%
            mov [%itemsTxtDataPtr%], eax

            ; stditems.txt
            mov ecx, %iconsLod%
            push esi
            push %stdItemsTxtFileName%
            call absolute %loadFileFromLod%
            mov [%stdItemsTxtDataPtr%], eax

            ; spcitems.txt
            mov ecx, %iconsLod%
            push esi
            push %spcItemsTxtFileName%
            call absolute %loadFileFromLod%
            mov [%spcItemsTxtDataPtr%], eax
            nop
            nop
            nop
            nop
            nop
        ]], 0x16)

        hook(mem.findcode(addr, NOP), function(d)
        
        end)
        
        hooks.asmpatch(0x448F95, "mov dword ptr [%itemsTxtDataPtr%],eax")
    end)
end