local lookupTable = {}
function getRange(str)
	if lookupTable[str] then return lookupTable[str][1], lookupTable[str][2] end
	local min, max = str:match("(%d+)%-(%d+)")
	min = tonumber(min)
	max = tonumber(max)
	assert(min ~= nil and max ~= nil)
	lookupTable[str] = {min, max}
	return min, max
end

local function getMinMaxCount(value)
	if type(value) == "string" then
		return getRange(value)
	elseif type(value) == "table" then
		return value[1], value[2]
	elseif type(value) == "number" then
		return value, value
	else
		error("Unsupported count type", 3)
	end
end

local random = math.random
function pseudoSpawnpoint(monster, x, y, z, count, powerChances, radius, group, exactZ)
	local t = {} -- will hold arguments
	if type(monster) == "table" then
		t = monster -- user passed table with arguments instead of monster
	else
		-- pack all arguments into a table
		t.monster = monster
		t.x, t.y, t.z = x, y, z
		t.count = count
		t.powerChances = powerChances
		t.radius = radius
		t.group = group
		t.exactZ = exactZ
	end
	t.count = t.count or "1-3" -- count is 1-3 by default (if unspecified)
	t.powerChances = t.powerChances or {34, 33, 33}
	t.radius = t.radius or 256
	assert(t.monster and t.x and t.y and (not t.exactZ or t.z), "pseudoSpawnpoint() call is missing critical parameters") -- make sure that all required parameters are provided
	local class = (t.monster + 2):div(3) -- class now contains id of monster class (group of 3 monsters of increasing tiers, as all types are divided into 3 tiers)
	
	local toCreate = random(getMinMaxCount(t.count)) -- will hold how many monsters to create
	
	local summoned = {} -- will hold summoned monsters to return
	for i = 1, toCreate do
		if Map.Monsters.Count >= Map.Monsters.Limit - 20 then
			return summoned
		end
		local x, y, z
		local spawnAttempts = 0
		local maxAttempts = t.maxSpawnAttempts or 20
		local failReasons = {}
		while true do
			-- generate random point in a circle centered on provided xy and with provided radius
			local angle = random() * math.pi * 2
			local xadd = math.cos(angle) * random(1, t.radius)
			local yadd = math.sin(angle) * random(1, t.radius)
			x, y = t.x + xadd, t.y + yadd
			z = not t.exactZ and Map.IsOutdoor() and Map.GetGroundLevel(x, y) or t.z
			if Map.IsIndoor() and Map.RoomFromPoint(x, y, z) > 0 then -- room from point check makes sure that monsters won't generate in a wall
				break
			elseif Map.IsIndoor() then
				table.insert(failReasons, {"monster generated in a wall", x, y, z})
			elseif Map.IsOutdoor() then
				-- check if 
				local tilesetFileSuffixes = {[0] = "", [1] = 2, [2] = 3}
				local tilesetsFile = "Tile" .. (Game.Version == 8 and (tilesetFileSuffixes[Map.TilesetsFile] or error("Unknown tileset file " .. Map.TilesetsFile)) or "") .. "Bin"
				local tileId = Map.TileMap[(64 - y / 0x200):floor()][(64 + x / 0x200):floor()]
				if Game[tilesetsFile][tileId].Water and Game.MonstersTxt[class * 3 - 2].Fly == 0 then
					table.insert(failReasons, {"non-flying monster generated above water", x, y, z})
				else
					break
				end
			end
			spawnAttempts = spawnAttempts + 1
			if spawnAttempts >= maxAttempts then
				local t2 = {}
				for i, v in ipairs(failReasons) do
					table.insert(t2, string.format("%d:	reason: %s		x: %d	y: %d	z: %d", i, unpack(v)))
				end
				local errorMessage = "\nCouldn't spawn monster, spawnpoint data: " .. dump(t) .. "\n\nSubsequent spawn failure reasons:\n" .. table.concat(t2, "\n")
				error(errorMessage, 2)
			end
		end
		
		-- generate random monster power according to defined powerChances
		local power
		local rand = random(1, 100)
		if t.powerChances[1] ~= 0 and (rand <= t.powerChances[1] or (t.powerChances[2] == 0 and t.powerChances[3] == 0)) then
			power = 0
		elseif t.powerChances[2] ~= 0 and ((rand <= t.powerChances[2] + t.powerChances[1]) or (t.powerChances[1] == 0 and t.powerChances[3] == 0)) then
			power = 1
		elseif t.powerChances[3] ~= 0 then
			power = 2
		elseif t.powerChances[2] ~= 0 then
			power = 1
		else
			power = 0
		end
		
		-- perform transform if it is set
		-- need roundabout way for Merge because bolster there screws things up without heavy modifications to it, including new event below
		local doneMerge
		local transform = type(t.transform) == "function" and t.transform
		if Merge and transform then
			function events.SummonMonster(mon)
				doneMerge = true
				transform(mon)
				events.Remove("SummonMonster", 1)
			end
		end
		
		-- summon monster
		local mon = SummonMonster(class * 3 - 2 + power, x, y, z, true) -- true means monster has treasure
		if Merge and transform and not doneMerge then
			error("Couldn't apply transform to monster")
		elseif not Merge and transform then
			transform(mon)
		end
		-- set group
		mon.Group = t.group or 255
		
		-- insert into table to return later
		table.insert(summoned, mon)
	end
	return summoned
end

function pseudoSpawnpointItem(item, x, y, z, count, radius, level, typ)
	local t = {}
	if type(item) == "table" then
		t = item -- user passed table with arguments instead of item
	else
		t.item = item
		t.x, t.y, t.z = x, y, z
		t.count = count
		t.radius = radius
		t.level = level
		t.typ = typ
	end
	t.count = t.count or 1
	t.radius = t.radius or 64
	assert((t.item or t.level) and t.x and t.y and t.z)
	
	local toCreate = random(getMinMaxCount(t.count))
	
	local items, objects = {}, {}
	for i = 1, toCreate do
		local x, y, z
		local spawnAttempts = 0
		while true do
			local angle = random() * math.pi * 2
			local xadd = math.cos(angle) * random(1, t.radius)
			local yadd = math.sin(angle) * random(1, t.radius)
			
			x, y = t.x + xadd, t.y + yadd
			z = Map.IsOutdoor() and Map.GetGroundLevel(x, y) or t.z
			if Map.IsOutdoor() or Map.RoomFromPoint(x, y, z) > 0 then
				break
			end
			spawnAttempts = spawnAttempts + 1
			if spawnAttempts >= 10 then
				error("Couldn't spawn item: " .. dump(t), 2)
			end
		end
		SummonItem(t.item or 1, x, y, z, nil)
		local obj = Map.Objects[Map.Objects.High]
		local item = obj.Item
		table.insert(objects, obj)
		table.insert(items, item)
		if t.level then
			item:Randomize(t.level, t.typ or const.ItemType.Any)
			obj.Type, obj.TypeIndex = Game.ItemsTxt[item.Number].SpriteIndex, Game.ItemsTxt[item.Number].SpriteIndex
		end
	end
	return items, objects
end

function psp()
  print(string.format("x = %d, y = %d, z = %d", XYZ(Party)))
  print(string.format("x = %d, y = %d", Party.X, Party.Y))
end

if not table.join then
	function table.join(t1, t2)
		local n = #t1
		for i = 1, #t2 do
			t1[n + i] = t2[i]
		end
		return t1
	end
end

function joinTables(...)
	local n = select("#", ...)
	if n == 0 then return {} end
	local t = (select(1, ...))
	for i = 2, n do
		t = table.join(t, (select(i, ...)))
	end
	return t
end

-- shared spawnpoints

-- contains only new() function
sharedSpawnpoint = {}
-- contains actual spawnpoints
sharedSpawnpoints = {}

local function monClass(Id)
	if not Id then return end
	return (Id + 2):div(3)
end

local validSettings = {"RandomSpawnpointOrder", "ExactSpawnMin", "ExactSpawnMax", "DivideAcrossAllSpawnpoints"}
local function validateSettings(settings)
	for k, v in pairs(settings) do
		if not table.find(validSettings, k) then
			error(string.format("Invalid spawnpoint setting %q", k), 3)
		end
	end
end

function sharedSpawnpoint.new(mapname, spawnpointId, monster, max, settings)
	-- thought about shared metatable and data inside spawnpoint itself, but I would probably lose excellent
	-- aquamarine colouring of upvalues which makes script easier to understand :(
	if not mapname or not spawnpointId then
		error("map name or spawnpoint id arguments not present")
	end

	-- handling duplicated spawnpoints when reloading global scripts can be done in multiple ways:
	-- 1. on leave map, leave game and load savegame (new event) clear spawnpoints - would clear those not in global/maps too
	-- 2. use events.InternalBeforeLoadMap for above - same disclaimer + it's internal event which might change
	-- 3. create script in global folder which is loaded first to clear all spawnpoints - same disclaimer as above
	-- 4. either of first two points and using debug.getinfo here, to find whether global/maps script is creating spawnpoint - potentially wouldn't work if global script calls function in general to create spawnpoint
	-- 5. when spawnpoint exists, just replace it. Disadvantage - might be slower, because spawnpoint would still trigger monsterKilled event.
	-- Can't simply return old one, because initialization code will run again and add spawnpoints etc., which would duplicate them. Could provide a function
	-- sharedSpawnpoint.getOrCreate(), but I'm not keen on that idea - dynamic changes to spawnpoint wouldn't be registered. Or function sharedSpawnpoint.isSpawnpointCreated(mapname, id)
	-- I chose fifth option

	local oldIndex = table.findIf(sharedSpawnpoints, function(sp) return sp.getId() == spawnpointId end)
	if oldIndex then
		if sharedSpawnpoints[oldIndex].getMap() ~= mapname then
			debug.Message(string.format("Warning: replaced spawnpoint %q with one for different map: old = %q, new = %q", spawnpointId, sharedSpawnpoints[oldIndex].getMap(), mapname))
		end
		table.remove(sharedSpawnpoints, oldIndex)
	end

	local MAX_SPAWNED_AT_ONCE = diffsel(4, 6, 8)
	local ret = {}
	local spawnpoints = {}
	local maxSpawnByClass = {}
	local spawned = {}
	settings = settings or {}
	validateSettings(settings)
	local transforms = {}
	local class = monClass(monster)
	if class and max then
		maxSpawnByClass[class] = max
	end

	function ret.getId()
		return spawnpointId
	end

	function ret.setSpawnSettings(s)
		settings = table.copy(s)
		validateSettings(settings)
	end

	function ret.saveSpawnedMonsters()
		if Map.Name ~= mapname then return end
		mapvars.SharedSpawnpointMonsters = mapvars.SharedSpawnpointMonsters or {}
		mapvars.SharedSpawnpointMonsters[spawnpointId] = {}
		for class, monArray in pairs(spawned) do
			local sp = tget(mapvars.SharedSpawnpointMonsters[spawnpointId], class)
			for _, mon in ipairs(monArray) do
				table.insert(sp, mon:GetIndex())
			end
		end
	end
	
	local function loadSpawnedMonsters()
		if Map.Name ~= mapname then return end
		spawned = {}
		mapvars.SharedSpawnpointMonsters = mapvars.SharedSpawnpointMonsters or {}
		local entry = mapvars.SharedSpawnpointMonsters[spawnpointId]
		if not entry then
			return
		end
		for class, mapMonIds in pairs(entry) do
			for _, mapMonId in ipairs(mapMonIds) do
				if mapMonId < Map.Monsters.count then
					local mon = Map.Monsters[mapMonId]
					table.insert(tget(spawned, class), mon)
				end
			end
		end
	end
	ret.loadSpawnedMonsters = loadSpawnedMonsters

	function ret.addSpawnpoint(data)
		if type(data) ~= "table" then error("Argument passed to sharedSpawnpoint.addSpawnpoint() isn't a table") end
		local class = monClass(data.monster)
		table.insert(tget(spawnpoints, class), data)
	end

	-- set maximum spawned count for passed monster's class
	function ret.setMax(mon, max)
		maxSpawnByClass[monClass(mon)] = max
	end

	-- default max spawned monsters count, used if setMax is not called
	function ret.setDefaultMax(max)
		MAX_SPAWNED_AT_ONCE = max
	end

	-- each monster class has similar maximum
	function ret.spawn()
		if Map.Name ~= mapname then
			error(string.format("Tried to spawn monsters while on different map. Destination map: %s, current map: %s", mapname, Map.Name), 2)
		end
		local count = 0
		table.foreach(spawned, function(mons)
			count = count + tlen(mons)
		end)
		if count == 0 then
			loadSpawnedMonsters()
			count = 0
			table.foreach(spawned, function(mons)
				count = count + tlen(mons)
			end)
			Log(Merge.Log.Warning, "SharedSpawnpoint[%q, %q]: Loading monsters inside spawn function, new count %d", mapname, spawnpointId, count)
		end
		local function spawnSingleClass(monsterSpawnpoints, class)
			if #monsterSpawnpoints == 0 then return end
			local randOrder = {}
			if settings.RandomSpawnpointOrder then
				while #randOrder < #monsterSpawnpoints do
					local i = math.random(1, #monsterSpawnpoints)
					if not table.find(randOrder, i) then
						table.insert(randOrder, i)
					end
				end
			else
				for i = 1, #monsterSpawnpoints do
					randOrder[i] = i
				end
			end
			local canSpawn = (maxSpawnByClass[class] or MAX_SPAWNED_AT_ONCE) - #(spawned[class] or {})
			if canSpawn == 0 then return end
			for _, index in ipairs(randOrder) do
				local spawnpoint = monsterSpawnpoints[index]
				local maxInOneSpawn = canSpawn
				local minInOneSpawn = 1
				-- there can spawn fewer monsters than ExactSpawnMin if there are not enough monsters to spawn fully
				if settings.ExactSpawnMin then
					local min = getMinMaxCount(spawnpoint.count)
					minInOneSpawn = math.min(min, canSpawn) -- no more than can spawn
				end
				if settings.ExactSpawnMax then
					local _, max = getMinMaxCount(spawnpoint.count)
					maxInOneSpawn = math.min(max, canSpawn) -- no more than can spawn
				end
				-- clamp?
				assert(minInOneSpawn <= maxInOneSpawn, string.format("Invalid range %q", dump(spawnpoint.count)))
				if settings.DivideAcrossAllSpawnpoints then
					-- no less that 1 and no less than min
					maxInOneSpawn = math.max(math.ceil(canSpawn / #monsterSpawnpoints), 1, minInOneSpawn)
				end
				local oldTransform = spawnpoint.transform
				local function newTransform(mon)
					if oldTransform then
						oldTransform(mon)
					end
					local f = transforms[class]
					if f then
						f(mon)
					end
				end
				spawnpoint.transform = newTransform
				local oldC = spawnpoint.count
				spawnpoint.count = minInOneSpawn == maxInOneSpawn and maxInOneSpawn or {minInOneSpawn, maxInOneSpawn}
				local mons = pseudoSpawnpoint(spawnpoint)
				spawnpoint.count, spawnpoint.transform = oldC, oldTransform
				for i, v in ipairs(mons) do
					local class = monClass(v.Id)
					table.insert(tget(spawned, class), mons[i])
				end
				canSpawn = canSpawn - #mons
				assert(canSpawn >= 0)
				if canSpawn == 0 then return end
			end
		end

		for class, spawnpointTable in pairs(spawnpoints) do
			spawnSingleClass(spawnpointTable, class)
		end
	end

	function ret.getSpawnedMonsters(monster)
		--if mapname ~= Map.Name then return end
		local class = monClass(monster)
		return class and spawned[class] or spawned
	end
	ret.getAllSpawnedMonsters = ret.getSpawnedMonsters

	function ret.tryRemoveSpawnedMonster(mon)
		if mapname ~= Map.Name then return end
		if mon then
			local class = monClass(mon.Id)
			local index = table.find(tget(spawned, class), mon)
			if index then
				table.remove(spawned[class], index)
			end
		else
			spawned = {}
		end
	end
	ret.removeAllSpawnedMonsters = ret.tryRemoveSpawnedMonster

	function ret.clearSpawnpoints(monster)
		local class = monClass(monster)
		if class then
			spawnpoints[class] = {}
		else
			spawnpoints = {}
		end
	end
	ret.clearAllSpawnpoints = ret.clearSpawnpoints

	function ret.getMap()
		return mapname
	end

	function ret.setTransform(mon, fn)
		transforms[monClass(mon)] = fn
	end

	function ret.clearSpawnedTable()
		spawned = {}
	end

	loadSpawnedMonsters() -- in case spawnpoint had monsters in mapvars, and was replaced after events.LoadMap, so loading wasn't done
	
	table.insert(sharedSpawnpoints, ret)
	return ret
end

-- what events get called on:
-- 1. leaving map: beforesavegame (autosave), then leave map
-- 2. saving game: beforesavegame

-- to test, write function writing out map monster indexes of spawned monsters, then call it multiple times (for example after saving,
-- leaving map, loading spawned monsters, visiting unrelated map in between)

function showIndexes()
	local content = {}
	for _, ss in pairs(sharedSpawnpoints) do
		local ind = {}
		for class, monTable in pairs(ss.getSpawnedMonsters()) do
			for i, mon in pairs(monTable) do
				ind[#ind + 1] = mon:GetIndex()
			end
		end
		table.sort(ind)
		table.insert(ind, 1, string.format("Spawnpoint %q", ss.getId()))
		content[#content + 1] = table.concat(ind, "\n")
	end
	debug.Message(table.concat(content, "\n\n\n"))
end

-- even before load map happens after global scripts are loaded, need to use leave map
-- LEAVE MAP IS NOT CALLED WHEN LOADING SAVEGAME WHEN PLAYING
--function events.LeaveMap()
--	sharedSpawnpoints = {}
--end

function events.BeforeSaveGame()
	for _, ss in ipairs(sharedSpawnpoints) do
		ss.saveSpawnedMonsters()
	end
end

function events.LoadMap()
	for _, ss in ipairs(sharedSpawnpoints) do
		ss.clearSpawnedTable()
		ss.loadSpawnedMonsters()
		--debug.Message(dump(ss.getSpawnedMonsters(), 2))
	end
end

function events.MonsterKilled(mon)
	for _, ss in ipairs(sharedSpawnpoints) do
		ss.tryRemoveSpawnedMonster(mon)
	end
end