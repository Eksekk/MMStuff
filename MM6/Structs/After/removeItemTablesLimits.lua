local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

local mmver = offsets.MMVersion
function mmv(...)
	local r = select(mmver - 5, ...)
	assert(r ~= nil)
	return r
end

if mmver ~= 6 then return end

--[[
    REMOVE LIMITS WORKFLOW:
    1) generate above text to facilitate finding references
    2) find all references which are findable by search
    3) patch each place where files are loaded, allocating space for data, asmpatching some addresses to use new data, and replace all references with function call
    4) test and fix all bugs you can find
]]

local function getSpellQueueData(spellQueuePtr, targetPtr)
	local t = {Spell = i2[spellQueuePtr], Caster = Party.PlayersArray[i2[spellQueuePtr + 2]]}
	t.SpellSchool = ceil(t.Spell / 11)
	local flags = u2[spellQueuePtr + 8]
	if flags:And(0x10) ~= 0 then -- caster is target
		t.Caster = Party.PlayersArray[i2[spellQueuePtr + 4]]
	end

	if flags:And(1) ~= 0 then
		t.FromScroll = true
		t.Skill, t.Mastery = SplitSkill(u2[spellQueuePtr + 0xA])
	else
		t.Skill, t.Mastery = SplitSkill(t.Caster:GetSkill(const.Skills.Fire + t.SpellSchool - 1))
	end

	local targetIdKey = mmv("TargetIndex", "TargetIndex", "TargetRosterId")
	if targetPtr then
		if type(targetPtr) == "number" then
			t[targetIdKey], t.Target = internal.GetPlayer(targetPtr)
		else
			t[targetIdKey], t.Target = targetPtr:GetIndex(), targetPtr
		end
	else
		local pl = Party[i2[spellQueuePtr + 4]]
		t[targetIdKey], t.Target = pl:GetIndex(), pl
	end
	return t
end

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

function printSortedArraysData(arrs, dataOrigin)
    arrs = arrs or {"ItemsTxt", "StdItemsTxt", "SpcItemsTxt", "PotionTxt", "ScrollTxt"}
    dataOrigin = dataOrigin or Game.ItemsTxt["?ptr"] - 4
    local out = {}
    for k, name in pairs(arrs) do
        local s = Game[name]
        local low, high, size, itemSize, dataOffset = s["?ptr"], s["?ptr"] + s.Limit * s.ItemSize, s.Size, s.ItemSize, s["?ptr"] - dataOrigin
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
end

function replacePtrs(t) -- addrTable, newAddr, origin, cmdSize, check)
    local func = t.func
    local arr = t.arr or u4
	for i, oldAddr in ipairs(t.addrTable) do
        local arr, oldAddr = arr, oldAddr
        if type(oldAddr) == "table" then
            arr = oldAddr.arr
            oldAddr = oldAddr[1]
        end
		local old = arr[oldAddr + t.cmdSize]
        local new
        if func then
            new = func(old)
        else
		    new = t.newAddr - (t.origin - old)
        end
		t.check(old, new, t.cmdSize, i)
		arr[oldAddr + t.cmdSize] = new
	end
end

local function processReferencesTable(arrName, newAddress, newCount, addressTable, lenP)
    local arr = Game[arrName]
    local origin = arr["?ptr"]
    local lowerBoundIncrease = (addressTable.lowerBoundIncrease or 0) * arr.ItemSize
    addressTable.lowerBoundIncrease = nil -- eliminate special case in loop below
    local oldMin, oldMax = origin - arr.ItemSize - lowerBoundIncrease, origin + (arr.Limit + 1) * arr.ItemSize
    local newMin, newMax = newAddress - arr.ItemSize - lowerBoundIncrease, newAddress + arr.ItemSize * (newCount + 1)
    local function check(old, new, cmdSize, i)
        assert(old >= oldMin and old <= oldMax, format("[%s] old address 0x%X [cmdSize %d; array index %d] is outside array bounds [0x%X, 0x%X] (new entry count: %d)", arrName, old, cmdSize, i, oldMin, oldMax, newCount))
        assert(new >= newMin and new <= newMax, format("[%s] new address 0x%X [cmdSize %d; array index %d] is outside array bounds [0x%X, 0x%X] (new entry count: %d)", arrName, new, cmdSize, i, newMin, newMax, newCount))
    end
    mem.prot(true)
    for cmdSize, addresses in pairs(addressTable) do
        if type(cmdSize) == "number" then
            -- normal refs
            replacePtrs{addrTable = addresses, newAddr = newAddress, origin = origin, cmdSize = cmdSize, check = check}
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
                    elseif what == "high" then
                        memArr[addr + cmdSize] = newCount - 1
                    elseif what == "size" then
                        memArr[addr + cmdSize] = arr.ItemSize * newCount
                    elseif what == "End" then
                        memArr[addr + cmdSize] = newAddress + arr.ItemSize * newCount
                    end
                end
            end
        end
    end
    mem.ChangeGameArray(arrName, newAddress, newCount, lenP)
    mem.prot()
end

-- DataTables.ComputeRowCountInPChar(p, minCols, needCol)
-- minCols is minimum cell count - if less, function stops reading file and returns current count
-- if col #needCol is not empty, current count is updated to its index, otherwise nothing is done - meant to exclude empty entries at the end of some files

do

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
        [2] = {0x42574E, 0x425A07},
        [3] = {0x41CB6E, 0x42576C, 0x4257C6, 0x42580C, 0x425A25, 0x425A7F, 0x425AC5, 0x448640, 0x448754},
        high = {
            [6] = {0x449ECB, arr = u1}
        },
        limit = {
            [1] = {0x425734, 0x425786, 0x4259ED, 0x425A3F},
            [4] = {0x449D7F}
        }
    }

    local stdItemsTxtRefs = {
        [2] = {0x4256CE, 0x425987, 0x425C2A},
        [3] = {0x41CB34, 0x4256F7, 0x4259B0, 0x425C53, 0x44870B},
    }

    local itemsTxtRefs = {
        [1] = {
            0x4218DB, 0x42AB01, 0x43E050, 0x44A09A, 0x450D39, 0x4528BD, 0x452970, 0x4532B2, 0x453800, 0x454290, 0x454B62, 0x456192, 0x4564F2, 0x45664C,
            -- 0x457C66, -- this one is skipped, because it's used before new space is allocated
            0x458A2D, 0x458B53, 0x4857C2, 0x49FCDD, 0x49FEDD
        },
        [2] = {
            0x4123DC, 0x41271D, 0x41289C, 0x4128A5, 0x4129CA, 0x412A43, 0x412A4C, 0x412B14, 0x412B1D, 0x412C20, 0x412CA1, 0x4207D0, 0x4207FC, 0x427BAC, 0x427BDD, 0x42AAF5, 0x42C706, 0x44868D, 0x448696, 0x4486B8, 0x44A089, 0x45A063, 0x45A06D, 0x47D697, 0x47D6EA, 0x47E462, 0x47E468, 0x47E47E, 0x47E4A8, 0x47E578, 0x47E589, 0x47E58F, 0x47E5C2, 0x47EB11, 0x47EB17, 0x47EB36, 0x480CB9, 0x480CBF, 0x481C60, 0x481C72, 0x482EEC, 0x482F00, 0x482F06, 0x4833A6, 0x4833B0, 0x4833EC, 0x4833FB, 0x483439, 0x483445, 0x48344B, 0x483453, 0x48349F, 0x4834AF, 0x4834B5, 0x4834F7, 0x4834FF, 0x483514, 0x48351D, 0x483529, 0x48352F, 0x48353A, 0x483578, 0x483588, 0x48358E, 0x48359A, 0x48362A, 0x483630, 0x48366E, 0x483674, 0x48367F, 0x483A2A, 0x483A34, 0x483B11, 0x483B1B, 0x483B87, 0x483B91, 0x48513F, 0x485164, 0x485826, 0x48588F, 0x4858F8, 0x485961, 0x4859B8, 0x485A0F, 0x485A66, 0x485ABD, 0x485B14, 0x485B6B, 0x485BC2, 0x4A4C42, 0x4A4C85
        },
        [3] = {
            0x40FEE0, 0x40FF00, 0x410FF2, 0x4123E2, 0x4123E9, 0x412497, 0x41249E, 0x412657, 0x41265E, 0x412708, 0x41270F, 0x41292F, 0x412936, 0x4129BC, 0x4129C3, 0x412C30, 0x412C37, 0x412E58, 0x412F10, 0x412FAA, 0x4166A0, 0x41C4F2, 0x41C4FA, 0x41C57D, 0x41DECB, 0x41E0D6, 0x41E288, 0x41EB7A, 0x41ECF9, 0x41F11F, 0x41FE88, 0x420569, 0x4205B0, 0x4206A8, 0x421700, 0x4217E5, 0x4218EE, 0x42558B, 0x425592, 0x4256AB, 0x4256C5, 0x4256EC, 0x425763, 0x4257BE, 0x425801, 0x42584F, 0x425964, 0x42597E, 0x4259A5, 0x425A1C, 0x425A77, 0x425ABA, 0x425B08, 0x425C07, 0x425C21, 0x425C48, 0x429FAB, 0x42A396, 0x431CA0, 0x44861A, 0x448670, 0x448B46, 0x448BD2, 0x44F0D6, 0x458F91, 0x45907B, 0x45997F, 0x45A040, 0x45A967, 0x45BB89, 0x45BD12, 0x47E501, 0x47E625, 0x480BEF, 0x480C60, 0x481AF4, 0x481AFB, 0x481B4A, 0x481B51, 0x481B9C, 0x481BC0, 0x481BFB, 0x4835E5, 0x483C16, 0x483C98, 0x486CFF, 0x486E43, 0x486F37, 0x4870E4, 0x4872B2, 0x496E9E, 0x49758B, 0x4A4434, 0x4A46E6, 0x4A47F6, 0x4A499A
        },
        [5] = {
            0x41FFA4, 0x4208E1, 0x44C2F0, 0x45609A, 0x4561B0, 0x45625A, 0x46CC95, 0x48B2F3
        },
        limit = {
            [1] = {0x449852, 0x40FEC3, 0x448968, 0x448CDA},
            [2] = {0x44966C, 0x449678--[[, 0x449805]], 0x44A6F4}
        }
    }

    -- potion txt: 0x56A77F, 0x56AAC9, 0x9B6F, 0x9EB9

    -- rnditems.txt is ChanceByLevel field of ItemsTxtItem

    local potionTxtRefs = {
        [3] = {0x410BAF}, -- this one really references unused space before, but since it's indexed by [1st potion item id * 29] + [2nd potion id], it uses address inside
        lowerBoundIncrease = 165,
    }
	
    -- various enchantment power ranges etc.
	local otherItemDataRefs = {
        [1] = {0x425734, 0x425786, 0x4259ED, 0x425A3F},
        [2] = {0x425710, 0x425716, 0x4259C9, 0x4259CF, 0x425C6C, 0x425C72},
        [3] = {0x4256B5, 0x42596E, 0x425C11},
    }

    -- relative offsets from item data start
    local relativeItemDataRefs = {
        [2] = {0x448F95, 0x4496C8, 0x449835, 0x44991E, 0x449932, 0x449946, 0x44996B, 0x44997F, 0x449993, 0x4499B8, 0x4499CC, 0x4499E0, 0x449A05, 0x449A19, 0x449A2D, 0x449A4B, 0x449A5C, 0x449A6D, 0x449A8B, 0x449A9C, 0x449AAD, 0x449AFF, 0x449B31, 0x449C32, 0x449C3C, 0x4465DE, 0x449D43, 0x449D75, 0x449EC1, 0x449ECB, 0x449ED5, 0x449EDD, 0x449EF4, 0x44A61B, 0x44A630, 0x44A645, 0x44A65A, 0x44A66F, 0x44A683, 0x44A692, 0x44A69E},
        [3] = {0x448C3B, 0x448C4F}
    }

    -- 0x6BA998 is scroll.txt contents
    autohook(0x468084, function(d)
        -- just loaded scroll.txt
        
        -- needs consideration: make item id be binding instead of row index?
        local count = DataTables.ComputeRowCountInPChar(d.eax, 1, 1)
        local newScrollSpaceAddr = mem.StaticAlloc(count * 4) -- editpchar size
        processReferencesTable("ScrollTxt", newScrollSpaceAddr, count, scrollTxtRefs)
    end)

    -- ITEM DATA MEMORY LAYOUT:
    -- items.txt size, items.txt, stditems.txt, spcitems.txt, 0x3918 placeholder bytes, potions.txt, 4 empty bytes, data pointers (items.txt, rnditems.txt, stditems.txt, spcitems.txt)
    -- sum of all item chances for each of 6 treasure levels from rnditems.txt (0x56AADC, 6 dwords),
    -- bonus chance by level from rnditems.txt (dword, level 1-6): standard, special, special% : 0x56AAF4, 18 dwords
    -- std item bonus chances (column sums) : 0x56AB3C, 9 dwords
    -- std bonus strength ranges: [min, max] for each treasure level: 0x56AB60, 12 dwords
    -- spc item bonus chances (column sums): 0x56AB90, 12 dwords
    -- 0x8 zero bytes
    -- spc items highest index (dword)
    -- 0x20 zero bytes

    local NOP = string.char(0x90)

    local dataPtrs = 0x56AACC -- data pointers
    local itemsTxtDataPtr, rndItemsTxtDataPtr, stdItemsTxtDataPtr, spcItemsTxtDataPtr, useItemsTxtDataPtr = dataPtrs, dataPtrs + 4, dataPtrs + 8, dataPtrs + 12, 0x56F470
    local hooks = HookManager{itemsTxtDataPtr = itemsTxtDataPtr, rndItemsTxtDataPtr = rndItemsTxtDataPtr, stdItemsTxtDataPtr = stdItemsTxtDataPtr, spcItemsTxtDataPtr = spcItemsTxtDataPtr, useItemsTxtDataPtr = useItemsTxtDataPtr, itemsTxtFileName = 0x4BFE04, stdItemsTxtFileName = 0x4BFCD8, spcItemsTxtFileName = 0x4BFCC8, iconsLod = Game.IconsLod["?ptr"], loadFileFromLod = 0x40C1A0, useItemsTxtFileName = 0x4BF9BC, rndItemsTxtFileName = 0x4BFCE8}

    -- load tables
    local addr = hooks.asmpatch(0x44654D, [[
        ; items.txt
        mov ecx, %iconsLod%
        push 0
        push %itemsTxtFileName%
        call absolute %loadFileFromLod%
        mov [%itemsTxtDataPtr%], eax

        ; rnditems.txt
        mov ecx, %iconsLod%
        push 0
        push %rndItemsTxtFileName%
        call absolute %loadFileFromLod%
        mov [%rndItemsTxtDataPtr%], eax

        ; stditems.txt
        mov ecx, %iconsLod%
        push 0
        push %stdItemsTxtFileName%
        call absolute %loadFileFromLod%
        mov [%stdItemsTxtDataPtr%], eax

        ; spcitems.txt
        mov ecx, %iconsLod%
        push 0
        push %spcItemsTxtFileName%
        call absolute %loadFileFromLod%
        mov [%spcItemsTxtDataPtr%], eax

        ; useitems.txt
        mov ecx, %iconsLod%
        push 0
        push %useItemsTxtFileName%
        call absolute %loadFileFromLod%
        mov [%useItemsTxtDataPtr%], eax

        nop
        nop
        nop
        nop
        nop
    ]], 0x1B)

    --> (Game.PotionTxt[164].?ptr + 5):tohex()
  --"56A7F9"

    --for i = 1, 100 do Party[0].Items[1]:Randomize(6) end
    hook(mem.findcode(addr, NOP), function(d)
        local itemCount, stdItemCount, spcItemCount = DataTables.ComputeRowCountInPChar(u4[itemsTxtDataPtr], 0, 1) - 3 + 1, -- 0th item also counts
            DataTables.ComputeRowCountInPChar(u4[stdItemsTxtDataPtr], 1, 1) - 4, DataTables.ComputeRowCountInPChar(u4[spcItemsTxtDataPtr], 1, 2) - 11
        local potionTxtCount = DataTables.ComputeRowCountInPChar(u4[useItemsTxtDataPtr], 0, 2) - 9 -- the file for this is useItems.txt
        --debug.Message(format("items %d, std %d, spc %d, potion %d", itemCount, stdItemCount, spcItemCount, potionTxtCount))

        local origItemDataOffset = Game.ItemsTxt["?ptr"] - 4 -- -4 for size field

        local itemsSize, stdItemsSize, spcItemsSize, potionTxtSize = itemCount * Game.ItemsTxt.ItemSize, stdItemCount * Game.StdItemsTxt.ItemSize, spcItemCount * Game.SpcItemsTxt.ItemSize, potionTxtCount * potionTxtCount
        local newSpace = mem.StaticAlloc(itemsSize + stdItemsSize + spcItemsSize + potionTxtSize + 0x3A40)
        u4[newSpace] = itemCount -- Game.ItemsTxt lenP
        local itemsOffset = newSpace + 4
        local stdItemsOffset = itemsOffset + itemsSize
        local spcItemsOffset = stdItemsOffset + stdItemsSize
        local potionTxtOffset = spcItemsOffset + spcItemsSize + 0x3918
        local otherDataOffset = potionTxtOffset + potionTxtSize

        -- keys are values after which value needs to be added to data offset (requires summing all of those that are passed)
        -- this code block must be run before game arrays are changed
        local breakpoints = {}
        do
            local gameArrays = {4, {Game.ItemsTxt, itemsSize}, {Game.StdItemsTxt, stdItemsSize}, {Game.SpcItemsTxt, spcItemsSize}, 0x3918, {Game.PotionTxt, potionTxtSize}, 0x127}
            local offset = 0
            for i, data in ipairs(gameArrays) do
                if type(data) == "number" then
                    offset = offset + data
                else
                    local size = data[1].Limit * data[1].ItemSize
                    local shift = data[2] - size
                    breakpoints[offset] = shift
                    offset = offset + size
                end
            end
            breakpoints[offset] = 0
            --debug.Message(dump(breakpoints))
        end

        local minOldOff, maxOldOff, minNewOff, maxNewOff = 0, 0, 0, 0
        for offset, shift in pairs(breakpoints) do
            maxOldOff = max(maxOldOff, offset)
            maxNewOff = maxNewOff + shift
        end
        maxNewOff = maxNewOff + maxOldOff

        local function check(old, new, cmdSize, i)
            assert(old >= minOldOff and old <= maxOldOff, format("Old item data offset 0x%X (cmdSize %d, index %d) is outside bounds [0x%X, 0x%X]", old, cmdSize, i, minOldOff, maxOldOff))
            assert(new >= minNewOff and new <= maxNewOff, format("New item data offset 0x%X (cmdSize %d, index %d) is outside bounds [0x%X, 0x%X]", new, cmdSize, i, minNewOff, maxNewOff))
        end

        local function getNewDataOffset(old)
            local val = old
            for offset, shift in pairs(breakpoints) do
                if old >= offset then
                    val = val + shift
                end
            end
            return val
        end

        for cmdSize, addresses in pairs(relativeItemDataRefs) do
            replacePtrs{addrTable = addresses, cmdSize = cmdSize, func = getNewDataOffset, check = check}
        end

        maxOldOff, maxNewOff = maxOldOff + 0x56AADC, maxNewOff + newSpace
        minOldOff, minNewOff = minOldOff + 0x56AADC, minNewOff + newSpace
        for cmdSize, addresses in pairs(otherItemDataRefs) do
            replacePtrs{addrTable = addresses, cmdSize = cmdSize, origin = 0x56AADC, newAddr = otherDataOffset, check = check}
        end

        processReferencesTable("ItemsTxt", itemsOffset, itemCount, itemsTxtRefs, newSpace)
        processReferencesTable("StdItemsTxt", stdItemsOffset, stdItemCount, stdItemsTxtRefs)
        processReferencesTable("SpcItemsTxt", spcItemsOffset, spcItemCount, spcItemsTxtRefs)
        processReferencesTable("PotionTxt", potionTxtOffset, potionTxtCount, potionTxtRefs)

        -- update mmextension hardcoded address
        do
            local i, val = debug.findupvalue(structs.Item.Randomize, "pItems")
            assert(i)
            debug.setupvalue(structs.Item.Randomize, i, newSpace)
        end

        -- esi points at start of data (items.txt size field)
        d.esi = newSpace

        -- correct base pointer
        hooks.ref.newSpace = newSpace
        hooks.asmhook(0x448F72, [[
            mov ebx, %newSpace%
            mov [esp + 0x18], ebx
        ]])

        -- use already loaded tables' data
        asmpatch(0x448F79, "mov eax, " .. u4[itemsTxtDataPtr], 0x16)
        asmpatch(0x4496AC, "mov eax, " .. u4[rndItemsTxtDataPtr], 0x16)
        asmpatch(0x449ADE, "mov eax, " .. u4[stdItemsTxtDataPtr], 0x1B)
        asmpatch(0x449D22, "mov eax, " .. u4[spcItemsTxtDataPtr], 0x1B)

        hooks.ref.lastRndItemsIndex = mem.StaticAlloc(4)

        -- don't require rnditems.txt to have filled data for all items
        hooks.asmpatch(0x4497F9, [[
            ; if there is more data, next character is newline and then a digit
            mov al, [esi + 1]
            cmp al, '0'
            jb @done
            cmp al, '9'
            ja @done
            ; TODO: at most [item count] rows
            jmp @exit
            @done:
                mov [%lastRndItemsIndex%], edi
                jmp absolute 0x449805
            @exit:
                jmp absolute 0x4496F7
        ]], 0xC)

        -- hooks.asmhook(0x4498B0, [[
        --     cmp edi, [%lastRndItemsIndex%]
        --     jg
        -- ]])

        -- generate item function stuff
        do
            local itemBuf = mem.StaticAlloc(itemCount * 4)
            local hooks = HookManager{itemBuf = itemBuf}
            hooks.asmhook2(0x448973, [[
                mov edi, %itemBuf%
            ]])
            hooks.asmpatch(0x44897A, [[
                mov ecx, %itemBuf%
                sub edx,ebx
            ]])
            hooks.asmhook2(0x448A3F, [[
                mov eax, [%itemBuf%]
            ]])
            hooks.asmpatch(0x448A5A, [[
                jge absolute 0x448B40
                mov edi, %itemBuf%
            ]], 0xA)
            hooks.asmhook2(0x448CDF, [[
                mov edi, %itemBuf%
            ]])
            hooks.asmhook2(0x448CFB, [[
                mov edx, %itemBuf%
            ]])
            hooks.asmhook2(0x448E25, [[
                mov eax, [%itemBuf%]
            ]])
            hooks.asmhook2(0x448E5C, [[
                mov eax, %itemBuf%
            ]])
            -- TODO: CHECK
            -- TODO: change all to asmpatches to have no useless instructions? (low priority)
        end

        -- golden touch
        autohook2(0x428722, function(d)
            local t = getSpellQueueData(d.ebx, d.edi)
            t.Item = structs.Item:new(d.esi)
            t.Can = d.SF ~= d.OF -- doesn't include all checks, just the one for item number
            -- set nil to allow vanilla code to decide
            -- vanilla checks:
            -- item id < 400
            -- item not broken
            -- chance check (10% * skill) passed
            events.cocall("CanItemBeAffectedBySpell", t)
            if t.Can ~= nil then
                if t.Can then
                    d:push(0x428758)
                    return true
                else
                    d:push(0x425CE9)
                    return true
                end
            end
        end, 0xC)

        -- 0x448A1F, 0x4497F9, 0x44A70A CONTAIN HIGH OF ITEMS ABLE TO BE GENERATED EXCEPT ARTIFACTS (0x190, 400)
        -- 0x44A6E1 contains last artifact index

        -- can item be generated, TODO: patch all instance3s
        do
            local buf = mem.StaticAlloc(itemCount)
            mem.fill(buf, 400, 1) -- normal items
            mem.fill(buf + 400, itemCount - 400, 0) -- artifacts and quest items and after
            local can = setmetatable({}, {__index = function(_, i)
                if i > itemCount then
                    error(format("Invalid item id %d", i), 2)
                end
                return u1[buf + i - 1] ~= 0
            end,
            __newindex = function(_, i, v)
                if i > itemCount then
                    error(format("Invalid item id %d", i), 2)
                end
                u1[buf + i - 1] = v and 1 or 0
            end})
            -- if value at index idx is 0, item idx cannot be generated (artifacts and quest items by default), otherwise it can
            evt.CanItemBeRandomlyFound = can
            HookManager{
                buf = buf, itemCount = itemCount
            }.asmpatch(0x448A1F, [[
                ; edi = item id
                mov cl, [%buf% + edi - 1]
                test cl, cl
                jne absolute 0x4489A2
                ; current cannot be generated - find first which can
                push esi
                xchg esi, edi
                lea edi, [%buf% + esi]
                mov ecx, %itemCount%
                sub ecx, esi
                push eax
                mov al, 1
                repne scasb
                pop eax
                xchg esi, edi
                pop esi
                jne @exit
                sub edi, %buf% - 1
                jmp absolute 0x4489A2
                @exit:
            ]], 0xC)
        end

        -- asmpatch(0x4497F9, "cmp edi," .. itemCount)

        mem.hookfunction(0x44A6B0, 1, 0, function(d, def, itemPtr)
            local item = structs.Item:new(itemPtr)
            local t = {Item = item, Allow = true}
            events.cocall("GenerateArtifact", t)
            if t.Allow then
                def(itemPtr)
            end
            events.cocall("ArtifactGenerated", t)
        end)

        -- TODO: generateArtifact (0x44A6B0)

        -- 0x440D43, 0x441891 contains check for artifact added to mouse and if it's artifact, marks as found
        
        -- MOVE TABLE DATA POINTERS

        -- size: std done, spc done, items done, potion done, scroll done
        -- limit: 
        ------ hardcoded: scroll done, potion done, spc done, std done (?), items done (absolute limit), possible to generate (0x190) done and artifacts and below (.429) TODO-ed)
        ------ address of variable: items done?
        -- count: 
        -- end: 
        -- GAME EXIT CLEANUP FUNCTION
    end)
end

function events.CanItemBeAffectedBySpell(t)
    -- TODO
end