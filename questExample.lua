Quest {
    "BananaQuest", -- quest id. Can be any string. This is how you will refer to this quest (via vars.Quests["BananaQuest"] or vars.Quests.BananaQuest)
    NPC = 9999, -- npc which will manage this quest (will have conversation topic etc.)
    Slot = 0, -- number of slot the npc topic will be in. Each NPC has 6, numbered from 0 to 5. Only four topics can be shown at any one time though
    QuestItem = 9999, -- item needed to complete quest, can be missing if you provide your own CheckDone function (see below). Item will be removed on completion unless...
    -- KeepQuestItem = true, -- this line is uncommented (dashes at the beginning removed)
    Experience = 75000, -- experience reward
    Gold = 13000, -- gold reward
    Quest = true, -- should work. If it doesn't, provide any unused ("0" text in quests.txt) quest bit below 256

    -- example CheckDone function. if you want just item or gold to complete, can be removed. If this function returns true, quest will be completed
    CheckDone = function()
        return true -- always completable
        --[[
        -- to enable this requirement, uncomment it and comment out the return above
        return Party.Food < 5 -- have less than 5 food, to verify that you didn't eat some bananas :)
        ]]
    end,
    
    -- example Done function. Will be run on quest completion, you can add custom rewards here
    Done = function()
        -- example: refill every player's mana
        for i, pl in Party do
            pl.SP = math.max(pl.SP, pl:GetFullSP()) -- math.max makes it so that mana won't decrease if it's above maximum
        end
    end,

    -- example CanShow function. Will be run when you enter NPC dialog, if this function returns false, topic won't be shown at all
    CanShow = function()
        return evt.CheckMonstersKilled{CheckType = 3, Id = 200, Count = 0} -- all monsters of id 200 on current map must be killed to show topic
    end,

    CheckGive = function()
        -- example: make sure that every player has at least 15 level
        
        -- i is player index, increments by 1 starting from 0 for each PC from left to right
        -- pl is variable which contains party member data
        for i, pl in Party do
            if pl.LevelBase < 15 then -- check if level is at least 15. Full list of player properties you can access (and change) is here: https://grayface.github.io/mm/ext/ref/#structs.Player
                return false -- exit the code, quest can't be completed
            end
        end
        return true -- if the code didn't exit, every player has 15+ level. Quest can be given
    end,
    
    -- texts pertaining to the quest
    Texts = {
        Topic = "I need bananas", -- topic you can click on
        TopicGiven = "Do you have bananas?", -- this topic will be shown if quest has been given (usually this means clicked for the first time). Can be skipped
        TopicDone = "Thanks for bananas!", -- this topic will be shown if quest has been done. Can be skipped
        -- TopicDone = false, -- topic will disappear if quest is completed
        Give = "I need bananas, can you give me some? You will be rewarded.", -- shown when quest is given
        Ungive = "I can't trust you with such great requirement. Only properly experienced adventurers can find bananas. Sorry.", -- will be shown if quest can't be given (either due to missing "Give" text or if CheckGive function returns false)
        Undone = "Why can't you get some bananas for me? I need them. Please.", -- will be shown if quest can't be completed (due to item requirement or CheckDone function returning false)
        Done = "Thanks for the bananas! Here is some gold for you. Have also some banana juice I just made. [Banana juice tastes wonderfully. Your spiritual energy is restored]", -- will be shown when quest is done (only one time)
        After = "You were such a nice man. Thanks again.", -- will be shown after quest completion if topic is again clicked on. Not needed if TopicDone is false
        Award = "Obtained bananas", -- award that is given on quest completion. Can be skipped
        Quest = "Find some bananas", -- text that will be shown in quest log
    }
}