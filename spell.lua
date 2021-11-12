local damage = module.internal("damage")
local ts = module.internal("TS")
local pred = module.internal("pred")
local orb = module.internal("orb")
local common = module.load("Tribble_AIO","common")

local spell = class()
local getDmg = damage.spell
local getTar = ts.get_result
local countMoveCloser = 0
local lastTarget = nil

-- local variables for API functions.
local string_find, string_lower, pairs, pred_get_prediction, math_abs, math_sqrt
    = string.find, string.lower, pairs, pred.get_prediction, math.abs, math.sqrt

-- set up menu
function spell:__init(menu)
	self:bindToMenu(menu)
end

-- the menu organization
function spell:bindToMenu(menu)
	self.slotname = ({"W","E","R",[0]="Q"})[self.slot]
	self.menu = menu:menu(self.slotname, self.slotname)
	if (self.makeMenu) then
		self:makeMenu()
	end
	return self
end

-- positive if there is a wall.
function spell:isYasWallBetween(target)
	if common.avoidObjects and #common.avoidObjects >= 1 then
		for run, value in pairs(common.avoidObjects) do
			if 		value.valid
			and string_find(string_lower(value.name),string_lower("w_windwall"))
			and player:dist(value) < 1500
			and player:dist(value) < player:dist(target)
			then
				return true
			end
		end
	end
	return false

end

-- Determine whether to cast or not, as well as create the target point for the cast.
function spell:castOrNot(target, speedAway_mult, speedTowards_mult, spellRange, adjustRange, spellSlot)

	if not common:isTargetValid(target) then return end

	local dist = player:dist(target)
	local i = 0
	local targetPrint = ""
	local Delay1  = ""
	local Delay2 = ""
	local outputPrint = ""
	local speedNormalize = 0
	local normalize = 0

	common.alpha = 0
	common.beta  = 0
	common.gamma = 0

	-- velocity is 0 if the character is not moving.  Greater than zero when moving
	-- moveSpeed (see below) is the potential speed of the character.  Will be at baseline level even if standing still
	-- combination of velocity and moveSpeed required to determine if moving and at what speed
	local velocity = math_sqrt(target.velocity.x*target.velocity.x + target.velocity.z*target.velocity.z)
	local moveSpeed = target.moveSpeed
	if velocity == 0 then moveSpeed = 0 end			-- correct baseline moveSpeed to allow for zero

	if dist < spellRange
	then
		if self:isYasWallBetween(target) then return false end

		local dist = player:dist(target)
		if lastTarget ~= target then
			countMoveCloser = 0
		end
		lastTarget = target

		if moveSpeed > 0 then

			-- get first estimate of position/time with current prediction
			local output = pred_get_prediction(player, target, spellSlot)
			local isfleeing = common:isFleeing(target, player, output.endPos) -- determines if moving away or towards
			
			common.future_pos = output.endPos
			common.future_pos3d = output.endPos
			
			if (common.gamma > 45 and common.gamma < 135) then													-- determine if movement more or less perpendicular to line of fire
				speedNormalize = (50 * (target.moveSpeed))/700		-- if so, add up to 100 units (might need to alter depending on champ)
			end
			
			if dist > 700 then
				if not isfleeing                                                             -- if not running away, add a little towards me
				then
					speedNormalize = speedNormalize + 50 * target.moveSpeed/700   -- depending on moveSpeed, add some buffer, max 50 units
					
				else
					speedNormalize = speedNormalize + 200 * target.moveSpeed/700   -- depending on moveSpeed, subtract some buffer
				end
				common.future_pos = output.endPos - (output.startPos - output.endPos):norm() * (adjustRange + speedNormalize)
			end
		else
			common.future_pos = target.pos
			common.future_pos3d = target.pos				-- this is just to check original prediction versus altered position.
		end
 
		if dist <=	player:dist(common.future_pos) then
			if not isfleeing and speed == 0 then
				return true
			elseif not isfleeing then
				if countMoveCloser >= 2 then							-- make sure moving closer is twic e before casting...
					countMoveCloser = 0
					return true
				else
					countMoveCloser = 1 + countMoveCloser
					return false
				end
			elseif isfleeing  -- Convert to distance.
			then
				return true
			end
		end
	end

	return false
end

-- Find the nearest point to a line. Not currently used.
function spell:distPointToLine(px,py,x1,y1,x2,y2) -- point, start and end of the segment
	local dx,dy = x2-x1,y2-y1
	local length = math_sqrt(dx*dx+dy*dy)
	dx,dy = dx/length,dy/length
	local p = dx*(px-x1)+dy*(py-y1)
	if p < 0 then
		dx,dy = px-x1,py-y1
		return math_sqrt(dx*dx+dy*dy), x1, y1 -- distance, nearest point
	elseif p > length then
		dx,dy = px-x2,py-y2
		return math_sqrt(dx*dx+dy*dy), x2, y2 -- distance, nearest point
	end
	return math_abs(dy*(px-x1)-dx*(py-y1)), x1+dx*p, y1+dy*p -- distance, nearest point
end

-- is not able to move or control
function spell:isHindered(target)
	local velocity = math_sqrt(target.velocity.x*target.velocity.x + target.velocity.z*target.velocity.z)
	return (target.isStunned
	or target.isRecalling
	or target.isFeared
	or target.isTaunted
	or target.isAsleep
	or target.isFleeing
	or target.isCharmed
	or target.isRooted
	or velocity == 0)

end

-- if I have corrupt potion, cast it.
function common:castCorrupt(target, howFar)

	local ID = nil
	for i = 0, 38 do
		local item = player.heroInventory:get(i)
		if 		(item)
		and  item.displayName == "Corrupting Potion"
		and  item.ammo > 0
		then
			ID = item.id
			if ID > 0 then
				for j = 0, 5 do
					if player:itemID(j) == ID then
						k = j + 6
					end
				end

				for l = 0, player.buffManager.count - 1 do
					local buff = player.buffManager:get(l)
					if 		buff.valid
					and buff.name == "ItemDarkCrystalFlask"
					then
						return
					end
				end

				if 100*player.health/player.maxHealth < 100
				or  player.mana < 100
				or player:dist(target) < howFar
				then
					player:castSpell("self", k, player)
					return
				end
			end
		end
	end
end

-- is the spell usable?
function spell:usable()
	return player:spellState(self.slot) == SpellState.Ready
end

-- improve synergy with orb walking
function spell:passiveDamage(target)
	local damage
	if player.levelRef < 4 then
		damage = player.totalBonusAttackDamage * 0.5
	elseif player.levelRef < 7 then
		damage = player.totalBonusAttackDamage * 0.6
	elseif player.levelRef < 9 then
		damage = player.totalBonusAttackDamage * 0.7
	elseif player.levelRef < 11 then
		damage = player.totalBonusAttackDamage * 0.8
	elseif player.levelRef < 13 then
		damage = player.totalBonusAttackDamage * 0.9
	else
		damage = player.totalBonusAttackDamage
	end
	return damage
end

-- A list of spells that can be interrupted with stun, etc.
spell.interruptableSpells = {
	["anivia"] = {
		{menuslot = "R", slot = 3, spellname = "glacialstorm", channelduration = 6}
	},
	["caitlyn"] = {
		{menuslot = "R", slot = 3, spellname = "caitlynaceinthehole", channelduration = 1}
	},
	["ezreal"] = {
		{menuslot = "R", slot = 3, spellname = "ezrealtrueshotbarrage", channelduration = 1}
	},
	["fiddlesticks"] = {
		{menuslot = "W", slot = 1, spellname = "drain", channelduration = 5},
		{menuslot = "R", slot = 3, spellname = "crowstorm", channelduration = 1.5}
	},
	["gragas"] = {
		{menuslot = "W", slot = 1, spellname = "gragasw", channelduration = 0.75}
	},
	["janna"] = {
		{menuslot = "R", slot = 3, spellname = "reapthewhirlwind", channelduration = 3}
	},
	["karthus"] = {
		{menuslot = "R", slot = 3, spellname = "karthusfallenone", channelduration = 3}
	}, --common:IsTargetValidTarget will prevent from casting @ karthus while he's zombie
	["katarina"] = {
		{menuslot = "R", slot = 3, spellname = "katarinar", channelduration = 2.5}
	},
	["lucian"] = {
		{menuslot = "R", slot = 3, spellname = "lucianr", channelduration = 2}
	},
	["lux"] = {
		{menuslot = "R", slot = 3, spellname = "luxmalicecannon", channelduration = 0.5}
	},
	["malzahar"] = {
		{menuslot = "R", slot = 3, spellname = "malzaharr", channelduration = 2.5}
	},
	["masteryi"] = {
		{menuslot = "W", slot = 1, spellname = "meditate", channelduration = 4}
	},
	["missfortune"] = {
		{menuslot = "R", slot = 3, spellname = "missfortunebullettime", channelduration = 3}
	},
	["nunu"] = {
		{menuslot = "R", slot = 3, spellname = "nunushield", channelduration = 3}
	},
	["pantheon"] = {
		{menuslot = "R", slot = 3, spellname = "pantheonrjump", channelduration = 2}
	},
	["shen"] = {
		{menuslot = "R", slot = 3, spellname = "shenr", channelduration = 3}
	},
	["twistedfate"] = {
		{menuslot = "R", slot = 3, spellname = "gate", channelduration = 1.5}
	},
	["varus"] = {
		{menuslot = "Q", slot = 0, spellname = "varusq", channelduration = 4}
	},
	["warwick"] = {
		{menuslot = "R", slot = 3, spellname = "warwickr", channelduration = 1.5}
	},
	["xerath"] = {
		{menuslot = "R", slot = 3, spellname = "xerathlocusofpower2", channelduration = 3}
	}
}

return spell