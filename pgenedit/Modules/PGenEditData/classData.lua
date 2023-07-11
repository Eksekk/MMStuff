local data = {}
mmvAssert(7) -- TODO: support other versions (+ merge(base/revamp)/rev4/elemental mod)

-- for k, v in sortpairs(table.invert(const.Class)) do print(k, v) end

local c = const.Class
local cInv = table.invert(c)
for i = 0, #cInv - 1, 4 do
	for j = 0, 3 do
		local id = i + j
		data[id] = data[id] or {}
		data[id].masteries = M.deepcopyMM(Game.Classes.Skills[id])
		data[id].id = i + j
		data[id].name = Game.ClassNames[id]
	end
	data[i].tier = 0
	data[i + 1].tier = 1
	data[i + 2].tier = 2
	data[i + 3].tier = 2
	
	data[i + 2].alignment = "light" -- don't specify previous alignments, because neutral is default
	data[i + 3].alignment = "dark"
	
	data[i].promotionClasses = {i + 1} -- only direct (at most one level above)
	data[i + 1].promotionClasses = {i + 2, i + 3}
	
	data[i + 1].baseClass = i
	data[i + 2].baseClass = i + 1
	data[i + 3].baseClass = i + 1
end

--[[ player types:
PLAYER_GENERIC = 0,
PLAYER_CASTER,
PLAYER_MELEE,
PLAYER_RANGED,
PLAYER_DEFENSIVE,
PLAYER_UTILITY,
]]

local function aff4(id, aff)
	for i = 0, 3 do
		data[id + i].playerTypeAffinity = table.copy(aff)
	end
end

local pt = M.playerTypes

-- M.dll.setClassData(json.encode(M.C()))

-- let's accept minimum affinity of 0.1, to still allow caster-focused party to sometimes have knights, for example for tanking
aff4(c.Knight, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 0.3, [pt.defensive] = 1, [pt.utility] = 0.5})
aff4(c.Thief, {[pt.caster] = 0.1, [pt.melee] = 0.8, [pt.ranged] = 0.3, [pt.defensive] = 0.5, [pt.utility] = 1})
aff4(c.Monk, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 0.3, [pt.defensive] = 0.8, [pt.utility] = 0.5})
aff4(c.Paladin, {[pt.caster] = 0.7, [pt.melee] = 0.8, [pt.ranged] = 0.5, [pt.defensive] = 1, [pt.utility] = 0.5})
aff4(c.Archer, {[pt.caster] = 0.7, [pt.melee] = 0.8, [pt.ranged] = 1, [pt.defensive] = 0.7, [pt.utility] = 0.7})
aff4(c.Ranger, {[pt.caster] = 0.3, [pt.melee] = 0.7, [pt.ranged] = 0.8, [pt.defensive] = 0.5, [pt.utility] = 1})
aff4(c.Cleric, {[pt.caster] = 1, [pt.melee] = 0.3, [pt.ranged] = 0.6, [pt.defensive] = 0.4, [pt.utility] = 0.8})
aff4(c.Druid, {[pt.caster] = 1, [pt.melee] = 0.3, [pt.ranged] = 0.8, [pt.defensive] = 0.3, [pt.utility] = 0.8})
aff4(c.Sorcerer, {[pt.caster] = 1, [pt.melee] = 0.3, [pt.ranged] = 1, [pt.defensive] = 0.1, [pt.utility] = 0.8}) -- def 0.1 because theoretically has invis/shield/stone skin

-- names

--[[
int id;
std::string name;
int tier; // 0-2
PlayerClass* baseClass; // goes towards lower tier, i.e. the class you start with
Alignment alignment; // light, dark, neutral
std::vector<PlayerClass*> promotionClasses; // higher tier
std::unordered_map<int, Mastery> maximumSkillMasteries;
double playerTypeAffinity[PLAYER_TYPE_COUNT]; // how appropriate is this class for given player type
int classWindowId;
]]

-- satisfy json encoder
for i = #data, 0, -1 do
	for j = #data[i].masteries, 0, -1 do
		data[i].masteries[j + 1] = data[i].masteries[j]
	end
	data[i].masteries[0] = nil
	data[i + 1] = data[i]
end
data[0] = nil

-- postprocess (assuming c++ json reader starts array at 0, not 1):
-- data[] index in lua = data[] index in c++
-- data[].masteries[] index in lua = data[].masteries index in c++

pgen = pgen or {}
pgen.vanillaClassData = data
-- DERIVATIVE MODS (elemental, rev4 etc.) MODIFY VANILLA DATA FROM ABOVE - MINIMIZED DUPLICATION

return data