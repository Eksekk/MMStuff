if offsets.MMVersion == 6 then return end -- MM6 has no GetSkill event
-- to see class strings, execute in console "dump(const.Class)", likewise for skills

-- bonus list
-- table nesting details: classId or table with class ids, then skill id or table with skillIds, then table with fields, a number to apply fixed bonus or a CalcBonusFunc function
-- possible fields of last table:
--    Bonus = plain skill bonus
--    Condition(pl, skill, level, mastery) = function that determines whether bonus will be applied. Receives as arguments player affected, skill level, skill mastery, and skill id (to facilitate generic bonus calculation functions). If this returns false, bonus won't be added. If it's absent, it will always be applied
--    CalcBonusFunc(pl, skill, level, mastery) = function that returns calculated bonus based on its parameters. Overrides "Bonus" field, unless it returns nil or false.
local classBonuses
local raceBonuses

function events.GameInitialized1() -- defer to allow Merge scripts to run and set const.Race and change const.Class

    -- convenient aliases to access some consts
    local cc, cs, cr = const.Class, const.Skills, const.Race

    ----- RACE BONUSES -----
    raceBonuses = {
        [cr.Elf] = {
            [{cs.Air, cs.Water}] = function(pl, skill, level, mastery)
            return 5
        end,
        }
    }

    ----- CLASS BONUSES -----
    classBonuses = {
        --[[
        [cc.Knight] = {
            [cs.Armsmaster] = {
                Bonus = 3,
                Condition = function(pl, level, mastery, skill) -- if this returns false, no bonus will be applied
                    return pl.Stats[const.Stats.Might].Base >= 20
                end,
            },
            [cs.Fire] = {
                -- calculates bonus
                CalcBonusFunc = function(pl, level, mastery, skill)
                    -- example: increase skill by 3 only if it's at least 8M
                    if level >= 8 and mastery >= const.Master then
                        return 3
                    end
                    -- returns nil (no bonus) automatically
                end
            },
        },
        -- can be table to apply to multiple classes
        [{cc.MasterArcher, cc.Spy}] = {
            [cs.Bow] = {
                Bonus = 10,
            },
            -- this can also be a table to apply to multiple skills
            [{cs.Fire, cs.Air, cs.Water, cs.Earth}] = {
                Bonus = 2,
            },
        },
        [{cc.Sorcerer, cc.Cleric}] = {
            [{cs.Fire, cs.Air, cs.Water, cs.Earth, cs.Body, cs.Spirit, cs.Mind}] = {
                Bonus = 1,
            },
            [cs.Alchemy] = 4, -- can be simply a number as a shortcut, to always apply fixed bonus
            [cs.Blaster] = 2,
        },
        [cc.Ranger] = {
            [cs.Armsmaster] = 2,
            [cs.Axe] = function(pl, level, mastery, skill) -- can also be a function to always apply variable bonus
                return level:div(2) -- like "of X magic" rings
            end,
        },
        ]]
    }
end

-- this event is launched each time game requires any player any skill value
-- reference link: https://grayface.github.io/mm/ext/ref/#events.GetSkill
function events.GetSkill(t)
    local pl = t.Player
    local targetClassId = pl.Class
    local bonus = 0
    local targetSkillId = t.Skill
    local s, m = SplitSkill(t.Result)
    
    -- local function to apply bonuses, works both for class and race bonuses
    local function applyBonus(id, targetId, bonusesEntry)
        -- "and" binds stronger than "or"
        -- "a and b or c and d" is parsed as "(a and b) or (c and d)"
        -- if you are not sure, you can use parentheses
        if type(id) == "number" and id == targetId or type(id) == "table" and table.find(id, targetId) then
            -- correct class from now on
            for skillId, skillEntry in pairs(bonusesEntry) do -- iterate over skill bonuses for certain class[es]
                if type(skillId) == "number" and skillId == targetSkillId or type(skillId) == "table" and table.find(skillId, targetSkillId) then
                    -- correct skill from now on
                    if type(skillEntry) == "number" then
                        bonus = bonus + skillEntry
                    elseif type(skillEntry) == "function" then
                        bonus = bonus + skillEntry(pl, s, m, targetSkillId)
                    elseif not skillEntry.Condition or skillEntry.Condition(pl, s, m, targetSkillId) then -- check condition
                        bonus = bonus + (skillEntry.CalcBonusFunc and skillEntry.CalcBonusFunc(pl, s, m, targetSkillId) or skillEntry.Bonus or 0) -- add bonus
                        -- "a and b or c" means that if "a" is true (anything other than nil or false), expression will return "b", otherwise it will return "c"
                        -- warning: if "b" is nil or false, this will always return "c"!
                    end
                end
            end
        end
    end
    for classId, bonusesEntry in pairs(classBonuses) do -- iterate over bonuses table to add those that should be added
        applyBonus(classId, targetClassId, bonusesEntry)
    end
    local ver = offsets.MMVersion
    if ver == 7 or ver == 8 and Merge then
        local targetRaceId
        if ver == 7 then
            targetRaceId = pl:GetRace()
        elseif Merge then
            targetRaceId = GetRace(pl, pl:GetSlot())
        end

        for raceId, bonusesEntry in pairs(raceBonuses) do
            applyBonus(raceId, targetRaceId, bonusesEntry)
        end
    end
    t.Result = JoinSkill(s + bonus, m)
end