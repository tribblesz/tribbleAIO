-- local variables for API functions. any changes to the line below will be lost on re-generation
local IsTargetValid, getShieldedHealth, math_acos, math_random, math_sqrt, module_internal, objManager_loop, string_find, string_format, string_lower, table_move, table_unpack 
    = IsTargetValid, getShieldedHealth, math.acos, math.random, math.sqrt, module.internal, objManager.loop, string.find, string.format, string.lower, table.move, table.unpack

local common = class()
local pred = module_internal("pred")
local ts = module_internal("TS")
local getTar = ts.get_result
local damage = module_internal("damage")
local orb = module_internal("orb")

common.isfleeing = true

common.avoidObjects = {}
common.aoTime = {}
common.nameObject = {}
common.printFormat = ""

common.target = nil
common.future_pos3d = nil

common.future_pos = nil
common.speedAwayTime = 0
common.speedAwayDist = 0

common.distancePred = 0
common.alpha = 0
common.beta  = 0
common.gamma = 0
common.URF = string_find(string_lower(game.mode),string_lower("URF"))

print("URF is: ", common.URF)

common.pred = {
	spellNum = 2,
	delay = 0.25,
	width = 135,
	speed = 1200,
	range = 970,
	boundingRadiusMod = 1,
	collision = {hero = false, minion = false, wall = false},
}

common.w = {
	slot = player:spellSlot(1),
	last = 0,
	range = 1325, --1380625

	result = {
		obj = nil,
		dist = 0,
		seg = nil,
	},

	predinput = {
		delay = 0.25,
		range = 1325,
		width = 40,
		speed = 1800,
		boundingRadiusMod = 1,
		collision = {
			hero = true,
			minion = true,
			wall = true,
		},
	},
}

local spellPrint = {"Q","W","E","R"}
local lastLevel = 0
local timerLevel = game.time

-- returns the best target in range
local function normalFilter(res, tar, dist)
	-- returns the best target in range
	if dist > 1500 then
		return false
	end
	res.obj = tar
	return true
end

-- updates common.target with the best target
function common:updateTarget()
	local res = getTar(normalFilter, nil, false, true)
	if not res or not res.obj then
		return
	end
	if res.obj:isValidTarget() then
		common.target = res.obj
	end
end

function common:getBestTarget(spellSlot)
	
	-- get magical and physical resistance of target
	-- figure out damage components of spell:__init
	-- determine mitigation
	-- determine which target is best target
	local lowestEnemy = common.target
	for enemy in objManager.heroes{ team = TEAM_ENEMY, dist = 1500, valid_target = true } do
		if common:isTargetValid(enemy)
		then
			if not lowestEnemy then 
				lowestEnemy = enemy
				print("nil Changed to:", enemy.name )
				log( enemy.name )
				goto nextIterate
			end
			if enemy.health - damage.spell(player, enemy, spellSlot) < lowestEnemy.health - damage.spell(player, lowestEnemy, spellSlot)
			and player:dist(enemy) < 1000
			then
				print("Changed to:", enemy.name )
				log( enemy.name )
				lowestEnemy = enemy
			end		
		end
		::nextIterate::
	end	
	common.target = lowestEnemy
	
end


-- translate Spell keyboard value into number
function common:levelSpellTranslate(whatIs)
	if whatIs == "Q" then
		return 0
	elseif whatIs == "W" then
		return 1
	elseif whatIs == "E" then
		return 2
	elseif whatIs == "R" then
		return 3
	end
	return nil
end

-- level the spell
function common:levelSpell(spellOrderEarly)

	if lastLevel ~= player.levelRef then

		if (game.time - timerLevel)*1000 > 5000 then
			timerLevel = game.time
			return
		end

		if (game.time - timerLevel)*1000 > (500 + math_random(1000,2000)) then

			lastLevel = lastLevel + 1

			if (player.levelRef <= 19) then
				if player:levelSpell( common:levelSpellTranslate( spellOrderEarly[lastLevel] )) then
					print("Spell Upgraded:", spellOrderEarly[lastLevel])
				else
					print("Attempted to level")
				end
			end
		end
	end
end

-- is the point inside the polygon
function common:insidePolygon(polygon, point)
	local oddNodes = false
	local j = #polygon
	for i = 1, #polygon do
		if (polygon[i].y < point.y and polygon[j].y >= point.y or polygon[j].y < point.y and polygon[i].y >= point.y) then
			if (polygon[i].x + ( point.y - polygon[i].y ) / (polygon[j].y - polygon[i].y) * (polygon[j].x - polygon[i].x) < point.x) then
				oddNodes = not oddNodes;
			end
		end
		j = i;
	end
	return oddNodes
end

-- mana check...  is this working again?
function common:check_mana(mana_percentage)
	if ((player.mana / player.maxMana) * 100) >= mana_percentage then
		return true
	else
		return false
	end
end

-- look for closest object and return
function common:getClosestObj(source_obj,table_obj)
	local mindist = math.huge
	local minobj = nil
	for _,obj in pairs(table_obj) do
		local dist = obj:dist(source_obj.pos)
		if dist < mindist then
			mindist = dist
			minobj = obj
		end
	end
	return minobj
end

-- concatenate two arrays
function common:concatArray(a, b)
	local result = {table_unpack(a)}
	table_move(b, 1, #b, #result + 1, result)
	return result
end

-- check that point is not under a dangerous tower.
function common:IsUnderDangerousTower(pos)
	if not pos then return false end
	for tower in objManager.turrets{ team = TEAM_ENEMY, dist = 1000, valid_target = true }  do
		if not tower.isDead and tower.health > 0 then
			if tower.pos:dist(pos) < (915+player.boundingRadius)  then
				return true
			end
		end
	end
	return false
end


function common:makeGetPercentStatFunc(_type)
	local min, max = _type, "max" .. _type:sub(1, 1):upper() .. _type:sub(2)
	return (function(obj) obj = obj or player return 100 * obj[min] / obj[max] end)
end

-- Look for invulnerable
function common:isInvincible(object)
	return object.buff[17] ~= nil
end

-- check across all valid types
function common:isTargetValid(object)

	return (
		object
		and object.ptr ~= 0
		and not object.isDead
		and object.isVisible
		and object.isTargetable
		and not object.invulnerable
		and not object.buff[17] ~= nil
	)
end

-- is the hero valid?
function common:isHeroValid(object, range)
	return (
	object
	and object.ptr ~= 0
	and object.type == TYPE_HERO
	and not object.isDead
	and object.isVisible
	and (object.team == player.team
	or object.isTargetable
	)
	and (not range or object.pos2D:distSqr(player.pos2D) < range * range)
	)
end

-- check validity of minion
function common:isMinionValid(object, ignoreTeam)
	return (
	object
	and object.ptr ~= 0
	and object.type == TYPE_MINION
	and (ignoreTeam or object.team ~= TEAM_ALLY)
	and not object.isDead
	and object.isVisible
	and object.isTargetable
	and object.health > 0
	and object.maxHealth > 5
	and object.maxHealth < 100000
	)
end

-- return distance squared between points
function common:GetDistanceSqr(p1, p2)
	local p2 = p2 or player
	local dx = p1.x - p2.x
	local dz = (p1.z or p1.y) - (p2.z or p2.y)
	return dx * dx + dz * dz
end

-- return distance between points
function common:GetDistance(p1, p2)
	local squaredDistance = common:GetDistanceSqr(p1, p2)
	return math_sqrt(squaredDistance)
end

function common:angles(a1, b1, c1)

	local a2 = common:GetDistanceSqr(b1, c1)
	local b2 = common:GetDistanceSqr(a1, c1)
	local c2 = common:GetDistanceSqr(a1, b1)

	local a = math_sqrt(a2)
	local b = math_sqrt(b2)
	local c = math_sqrt(c2)

	common.alpha = math_acos((b2 + c2 - a2)/(2*b*c))
	common.beta  = math_acos((a2 + c2 - b2)/(2*a*c))
	common.gamma = math_acos((a2 + b2 - c2)/(2*a*b))

	-- Converting to degree
	common.alpha = common.alpha * 180 / math.pi
	common.beta  = common.beta  * 180 / math.pi
	common.gamma = common.gamma * 180 / math.pi

end

-- True if fleeing, false if moving towards or standing still
function common:isFleeing(target, source, pred_pos)

	if not common:isTargetValid(target) then
		return false
	end

	common:angles(source.pos, target.pos, pred_pos)

	local sourceToTrg = target.pos:dist(source.pos)
	local sourceToPre = vec3(pred_pos):dist(source.pos)

	if sourceToPre > sourceToTrg then
		return true
	end
	
	return false

end

-- improve synergy with orb walking
function common:passiveDamage()
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

-- return number of enemies in range.
function common:CountEnemiesInRange(pos, range)
local enemies_in_range = {}
for enemy in objManager.heroes{team = TEAM_ENEMY, valid_target = true, dist = range} do
	enemies_in_range[#enemies_in_range + 1] = enemy
end
return enemies_in_range
end

-- return the aa Range
function common:getAARange(obj, source)
source = source or player
return player.attackRange + player.boundingRadius + (obj and obj.boundingRadius or 0)
end

-- return the ignite damage
function common:getIgniteDamage(target)
local damage = 55 + (25 * player.levelRef)
if target then
	damage = damage - (getShieldedHealth("AD", target) - target.health)
end
return damage
end

-- print the outcome of a spell cast
function common:printIt(mainWF, whereFrom, target)
local distance = player:dist(target)
local distance2 = player:dist(common.future_pos)
if common:isTargetValid(target)
then
	common.printFormat = string_format("%10s %10s  Target:%15s   Dist: %.0f  Dist: %.0f  Time: %f", mainWF, whereFrom, target.name, distance, distance2, game.time)
	log(common.printFormat)
	print(common.printFormat)
end
end

-- if we have corrupt...  cast
function common:castCorrupt(target, howFar)
local ID = nil
for i = 0, 38 do
	local item = player.heroInventory:get(i)
	if (item)
	and item.displayName == "Corrupting Potion"
	and item.ammo > 0
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

--
function common:HitChance(range, dist)
return 0
--return 100 - 100*(player.mana/player.maxMana)
end

-- Interrupts a class of spells with E/bomb.
function common:invoke_interrupt(spell, spellNum)
if player:spellState(spellNum) == 0 then
	if spell.owner.type == TYPE_HERO and spell.owner.team == TEAM_ENEMY then
		local enemyName = string_lower(spell.owner.charName)
		if self.interruptableSpells[enemyName] then
			for i = 1, #self.interruptableSpells[enemyName] do
				local spellCheck = self.interruptableSpells[enemyName][i]
				if string_lower(spell.name) == spellCheck.spellname then
					if player.pos2D:dist(spell.owner.pos2D) < 970 and IsTargetValid(spell.owner) then
						local seg = gpred.circular.get_prediction(self.pred, spell.owner)
						local range = self.pred.range * self.pred.range
						if seg and seg.startPos:distSqr(seg.endPos) <= range then
							player:castSpell("pos", 2, vec3(seg.endPos.x, spell.owner.y, seg.endPos.z))
						end
					end
				end
			end
		end
	end
end
end

-- Katarina Q
-- Yone dash
function common:invoke_on_dash()
if player:spellState(2) == 0 then
	local target = ts.get_result(function(res, obj, dist)
	if dist > 2500 then
		return
	end
	if dist <= (self.pred.range + obj.boundingRadius) and obj.path.isActive and obj.path.isDashing then
		res.obj = obj
		return true
	end
	end).obj

	if target then
		local dist = player:dist(target)
		local pred_pos = gpred.core.lerp(target.path, network.latency + spell.pred.delay, target.path.dashSpeed)
		if pred_pos and pred_pos:dist(player.path.serverPos2D) > common.GetAARange() and pred_pos:dist(player.path.serverPos2D) <= spell.pred.range then
			common:printIt("Main","e_InvokeDash", target)
			player:castSpell("pos", 2, vec3(pred_pos.x, target.y, pred_pos.z))
			orb.core.set_server_pause()
			return true
		end
	end
end
end

-- Look for certain strings in the table
function common:searchStrings(spellObject, dist, spellIgnore)

local objectDist = player:dist(spellObject)
	if 		spellObject.valid
		and objectDist < dist
	then
		if (((string_find(string_lower(spellObject.name),string_lower("Yasuo")) and not (player.charName == "Yasuo" and objectDist < 1200))
		and string_find(string_lower(spellObject.name),string_lower("Yasuo_base_w_windwall_enemy"))) 									-- when time is up)
		-- YasuoWChildMis * 2
		-- YasuoW_VisualMis
		-- Yasuo_Base_I_sheath_spark      end of activate

		--[3:25.49] Katarina_Base_Dagger_Ground_Indicator
		--[3:25.49] Found a problem
		--[3:25.49] Katarina_Base_Q_Dagger_Land_Dirt


		or ((    string_find(string_lower(spellObject.name),string_lower("Zed")) and not player.charName == "Zed")
		and (string_find(string_lower(spellObject.name),string_lower("Zed_Base_W_tar")) 					  						-- if this, avoid, but do not stun
		or string_find(string_lower(spellObject.name),string_lower("Zed_Base_CloneSwap")) 									-- if this and he is close, then wait to stun
		or string_find(string_lower(spellObject.name),string_lower("Zed_Base_Clone_death"))
		or string_find(string_lower(spellObject.name),string_lower("Zed_Base_R_Tar_TargetMarker"))))

		--		 or ((	string_find(string_lower(spellObject.name),string_lower("Leblanc")) and not player.charName == "Leblanc")
		--			 and (string_find(string_lower(spellObject.name),string_lower("Leblanc_Base_W_Return_indicator_death")) 	-- when time is up
		--				   or string_find(string_lower(spellObject.name),string_lower("LeBlanc_Base_W_Return_indicator"))			-- when she dashes
		--				   or string_find(string_lower(spellObject.name),string_lower("LeBlanc_Base_W_mis"))))

			or ((	string_find(string_lower(spellObject.name),string_lower("Katarina")) and not player.charName == "Katarina")
			and ( 	string_find(string_lower(spellObject.name),string_lower("Katarina_Base_W_mis"))
			or string_find(string_lower(spellObject.name),string_lower("Katarina_Base_Q_Dagger_Land_Dirt"))
			or string_find(string_lower(spellObject.name),string_lower("Katarina_base_Q_mis"))
		--  if close enough for her to hit you, assume it is and move.
		--  if not, look for close minion or enemy.
		-- will be complicated but worth...
		-- https://imgur.com/WhOPP3n
		-- https://www.reddit.com/r/KatarinaMains/comments/5ze39j/why_does_katarinas_q_sometimes_does_not_land_in/

		)))						-- when she dashes
		then
			return true
		end

		return false
	end
end

-- is there a yaswall up between me and target??
function common:isYasWallBetween(target)
	objManager_loop(function(obj)
		if 		player:dist(obj) < player:dist(target)
			and string_find(string_lower(obj.name),string_lower("Yasuo_base_w_windwall_enemy"))
		then
			print(obj.name)
		end
		end)
end

function common:nearTime(target, dist)

if string_find("katarina,zed,leblanc", string_lower(target.name))
then
	for run, value in pairs(common.avoidObjects) do			-- remove old objects
		if  	value.valid
		and string_find(string_lower(value), string_lower(target.name))
		and (game.time - common.aoTime[run]) *1000 > 500
		and player:dist(value) < dist
		then
			return true																-- found it and enough time pass to trust
		end
	end
	return false
end
return true

end

-- return the number of Heimer turrets on team ally.
function common:getNumTurrets(largeRange, tightRange, targetPos)
	
local numberturretsClosetoTarget = 0

	for minion in objManager.minions{ team = TEAM_ALLY, dist = largeRange } do
		if minion.name:find("H-28G") then
			local dist = minion:dist(targetPos)
			if dist < tightRange then
				numberturretsClosetoTarget = numberturretsClosetoTarget + 1
			end
		end
	end
	
	return numberturretsClosetoTarget
end

-- is there a collision between me and target
function common:isCollision(target)

	if player:dist(target) > 1500 then
		return true
	end
	
	--if common.URF then
		--print("URF collision allow")
		--return false
	--end

	local seg = pred.linear.get_prediction(common.w.predinput, target)
	if seg and seg.startPos:distSqr(seg.endPos) < 1380625 then
		local col = pred.collision.get_prediction(common.w.predinput, seg, target)
		if #col == 0 then
			return false
		end
	end

	return true
end

-- steal for any champs
function common:igniteExhaust(useIgnite, useExhaust, enemyRange)
	local dist = 0
	local countCloseEnemies = 0
	for enemy in objManager.heroes{team = TEAM_ENEMY, valid_target = true, dist = 650} do
		dist = player:dist(enemy)
		if not enemy.buff["sionpassivezombie"] ~= nil
		then
			common:exhaustIgniteCheck(enemy, useIgnite, useExhaust, enemyRange)
		end
	end

end

--  this will exhaust or ignite if close enough or enemy stunned, etc.
function common:exhaustIgniteCheck(enemy, useIgnite, useExhaust, enemyRange)

if enemy then
	local dist = player:dist(enemy)
	if dist < 600 then

		local health = 100*enemy.health/enemy.maxHealth
		local damage_total = 0
		local yes = 0

		for i = 4, 5 do
			if  (player:spellSlot(i).name  == "SummonerDot"
				and useIgnite
				and ( player:spellState(i) == SpellState.Ready
				or  game.time > player:spellSlot(i).cooldownEndTime))
			then
				damage_total = damage_total + damage.spell(player, enemy, i) * 1.5
				yes = i
			end

			if (yes == 0
				and player:spellSlot(i).name ==  "SummonerExhaust"
				and useExhaust
				and ( player:spellState(i) == SpellState.Ready
				or  game.time > player:spellSlot(i).cooldownEndTime))
			then
				yes = i
			end

			if (   yes > 0
				and ( enemy.health < damage_total
					or  dist < enemyRange
					or  health <= 15
					or (health <= 35
				and ( 	enemy.isStunned
					or  	enemy.isTaunted
					or 		enemy.isfeared
					or 		enemy.isFleeing
					or 		enemy.isAsleep
					or 		enemy.isCharmed
					or 		enemy.isRooted
					or 		enemy.isHardCCd
					or 		enemy.isHardMoveCCd
					or 		enemy.isSilenced
					or 		enemy.isImmovable))))
			then
				player:castSpell("obj", i, enemy)
				orb.core.set_server_pause()
				player:castSpell("obj", i, enemy)
				orb.core.set_server_pause()
			end
		end
	end
end
end


return common






