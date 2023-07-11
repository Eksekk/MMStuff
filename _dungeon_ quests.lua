

-- main quest
--[[
Quest {
    
    Texts = {
        Topic = ""
    },
}
]]

-- rescue prisoner?
-- Thivthys - god name

do return end

local enrothianWineNpc = 111 -- todo

NPCTopic {
    "Wine",
    "There is nothing else that tastes like a bottle of old enrothian wine! All other drinks pale in comparison. Even other beverage types."
}

Quest {
    NPC = enrothianWineNpc,
    Gold = 20000,
    Exp = 40000,
    Texts = {
        Topic = "Quest",
        Give = [[You see, it's of no surprise I'm wine connoisseur. I've drunk basically all of them. Tularean spirits, Evenmorn]]
    }
}

local insaneMageNpcId = 555 -- todo
local mageQuestNpcId = 222 -- todo
local gemOfHeavensId = 782

-- NOTE: add new village somewhere (5-6 houses)
Quest {
    Name = "MalignantTempleMageAssassination",
    NPC = mageQuestNpcId,
    QuestItem = gemOfHeavensId,
    Gold = 20000,
    Exp = 40000,
    Texts = {
        Topic = "Quest",
        TopicDone = "You have our gratitude!",
        Give = [[So have you heard recent news? They aren't very optimistic. Our village is getting robbed regularly, and recently was completely ransacked,
        to the point we had to rebuild our houses! That's why they look so hurried.
        
        Want to know who causes this? It's so called "Grand Wizard Sortileges". I'd like to not say "grand", but he placed a compulsion spell on us forcing to title him this horrid way.
        
        We have already hired some heroes to deal with him, but not only were they unexperienced, the wizard also barricaded himself in temple in Barrow Downs and surrounded with "friends".
        The daredevils are probably long since dead.
        
        Can you do it? You'll forever have our favor. Please help us!
            
        Oh, also make sure to equip all magic-resistance increasing artifacts you can find. You'll need them.]],
        Undone = [[Why are you delaying? The attacks don't stop, we are afraid he will go extra mile and we'll be all dead!]],
        Done = "So it's real. We are no longer in any danger. We no longer need to live every day afraid for the next. Extremely well done!",
        After = "Thank you again, demigods! You saved our lives. If you need anything, you're always welcome here."
    }
}

local exquisiteGarmentsIds = {helm = 562, amulet = 563, armor = 561}

local exquisiteGarmentsNpc = 555 -- todo


Quest {
    Name = "MalignantTempleHolyItemSet",
    NPC = exquisiteGarmentsNpc,
    Exp = 20000,
    Gold = 10000,
    CheckDone = function()
        for k, v in pairs(exquisiteGarmentsIds) do
            if not evt.All.Cmp("Inventory", v) then
                return false
            end
        end
        return true
    end,
    Done = function()
        vars.exquisiteSetReturnTime = Game.Time
    end,
    Texts = {
        Topic = "Quest",
        TopicDone = "Good job!",
        Give = [[The 'priests' of temple of Thivthys in Barrow Downs have preached that they have the garments giving nearly godlike powers, blessed by Thivthys herself.
        While that certainly is a stretch, there may be some truth here. It's also of no surprise that a lot of us would like to see that temple fall. It would be a big favor for the whole world.
        
        So, joining these two together, the best course of action would be to... 'borrow' the equipment. I'm sure you'll agree with me.
        
        Can you do it? We don't need nor want anything that has a connection to that damned temple. But I bet most of heroes need good gear. Yes, I know YOU in particular don't need it,
        but nonetheless it may prove useful once you encounter a big enough challenge.]],
        Undone = "You don't have all the items yet? That's alright, take your time. Their temple is certainly very secure, as much as we don't want to admit it.",
        Done = [[EXCELLENT JOB! Now they don't have one of their main sources of power, and I'm sure their 'resistance' made you to do a bit more destruction than strictly required. Double win for us, and for you probably too.
        
        Oh, you may also want to visit me in the future. I believe I have the required knowledge to extract some of magic of this equipment to serve the rest of your party. We shall see.
        ]],
        After = "So has this equipment proven useful already? Or did the 'priests' lie, as they always do?",
    }
}

NPCTopic {
    NPC = exquisiteGarmentsNpc,
    "It's done",
    [[Ah, you have returned. Very well, I not that long ago completed my research. There indeed is possibility to extract some magic to empower you. And best of all, your items won't be hurt by the spell at all.

    [You give items to the old lady. She reads long and impossible to remember sequence from the scroll. As she reads, the items begin to glow more with each word.
    Finally, in a bright flash of light, the scroll disappears, items revert to their old appearance, and you feel something has changed. You suddenly have much more energy]
        
    So here is your promised reward. Hope it will prove useful for you.
    ]],
    CanShow = function()
        return not vars.timedSetRewardTaken and vars.exquisiteSetReturnTime and Game.Time - vars.exquisiteSetReturnTime >= const.Week
    end,
    Done = function()
        vars.timedSetRewardTaken = true
        evt.All.Add("SkillPoints", 20)
    end
}

local function getItemSetWearState(pl)
    local function findItem(id)
        for i, item in pl.Items do
            if item.Number == id then
                return true
            end
        end
        return false
    end
    local ret = 
    {
        helm = findItem(exquisiteGarmentsIds.helm),
        armor = findItem(exquisiteGarmentsIds.armor),
        amulet = findItem(exquisiteGarmentsIds.amulet),
    }
    local count = 0
    for name, worn in pairs(ret) do
        if worn then
            count = count + 1
        end
    end
    ret.count = count
    return ret
end

--[[
[1/3 +50 HP and SP, +1 all magic skills; 2/3 +100 armor class; 3/3 reduces all damage received by 25%] Part of fabled equipment blessed by Thivthys herself. Made of very strong material and imbued with magic, this armor is one of the best of its kind. Nothing protects better against damage.

[1/3 +15 all resistances; 2/3 +2 to all misc skills; 3/3 +40 all stats] Part of fabled equipment blessed by Thivthys herself. This helmet looks insignificant, however, in reality it is one of most powerful equipment on Antagarich. Wearer's natural proficiencies are greatly increased.

[1/3 each weapon hit causes 3 fire, air, water and earth damage; 2/3 provides 5 HP and 10 MP regeneration; 3/3 all magic damage caused increased by 15%] Part of fabled equipment blessed by Thivthys herself. This amulet channels magic better than any other accessory available. Periodically refills wearer's life force and empowers his attacks.
--]]

function events.CalcStatBonusByItems(t)
    local set = getItemSetWearState(t.Player)
    if set.armor then
        if t.Stat == const.Stats.HP or t.Stat == const.Stats.SP then
            t.Result = t.Result + 50
        elseif t.Stat >= const.Stats.Fire and t.Stat <= const.Stats.Dark then
            t.Result = t.Result + 1
        elseif t.Stat == const.Stats.ArmorClass and set.count >= 2 then
            t.Result = t.Result + 100
        end
        -- remaining: damage
    end
    if set.helm then
        if t.Stat >= const.Stats.FireRes and t.Stat <= const.Stats.BodyRes then
            t.Result = t.Result + 15
        elseif t.Stat >= const.Stats.Might and t.Stat <= const.Stats.Luck and set.count >= 3 then
            t.Result = t.Result + 40
        end
    end
end

function events.GetSkill(t)
    local set = getItemSetWearState(t.Player)
    if set.helm and set.count >= 2 and t.Skill >= const.Skills.IdentifyItem then -- TODO: check
        local s, m = SplitSkill(t.Result)
        t.Result = JoinSkill(s + 2, m)
    end
end

function events.CalcDamageToMonster(t)

end

function events.CalcDamageToPlayer(t)
    local set = getItemSetWearState(t.Player)
    if set.armor and set.count >= 3 then
        t.Result = math.ceil(t.Result * 0.75)
    end
end

function events.Regeneration(t)
    local set = getItemSetWearState(t.Player)
    if set.amulet and set.count >= 2 then
        t.HP = t.HP + 5
        t.MP = t.MP + 10
    end
end

function events.CalcSpellDamage(t)
    local data = WhoHitMonster()
    if data.Player then
        local set = getItemSetWearState(data.Player)
        if set.amulet and set.count >= 3 then
            t.Result = math.floor(t.Result * 1.15)
        end
    end
end

-- find items scattered across the world

-- item272 - urn of thivthys

local urnOfThivthysId = 781
local urnOfThivthysNpc = 324 -- todo

Quest {
    Name = "CollectUrnsOfThivthys",
    NPC = urnOfThivthysNpc,
    CheckDone = function()
        local count = 0
        for _, pl in Party do
            for i, item in pl.Items do
                if item.Number == urnOfThivthysId then
                    count = count + 1
                end
            end
        end
        return count >= 4
    end,
    Done = function()
        while evt.All.Cmp("Inventory", urnOfThivthysId) do
            evt.Sub("Inventory", urnOfThivthysId)
        end
    end,
    Texts = {
        Topic = "Quest",
        TopicDone = "DeUrninated",
        Give = [[You have certainly heard the rumors - there are artifacts of immense power scattered across Antagarich, given by goddess Thivthys to her followers. \
        Of course, they had them 'borrowed' by certain heroes to weaken Temple of Thivthys's influence on the world. They were of course searched for, but no one found all of them. \
        If you give me full set, I will make sure that followers of evil don't see them ever again.
        
        And of course, you'll be greatly rewarded. The artifacts' power will be used to empower those who actually need it.]],
        Undone = "Did you have troubles finding them all? I assure you, they are definitely there, such artifact cannot be simply destroyed.",
        Done = "So it happened. I didn't think this was possible, finding the full set. Congratulations. And here is the promised reward. Excellent job.",
        After = "I will always be in awe. You're done what I didn't think was possible. Hope my 'gift' serves you well. You're always welcome here.",
    }
}

-- QUESTLINE