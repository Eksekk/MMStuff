--[[
The texts part is fine, and I don't want to paste it on purpose, don't want to shoot the punchline. :) It does it in this form, it gives you the mission and apparently everything is ok, but it doesn't check if I killed the 1 monster standing in front of the test house with ID 190. If I don't kill it, it just accepts the quest even so.
]]
Quest {
    "KillWolfQuest",
    NPC = 14, -- mia lucille
    Slot = 2,
    Experience = 75000,
    Gold = 13000,
    Quest = true,
    CheckDone = function()
        return evt.CheckMonstersKilled {CheckType = 2, Id = 190 - 1, Count = 0}					-- all monsters of id 190 on current map must be killed to show topic
        -- WARNING: this function takes monster type - 1 as argument to work properly
    end,
	CanShow = function()
        return true -- CONDITION moved to checkDone to make quest show always, but not complete until condition is satisfied
        -- you can undo that, but I recommend to add "NeverGiven = true" in such case, because it'd be strange for quest to be given ONLY after completing it ;)
	end,
  Texts = {Topic = "kill wolf", Done = "done", Undone = "Undone", Give = "Give"}
}
--[[
The aim would be to imitate an inn. The food purchase works fine, but I can't configure it not to give more than a maximum amount of food (e.g. max 20 food, and then say something else.. your pack is full or something). So like it's really an inn. And it would also be nice to get it to not give out 'Quest done' sound effect when buying, which I think is what /evt.Add("Food", 10)/ is associated with, because if I just use RewardItem, it just plays the money spending sound eff. Now, that's what I'd like to achieve.
]]
-- this topic will be shown when player actually can buy the food
Quest {
    "Innkeeper",
    NPC = 14,
    Slot = 0,
    NeverGiven = true,		-- skip "Given" state, perform Done/Undone check immediately
	NeverDone = true, 		 -- sell any number of "swords". This makes the quest completable mutiple times
	QuestGold = 50,			 -- pay: 50 gold
    Quest = true,
    CanShow = function()
        return Party.Food < 20 -- show only if less than maximum allowed food (otherwise below topic will be shown)
    end,
    Done = function(t)
        -- evt.Add almost always gives sound and sparkle animation, use direct access instead
        -- full list of "Party" properties: https://grayface.github.io/mm/ext/ref/#structs.GameParty
        -- also you can check there "Game" properties etc.
        Party.Food = Party.Food + 10 -- add 10 food
    end,
    Texts = {
        Topic = "Buy 10 food for 50 gold",
		Done = "Here you go, the speciality of the inn: the Arctic Wolf's foot!",
		Undone = "Sorry, you don't have enough money.",
    }
}
-- this topic will be shown if cannot buy due to exceeded maximum amount of food
-- NPCTopic is a variation of Quest function
NPCTopic {
    "Buy 10 food for 50 gold", -- topic
    "Your packs are full!", -- text
    NPC = 14, -- same npc
    Slot = 0, -- same slot
    CanShow = function() -- if this returns false, this topic won't be shown (and the other will be)
        return Party.Food >= 20 -- show only if too much food
    end,
    Ungive = function() -- runs either if quest can't be given due to function "CheckGive" returning false, or there is no "Give" text and function
        -- in this case it'll be run on each topic click
        -- show face animation
        -- Game.CurrentPlayer is 0-based player index or -1 if no player selected
        -- math.max makes player 0 show animation if no one is selected (max(-1, 0) == 0)
        Party[math.max(Game.CurrentPlayer, 0)]:ShowFaceAnimation(const.FaceAnimation.TavernPacksFull)
    end
}
--[[--
So here it would be nice to be able to set the strength of the potions (247, 248), e.g. to 100 potion strenght. Otherwise everything else works.
The timer too, but I'll figure out exactly what the theme should be :)
]]
vars.ratTailQuest = vars.ratTailQuest or {} -- new container in vars, which are kept in savegame
-- the or operator makes sure so that if the field is already set, we won't overwrite it with empty table

local setNpcSpeakTimer -- forward declaration, allows using function inside "Done" while defining the code below
Quest {
	"Rat Tail Quest",
    NPC = 14,
    Slot = 1,
    QuestItem = 1,
    -- KeepQuestItem = false, -- not needed, default is to remove item
    Experience = 75000,
    Gold = 13000,
    Done = function(t)
        evt.Add("Inventory", 247) -- this function I think always adds item to the mouse, so you can manipulate it that way
        Mouse.Item.Bonus = 100 -- potions use "Bonus" field for power
		evt.Add("Inventory", 247)
        Mouse.Item.Bonus = 100
		evt.Add("Inventory", 248)
        Mouse.Item.Bonus = 100
		evt.Add("Inventory", 248)
        Mouse.Item.Bonus = 100
        -- for same effect:
        --[[
        local items = {247, 247, 248, 248}
        for _, id in ipairs(items) do
            evt.Add("Inventory", id)
            Mouse.Item.Bonus = 100
        end
        ]]
        -- example: make NPC speak to you after 21 days pass
        -- modified MMExtension example, because "Sleep" function doesn't preserve queued sleeps after game reload
		local npc = 472
        vars.ratTailQuest.npcSpeakTime = Game.Time + const.Day*1 -- set time to speak
        setNpcSpeakTimer() -- launch timer even if game is not reloaded
    end,
    Quest = true,
    --[[ not neeeded
    CheckDone = function()
        return true
    end,
    --]]
  Texts = {Topic = "rat tail", Done = "done", Undone = "Undone", Give = "Give", TopicDone = false} -- topicDone = false makes topic disappear when quest is completed
}

-- speak npc part
-- this will be run every time savegame is reloaded or new game started

local timerSet
function setNpcSpeakTimer()
    if timerSet then -- only once per reload
        return
    end
    timerSet = true
    -- use "cocall" function to allow correctly using "Sleep" inside
    -- (if you didn't use it, npc might still speak, but any code below the Sleep() call [or calling "setNpcSpeakTimer" function] would be paused as well)
    cocall(function()
        local sleepFor = vars.ratTailQuest.npcSpeakTime - Game.Time
        if sleepFor >= 0 then
            Sleep(sleepFor, nil, {0}) -- execution pauses here until required time passes
        end
        vars.ratTailQuest.npcSpokeAlready = true
        Greeting{
            NPC = 14,
            "Do you find the game fun?"
        }
        evt.SpeakNPC(14)
    end)

    -- alternate way (to enable, uncomment below function and fully comment out "cocall()" above):
    --[[ function events.Tick() -- this runs on each tick (smallest unit of game time)
        if Game.Time >= vars.ratTailQuest.npcSpeakTime and Game.CurrentScreen == 0 then
            vars.ratTailQuest.npcSpokeAlready = true
            Greeting{
                NPC = 14,
                "Do you find the game fun?"
            }
            evt.SpeakNPC(14)
            events.Remove("Tick", 1) -- remove itself, so will run only once
        end
    end ]]

    -- there is also another way with timer, that will be added later
end

function events.LoadMap()
    if not vars.ratTailQuest.npcSpokeAlready and vars.ratTailQuest.npcSpeakTime then -- only set timer if npc didn't speak before and if speak time is set
        setNpcSpeakTimer()
    end
end

do return end

--[[
The texts part is fine, and I don't want to paste it on purpose, don't want to shoot the punchline. :) It does it in this form, it gives you the mission and apparently everything is ok, but it doesn't check if I killed the 1 monster standing in front of the test house with ID 190. If I don't kill it, it just accepts the quest even so.
]]

Quest {
    "KillWolfQuest", 
    NPC = 464,
    Slot = 2,
    Experience = 75000, 
    Gold = 13000,  
    
    Quest = true, 
    CheckDone = function()
        return evt.CheckMonstersKilled {CheckType = 2, Id = 190 - 1, Count = 0}					-- all monsters of id 190 on current map must be killed to show topic
        -- WARNING: this function takes monster type - 1 as argument to work properly
    end,
  
	CanShow = function()
        return true -- CONDITION moved to checkDone to make quest show always, but not complete until condition is satisfied
        -- you can undo that, but I recommend to add "NeverGiven = true" in such case, because it'd be strange for quest to be given ONLY after completing it ;)
	end,

  Texts = {Topic = "kill wolf", Done = "done", Undone = "Undone", Give = "Give"}
}

-- to show two topics you need two Quest{} or NPCTopic{} calls, there's no way around it
-- custom quest states are only assignable by yourself, default code won't do anything with them
-- first topic, clickable and contains all texts, but can't be completed
QuestNPC = 14
Quest {
    "KillWolfQuest",
    NPC = 447,
    Slot = 2,
    Quest = true,
    CheckDone = false, -- test complete in other topic
    Texts = {
        Topic = "Quest",
        TopicGiven = "Quest",
        TopicDone = false,
        Done = "done", Undone = "Undone", Give = "Give", Award = "Award", Quest = "Quest"
    }
}
Quest
{
    BaseName = "KillWolfQuest", -- is another topic dedicated to same quest as above, both will be marked as "done" on completion
    NPC = 447,
    Slot = 3, -- different slot
    Experience = 75000, -- this one contains rewards
    Gold = 13000,
    -- CheckDone = function() return true end, -- always completable
    CanShow = function(t)
        return evt.CheckMonstersKilled {CheckType = 2, Id = 190 - 1, Count = 0} -- but shows only if monsters are killed
    end,
    Texts = {
        Topic = "Killed!",
        TopicDone = false,
        Done = "You have killed all of the Wolves!",
    }
}