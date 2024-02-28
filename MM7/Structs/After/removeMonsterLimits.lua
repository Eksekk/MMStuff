local u4 = mem.u4
function replacePtrs(addrTable, origin, target)
	for i, v in ipairs(addrTable) do
		u4[v] = u4[v] + target - origin
	end
end

-- monsters txt: 5CCC68 - 5D2868
do return end
-- just loaded monsters txt
mem.autohook(0x455087, function(d)
    -- minimum amount of columns (if any row has less file can't be read) | highest 1-indexed column required (return value is last row which has >= columns)
    count = DataTables.ComputeRowCountInPChar(d.eax, 2, 2) - 1
end)