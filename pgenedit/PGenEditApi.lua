--[[
local loadSub = {"defaultPlayerData"
local data = setmetatable({}, __index = function(data, k)
	if k ==  then
		M.dll.loadData(data, k)
	end
end)
]]