-- receives three arguments and returns the one for current engine version, starting from 6
-- so mmv(5, "a", false) will return 5 in MM6, "a" in MM7, and false in MM8
local function mmv(...)
    local r = select(Game.Version - 5, ...)
    assert(r ~= nil)
    return r
end
do return end
local bossNameId = 2 -- add your id here
local bossName = "MyMonsterName" -- if using mm6, add your name here
-- Hejaz Mawsil (cobra egg guy), Donna Wyrith (first house on the right right at the start), Brekish Onefang (lizard in clan leader's hall in DWI)
local npc = mmv(288, 14, 1) -- add your npc here
-- warning: if you don't change npc, in Merge only MM8 version will work correctly
-- starting map in each case
local bossMapFile = mmv("oute3.odm", "out01.odm", "out01.odm") -- add your map name here (can entirely replace mmv call)

-- call this to summon required monster at party position
-- note: in MM8 you should wait for up to 6 seconds for quest to take newly summoned monster into consideration and update its state, otherwise you'll be able to complete it right away (only if you summon monster dynamically, placing through editor should be good)
function summonTestMonster()
    local mon = SummonMonster(math.random(1, 50), XYZ(Party))
    if Game.Version == 6 then
        mon.Name = bossName
    else
        mon.NameId = bossNameId
    end
    
    -- increase resistances
    -- indexes correspond to const.Damage
    local res = {[0] = 20, 0, 5, 10, 10} -- that "[0] = <value>" thing makes table start from index "0", rather than default "1"
    for resId, add in ipairs(res) do
        mon.Resistances[resId] = mon.Resistances[resId] + add
    end
    -- more damage
    mon.Attack1.DamageAdd = mon.Attack1.DamageAdd + 100
    mon.Attack2.DamageDiceCount = mon.Attack2.DamageDiceCount * 5

    mon.ArmorClass = 50

    -- give spell
    -- "a, b, c = d, e, f" is equivalent to "a = d, b = e, c = f" in C-like languages
    mon.Spell, mon.SpellSkill, mon.SpellChance = const.Spells.PoisonSpray, JoinSkill(10, const.Master), 50
end

-- to kill the monster, either download "god" script from MMExtension github repository and use it, or point at monster and execute in console "Map.Monsters[Mouse:GetTarget().Index].HP = 0"

-- adding monster name and map into npc message dynamically is not required, I do it to show some concepts
local function getNameAndMap()
    local mapName
    for i, entry in Game.MapStats do
        if entry.FileName:lower() == bossMapFile:lower() then
            mapName = entry.Name
            break
        end
    end
    if Game.Version == 6 then
        return bossName, mapName
    else
        return Game.PlaceMonTxt[bossNameId], mapName
    end
end

local texts = {
    Topic = "Kill the monster",
    TopicDone = "Thanks!",
    Give = string.format("Hey, can you help me? I need you to kill so-called %q on the %q map.", getNameAndMap()),
    Undone = "You didn't do it yet?",
    Done = "Well done, here is your reward.",
    Greet = "Thanks for visiting.",
    After = "Good that you killed the monster.",

    Quest = "Kill the monster.",
    Award = "Killed the monster",
}

local function callbackDone()
    -- for fun: boost stats and resistances of every player
    for i, pl in Party do
        for stat = const.Stats.Might, const.Stats.Luck do
            pl.Stats[stat].Base = pl.Stats[stat].Base + 50
        end
        if Game.Version > 6 then
            for resId in pl.Resistances do
                pl.Resistances[resId].Base = pl.Resistances[resId].Base + 30
            end
        else -- mm6 has resistances as "union" instead of "array", which means you can't use above for loop syntax (need to manually provide indexes)
            local cd = const.Damage
            local resistances = {cd.Fire, cd.Elec, cd.Poison, cd.Cold, cd.Magic}
            for _, resId in ipairs(resistances) do
                pl.Resistances[resId].Base = pl.Resistances[resId].Base + 30
            end
        end
    end
end

if Game.Version == 8 then
    -- here we can use KillMonstersQuest{} as a shortcut
    KillMonstersQuest {
        "killBossExample",
        {Map = bossMapFile, NameId = bossNameId}, -- the completion requirement is killing monster with this name id on this map
        NPC = npc,
        Slot = 0,
        Exp = 30000,
        Gold = 5000,
        Done = callbackDone, -- will be run on quest complete
        Texts = texts
    }
    -- this line would check if required monster **on current map** is killed
    -- evt.CheckMonstersKilled{}
else
    -- in MM6/MM7 need to manually code condition checking

    -- function which will check if monster is killed and set vars.exampleBossKilled to true if so
    local function checkKilled()
        -- check map
        if Map.Name ~= bossMapFile:lower() then
            return -- wrong map, don't run other code
        end

        -- if all monsters with specific NameId are killed or don't exist, quest will be completed
        for i, mon in Map.Monsters do
            if (Game.Version == 6 and mon.Name == bossName) or (Game.Version == 7 and mon.NameId == bossNameId) then -- exact condition depends on the game
                -- correct monster, now check if it's killed
                if mon.HP > 0 and mon.Ally ~= 9999 then -- mon.Ally is 9999 in MM7+ if monster is reanimated by party
                    return -- found required monster alive and not reanimated, exit
                end
            end
        end
        vars.exampleBossKilled = true -- set quest completion variable
    end

    Quest {
        "killBossExample",
        NPC = npc,
        Slot = 0,
        Exp = 30000,
        Gold = 5000,
        CheckDone = function(quest)
            checkKilled() -- check condition on quest topic click
            return vars.exampleBossKilled
        end,
        Done = callbackDone,
        Texts = texts
    }

    events.LeaveMap = checkKilled -- also check condition on map leave, if monster is on map other than the one with quest giver
end