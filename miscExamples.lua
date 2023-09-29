-- What command can be used to set the received gold and damage to random values within a certain range?

-- Gold:
-- 1st way
Party.Gold = Party.Gold + math.random(500, 1500) -- gives between 500 to 1500 gold, DOESN'T show message nor play sound
Game.NeedRedraw = true -- prevents text overlap bug

-- 2nd way
evt.Add("Gold", math.random(200, 1000)) -- gives between 200 to 1000 gold, shows msg and plays sound, shared with npc

-- 3rd way
-- from MMExt reference:
Party.AddGold(2000, 0)
-- Kind (second argument) values:
-- 0 = increase by Banker, give some part to followers
-- 1 = take exect amount, ignore followers
-- 2 = [MM7+] take all and don't show message, just clear status message
-- 3 = [MM7+] take all and don't change status message

-- 4th way:
evt.Add("GoldAddRandom", 1000) -- gives 1-1000 gold

-- Damage:
-- 1st way:
evt.DamagePlayer{DamageType = const.Damage.Fire, Damage = math.random(10, 50)} -- damages currently selected player
evt.DamagePlayer{Player = 2, DamageType = const.Damage.Fire, Damage = math.random(10, 50)} -- damages 3rd party member
evt.DamagePlayer{Player = "Random", DamageType = const.Damage.Fire, Damage = math.random(10, 50)} -- damages random party member

-- for more "Player" values, see here: https://grayface.github.io/mm/ext/ref/#evt.Players

-- 2nd way:
Party[1].HP = Party[1].HP - math.random(20, 30) -- [20-30] points of damage (non-resistable), DOESN'T play sound nor show animation

-- 3rd way:
Party[0]:DoDamage(math.random(100, 200)) -- physical by default
Party[1]:DoDamage(math.random(100, 200), const.Damage.Fire)