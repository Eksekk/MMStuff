local data = {}
pgenF = pgenF or {}
mmvAssert(7) -- TODO: support other versions (and merge(base/revamp)/rev4/elemental mod)

local costLow, costMedium, costHigh = {-1, 500, 2500, 6000}, {-1, 1000, 4000, 8000}, {-1, 2000, 5000, 8000}
for codeName, skillId in pairs(const.Skills) do
	data[skillId] = {}
	data[skillId].name = Game.SkillNames[skillId]
	data[skillId].maxMasteryByClass = {}
	for className, classId in pairs(const.Class) do
		data[skillId].maxMasteryByClass[classId] = Game.Classes.Skills[classId][skillId]
	end
	if skillId <= 7 or skillId == const.Skills.Unarmed then
		data[skillId].category = "weapon"
	elseif skillId <= 11 or skillId == 30 then
		data[skillId].category = "armor"
	elseif skillId <= (Game.Version == 8 and 23 or 20) then
		data[skillId].category = "magic"
	else
		data[skillId].category = "misc"
	end
	-- 004B27FD contains code for computing skill learning cost
	if skillId < const.Skills.Blaster or skillId == const.Skills.Merchant or skillId == const.Skills.Dodging or skillId == const.Skills.Unarmed or skillId == const.Skills.Armsmaster then
		data[skillId].trainCost = costHigh
	elseif skillId >= const.Skills.Fire and skillId <= const.Skills.Dark or skillId >= const.Skills.Leather and skillId <= const.Skills.Chain then
		data[skillId].trainCost = costMedium
	elseif skillId == const.Skills.Blaster then
		data[skillId].trainCost = {-1, 0, 0, 0}
	else
		data[skillId].trainCost = costLow
	end
	data[skillId].id = skillId
end

local s = const.Skills
local t = {melee = "melee", ranged = "ranged", defensive = "defensive", magic = "magic", utility = "utility", dummy = "dummy"}
local special = {blaster = "blaster", shield = "shield", elemental = "elemental",
	self = "self", magicExclusive = "magicExclusive", meditation = "meditation", raceSkill = "raceSkill"}
	
-- BEGIN GAME SPECIFIC DATA

if pgenF.isTwoHanded then
	mem.hooks[pgenF.isTwoHanded] = nil
	mem.hookfree(pgenF.isTwoHanded) -- support reloading the module without memory leaks
end
pgenF.isTwoHanded = mem.luaproc(function(playerPtr, itemId)
	local is = false
	local i, pl = GetPlayer(playerPtr)
	local txt = Game.ItemsTxt[itemId]
	if txt.EquipStat == const.ItemType.Weapon2H - 1 then
		is = true
	elseif txt.Skill == const.Skills.Spear then
		local s, m = SplitSkill(pl.Skills[const.Skills.Spear])
		if m < const.Master then
			is = true
		end
	end
	return is
end, 0, 2) -- stdcall

if pgenF.isEquippableInOffhand then
	mem.hooks[pgenF.isEquippableInOffhand] = nil
	mem.hookfree(pgenF.isEquippableInOffhand)
end
pgenF.isEquippableInOffhand = mem.luaproc(function(playerPtr, itemId)
	local is = false
	local i, pl = GetPlayer(playerPtr)
	local txt = Game.ItemsTxt[itemId]
	local s, m = SplitSkill(pl.Skills[txt.Skill])
	if txt.Skill == const.Skills.Sword then
		is = m >= const.Master
	elseif txt.Skill == const.Skills.Dagger then
		is = m >= const.Expert
	end
	return is
end, 0, 2)
-- for k, v in sortpairs(table.invert(const.Skills)) do print(k, v) end

local pt = M.playerTypes
local manualSkillsData =
{
	-- could be affinities instead of absolutes for types, but for now keep it simple
	
	-- { {types}, special (or nil), {affinities} }
	[s.Staff] = { {t.melee, t.defensive}, nil, {[pt.caster] = 0.4, [pt.melee] = 0.4, [pt.ranged] = 0.4, [pt.defensive] = 0.5, [pt.utility] = 0.5, } },
	[s.Sword] = { {t.melee, t.defensive}, nil, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 0.7, [pt.defensive] = 0.7, [pt.utility] = 0.5, } },
	[s.Dagger] = { {t.melee}, nil, {[pt.caster] = 0.7, [pt.melee] = 0.4, [pt.ranged] = 0.6, [pt.defensive] = 0.3, [pt.utility] = 0.5, } },
	[s.Axe] = { {t.melee}, nil, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 1, [pt.defensive] = 0.4, [pt.utility] = 0.5, } },
	[s.Spear] = { {t.melee, t.defensive}, nil, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 1, [pt.defensive] = 0.7, [pt.utility] = 0.5, } },
	[s.Bow] = { {t.ranged}, nil, {[pt.caster] = 0.7, [pt.melee] = 0.7, [pt.ranged] = 1, [pt.defensive] = 0.7, [pt.utility] = 0.5, } },
	[s.Mace] = { {t.melee}, nil, {[pt.caster] = 0.3, [pt.melee] = 0.8, [pt.ranged] = 0.8, [pt.defensive] = 1, [pt.utility] = 0.5, } },
	[s.Blaster] = { {t.ranged}, special.blaster, {[pt.caster] = 0.4, [pt.melee] = 0.4, [pt.ranged] = 1, [pt.defensive] = 0.5, [pt.utility] = 0.5, } },
	[s.Shield] = { {t.defensive}, special.shield, {[pt.caster] = 0.2, [pt.melee] = 0.5, [pt.ranged] = 0.5, [pt.defensive] = 1, [pt.utility] = 0.5, } },
	[s.Leather] = { {t.defensive}, nil, {[pt.caster] = 0.8, [pt.melee] = 0.6, [pt.ranged] = 0.6, [pt.defensive] = 0.4, [pt.utility] = 0.7, } },
	[s.Chain] = { {t.defensive}, nil, {[pt.caster] = 0.4, [pt.melee] = 0.8, [pt.ranged] = 0.8, [pt.defensive] = 0.7, [pt.utility] = 0.5, } },
	[s.Plate] = { {t.defensive}, nil, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 0.3, [pt.defensive] = 1, [pt.utility] = 0.3, } },
	[s.Fire] = { {t.magic, t.ranged}, special.elemental, {[pt.caster] = 1, [pt.melee] = 0.2, [pt.ranged] = 1, [pt.defensive] = 0.6, [pt.utility] = 0.5, } },
	[s.Air] = { {t.magic, t.ranged}, special.elemental, {[pt.caster] = 1, [pt.melee] = 0.1, [pt.ranged] = 1, [pt.defensive] = 0.6, [pt.utility] = 0.8, } },
	[s.Water] = { {t.magic, t.ranged}, special.elemental, {[pt.caster] = 1, [pt.melee] = 0.1, [pt.ranged] = 1, [pt.defensive] = 0.4, [pt.utility] = 1, } },
	[s.Earth] = { {t.magic, t.ranged}, special.elemental, {[pt.caster] = 1, [pt.melee] = 0.4, [pt.ranged] = 1, [pt.defensive] = 1, [pt.utility] = 0.5, } },
	[s.Spirit] = { {t.magic}, special.self, {[pt.caster] = 1, [pt.melee] = 0.6, [pt.ranged] = 0.6, [pt.defensive] = 0.7, [pt.utility] = 0.5, } },
	[s.Mind] = { {t.magic, t.ranged}, special.self, {[pt.caster] = 1, [pt.melee] = 0.3, [pt.ranged] = 1, [pt.defensive] = 0.6, [pt.utility] = 0.5, } },
	[s.Body] = { {t.magic, t.ranged}, special.self, {[pt.caster] = 1, [pt.melee] = 0.8, [pt.ranged] = 1, [pt.defensive] = 1, [pt.utility] = 0.5, } },
	[s.Light] = { {t.magic}, special.magicExclusive, {[pt.caster] = 1, [pt.melee] = 0.4, [pt.ranged] = 1, [pt.defensive] = 0.8, [pt.utility] = 0.5, } },
	[s.Dark] = { {t.magic, t.ranged}, special.magicExclusive, {[pt.caster] = 1, [pt.melee] = 0.1, [pt.ranged] = 1, [pt.defensive] = 0.2, [pt.utility] = 0.5, } },
	[s.IdentifyItem] = { {t.utility}, nil, {[pt.caster] = 0.8, [pt.melee] = 1, [pt.ranged] = 1, [pt.defensive] = 1, [pt.utility] = 1, } },
	[s.Merchant] = { {t.utility}, nil, {[pt.caster] = 1, [pt.melee] = 1, [pt.ranged] = 1, [pt.defensive] = 1, [pt.utility] = 1, } },
	[s.Repair] = { {t.utility}, nil, {[pt.caster] = 1, [pt.melee] = 1, [pt.ranged] = 1, [pt.defensive] = 1, [pt.utility] = 1, } },
	[s.Bodybuilding] = { {t.defensive}, nil, {[pt.caster] = 0.1, [pt.melee] = 0.7, [pt.ranged] = 0.5, [pt.defensive] = 1, [pt.utility] = 0.5, } },
	[s.Meditation] = { {t.utility, t.magic}, special.meditation, {[pt.caster] = 1, [pt.melee] = 0.1, [pt.ranged] = 0.5, [pt.defensive] = 0.4, [pt.utility] = 0.5, } },
	[s.Perception] = { {t.utility}, nil, {[pt.caster] = 0.3, [pt.melee] = 0.3, [pt.ranged] = 0.6, [pt.defensive] = 0.3, [pt.utility] = 1, } },
	[s.Diplomacy] = { {} }, -- skip useless skill
	[s.Thievery] = { {} }, -- skip useless skill
	[s.DisarmTraps] = { {t.utility}, nil, {[pt.caster] = 0.2, [pt.melee] = 0.5, [pt.ranged] = 0.6, [pt.defensive] = 0.3, [pt.utility] = 1, } },
	[s.Dodging] = { {t.defensive}, nil, {[pt.caster] = 0.3, [pt.melee] = 0.8, [pt.ranged] = 0.8, [pt.defensive] = 1, [pt.utility] = 0.5, } },
	[s.Unarmed] = { {t.melee}, nil, {[pt.caster] = 0.5, [pt.melee] = 0.8, [pt.ranged] = 0.3, [pt.defensive] = 0.3, [pt.utility] = 0.5, } },
	[s.IdentifyMonster] = { {t.utility}, nil, {[pt.caster] = 0.8, [pt.melee] = 0.3, [pt.ranged] = 0.7, [pt.defensive] = 0.6, [pt.utility] = 1, } },
	[s.Armsmaster] = { {t.melee}, nil, {[pt.caster] = 0.1, [pt.melee] = 1, [pt.ranged] = 0.6, [pt.defensive] = 0.8, [pt.utility] = 0.5, } },
	[s.Stealing] = { {t.utility}, nil, {[pt.caster] = 0.1, [pt.melee] = 0.1, [pt.ranged] = 0.1, [pt.defensive] = 0.1, [pt.utility] = 1, } },
	[s.Alchemy] = { {t.utility}, nil, {[pt.caster] = 1, [pt.melee] = 0.6, [pt.ranged] = 0.4, [pt.defensive] = 0.6, [pt.utility] = 1, } },
	[s.Learning] = { {t.utility}, nil, {[pt.caster] = 0.7, [pt.melee] = 0.7, [pt.ranged] = 0.7, [pt.defensive] = 0.7, [pt.utility] = 1, } },
}

-- END GAME SPECIFIC DATA

for id, manualData in pairs(manualSkillsData) do
	local s = data[id]
	if #manualData[1] == 0 then -- no types
		s.doNotGenerate = true
		s.types = {}
		s.affinityByPlayerType = {}
	else
		s.types = manualData[1]
		s.special = manualData[2]
		s.affinityByPlayerType = manualData[3]
	end
end

-- satisfy json encoder
for i = #data, 0, -1 do
	local s = data[i]
	for j = #s.maxMasteryByClass, 0, -1 do
		s.maxMasteryByClass[j + 1] = s.maxMasteryByClass[j]
	end
	s.maxMasteryByClass[0] = nil
	data[i + 1] = data[i]
end
data[0] = nil

pgen = pgen or {}
pgen.vanillaSkillData = data
-- DERIVATIVE MODS (elemental, rev4 etc.) MODIFY VANILLA DATA FROM ABOVE - MINIMIZED DUPLICATION

return data