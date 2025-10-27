local pds_gravity = CreateConVar('pds_gravity', '1', { FCVAR_ARCHIVE, FCVAR_CLIENTCMD_CAN_EXECUTE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE })
local pds_height = CreateConVar('pds_height', '0', { FCVAR_ARCHIVE, FCVAR_CLIENTCMD_CAN_EXECUTE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE })

local function InitNpcSensitivityTable()
    local tableName = "stealth_npcsensitivity"
    print("Stealth Mod: 检查新表 '" .. tableName .. "' 的完整性...")

    if !sql.TableExists(tableName) then
        print("Stealth Mod: 表 '" .. tableName .. "' 不存在，正在创建...")
        local createQuery = "CREATE TABLE " .. tableName .. "(key TEXT NOT NULL PRIMARY KEY, value REAL)"
        if sql.Query(createQuery) == false then
            ErrorNoHalt("Stealth Mod: 创建表 '" .. tableName .. "' 失败：" .. sql.LastError())
        end
        return
    end

    local contents = sql.Query("SELECT * FROM " .. tableName)
    if contents == false then
        ErrorNoHalt("Stealth Mod: 查询表 '" .. tableName .. "' 失败：" .. sql.LastError())
        return
    end

    if type(contents) == "table" then
        local toText = util.TableToJSON(contents, true)
        local compressed = util.Compress(toText)
        if #compressed > 65530 then
            print("Stealth Mod: 表 '" .. tableName .. "' 数据过大！正在备份并重置...")
            
            if !file.IsDir("stealth/backup", "DATA") then
                file.CreateDir("stealth/backup")
            end
            file.Write("stealth/backup/" .. tableName .. ".txt", toText)
            sql.Query("DROP TABLE " .. tableName .. "; CREATE TABLE " .. tableName .. "(key TEXT NOT NULL PRIMARY KEY, value REAL)")
        end
    end

    print("Stealth Mod: 新表 '" .. tableName .. "' 完整性检查完成。")
end

local function ReadNpcSensitivity()
    local contents = sql.Query("SELECT * FROM stealth_npcsensitivity")
    if contents == nil then return {} end
    
    local adjusted = {}


	for _, v in ipairs(contents) do
		adjusted[v.key] = tonumber(v.value) or 0
	end
	return adjusted
end

local function WriteNpcSensitivity(contents)
    sql.Query("DELETE FROM stealth_npcsensitivity; VACUUM;")
    PrintTable(contents)
    
    sql.Begin()  
        for k, v in pairs(contents) do
            local safeKey = sql.SQLStr(tostring(k))  
            local tempValue
            

            tempValue = tonumber(v) or 0
   
            
            local query = "INSERT INTO stealth_npcsensitivity" .. " VALUES (" .. safeKey .. ", " .. tempValue .. ")"

            if sql.Query(query) == false then
                ErrorNoHalt("Stealth Mod: " .. sql.LastError() .. "\n")
            end
        end
    sql.Commit()
end

local npcSensitivity_default = {
	["npc_combine_s"] = 2,
	["npc_metropolice"] = 1
}

local npcSensitivity_list = {}

hook.Add("Initialize", "pdsInit", function()
    InitNpcSensitivityTable()

	local loadFromDisk = ReadNpcSensitivity()
	local merged = table.Merge(npcSensitivity_default, loadFromDisk)
	table.CopyFromTo(merged, npcSensitivity_list)
end)

local function CheckLOSSimple(ply,npc)

	if !npc:TestPVS(ply) then return false end
	
	--if ply.stealth_iscloaked then return false end
	if ply:GetNWBool("sm_cloaked") or ply.cloaked then return false end
	
	--[[for boneid = 0, ply:GetBoneCount() do -- Considering how many bones the average playermodel has, the other way is worth it.
		local tr = util.TraceLine{
			start = npc:EyePos(),
			endpos = ply:GetBonePosition(boneid),
			filter = npc,
			mask = MASK_BLOCKLOS_AND_NPCS
		}
		if tr.Entity == ply then return true end
	end]]
	
	
	for i = 0, ply:GetHitboxSetCount()-1 do -- Having to make two loops just to get the hitbox positions is stupid.
		for o = 0, ply:GetHitBoxCount(i)-1 do
			local tr = util.TraceLine{
				start = npc:EyePos(),
				endpos = ply:GetBonePosition(ply:GetHitBoxBone(o,i)),
				filter = npc,
				mask = MASK_BLOCKLOS_AND_NPCS
			}
			if tr.Entity == ply then return true end
		end
	end
	
	return false
	
end

local function CheckLOSAdvanced(ply, npc)
	if tobool(stealthmod.CVarCache.ai_disabled) or tobool(stealthmod.CVarCache.ai_ignoreplayers) then return end
	if IsValid(ply) and ply:IsFlagSet(FL_NOTARGET) then return end
	
	if not ply:Alive() then return end
	if not ply then return end
	if not ply.stealth_Luminocity then return end

	-- Variables
	local minsight = tonumber(stealthmod.CVarCache.stealth_minsight)
	local maxsight = tonumber(stealthmod.CVarCache.stealth_maxsight)
	--local movementbonus = cvars.Number("stealth_speedmultiplier")
	local minhearing = tonumber(stealthmod.CVarCache.stealth_minhearing)
	--local shotfactor = cvars.Number("stealth_gunshotfactor")
	local multiplier = tonumber(stealthmod.CVarCache.stealth_multiplier)
	if minsight < 0 then minsight = 0 end
	if maxsight < 0 then maxsight = 0 end
	if !ply.stealth_shooting then ply.stealth_shooting = 0 end
	--if movementbonus < 0 then movementbonus = 0 end
	--if minhearing < 0 then minhearing = 0 end
	--if shotrange < 0 then shotrange = 0 end
	--if multiplier < 0 then multiplier = 0 end
	

	local isvisible = CheckLOSSimple(ply,npc)
		
	-- ConVar to number
	local alerttime = math.max(tonumber(stealthmod.CVarCache.stealth_alerttime), 0)
	
	if not isvisible then 
		if not timer.Exists(npc:EntIndex().."Cooldown") then
			-- Use ConVar as timer duration
			timer.Create(npc:EntIndex().."Cooldown",alerttime,1,function() 
				if IsValid(npc) then 
					npc:SetTarget(npc) 
					stealthmod.CalmNPC(ply, npc) 
				end 
			end)
			
			--npc:AddEntityRelationship(ply, D_NU, 1) -- I tried to add Manhunt style hiding after being caught, but this method just makes them stop searching for you.
		end 
	elseif timer.Exists(npc:EntIndex().."Cooldown") then
		-- Use ConVar as timer duration
		timer.Adjust(npc:EntIndex().."Cooldown",alerttime,1, function()
			if IsValid(npc) then 
				npc:SetTarget(npc) 
				stealthmod.CalmNPC(ply, npc) 
			end 
		end)
	end

	local yawdiff = math.abs(math.AngleDifference(npc:EyeAngles().y, (ply:GetPos()-npc:GetPos()):Angle().y))
	
	local lightbonus = ( (maxsight - minsight) * math.Clamp(ply.stealth_Luminocity/255 + ply.stealth_shooting/2, 0, 1.2) ) 
	--print(lightbonus)
	
	--local playerspeed = ply:GetVelocity():Length()
	local playerdist = ply:GetPos():DistToSqr(npc:GetPos())
	-- Sight and hearing are different variables
	--local sightrange = ( minsight + lightbonus * (1+(movementbonus*(playerspeed/200))) ) * multiplier
	local sightrange = ( minsight + lightbonus ) * multiplier
	sightrange = sightrange*sightrange
	--local hearrange = ( minhearing * (playerspeed/200) ) * multiplier
	local hearrange = minhearing * multiplier
	
	-- Enemies can't see what's behind them or behind walls
	if yawdiff>60 or not isvisible then
		sightrange = 0
	end
	
	-- If player is hiding under a cardboard box, and is not moving, ignore him.
	local wep = ply:GetActiveWeapon()
	if IsValid(wep) then
		if wep:GetClass() == "weapon_cbox" and ply:Crouching() and ply:GetVelocity():LengthSqr() < 32 then
			sightrange = 0
			--hearrange = 0
		end
	end
	--if ply:GetNWBool("sm_DisguiseActive") then
	if tobool(stealthmod.CVarCache.stealth_enabledisguises) and !npc.stealth_DisguiseMemory[ply:EntIndex()][ply:GetModel()] then
		local simplemodel = player_manager.TranslateToPlayerModelName(ply:GetModel())
		if disguises_list[npc:GetClass()] and disguises_list[npc:GetClass()][simplemodel] then 
		--if disguises_list[npc:GetClass()] and disguises_list[npc:GetClass()][ply:GetModel()] then 
			for _, a in ipairs(ply.Footprints.age) do
				npc.stealth_thingsseen[a:EntIndex()] = a
			end
			
			sightrange = 0
			--hearrange = 0
		end
	end

	if (sightrange*0.75)>playerdist then
		if ply:GetNWFloat('pds_bar', 0) > 0.99 then
			stealthmod.AlertNPC(ply, npc, false)
		else
			stealthmod.NPCInvestigate(npc, ply, false, 2)
		end
		return true
	--elseif (sightrange>playerdist or hearrange^2>playerdist) then
	elseif (sightrange>playerdist) then
		stealthmod.NPCInvestigate(npc, ply, false, 2)
	end
end

local function checkEntityLOS(ent, npc)
	if tobool(stealthmod.CVarCache.ai_disabled) then return -1 end
	-- Variables
	local minsight = tonumber(stealthmod.CVarCache.stealth_minsight)
	local maxsight = tonumber(stealthmod.CVarCache.stealth_maxsight)
	local multiplier = tonumber(stealthmod.CVarCache.stealth_multiplier)

	--local isvisible = CheckNPCLOStoEntity(ent,npc)
	local isvisible = CheckLOSSimple(ent,npc) -- Also works for props and ragdolls.
	local eyesang = npc:EyeAngles() or npc:GetAngles()
	local yawdiff = 0
	
	local eyesobj = npc:LookupAttachment( "eyes" )
	if eyesobj > 0 then eyesang = npc:GetAttachment( eyesobj ).Ang end
	yawdiff = math.abs(math.AngleDifference(eyesang.y,(ent:GetPos()-npc:GetPos()):Angle().y))
	
	local entdist = ent:GetPos():DistToSqr(npc:GetPos())
	local sightrange = maxsight * multiplier
	
	if yawdiff>60 or not isvisible then
		return -1
	end
	
	if (sightrange*sightrange*0.75)>=entdist then
		--stealthmod.NPCInvestigatePos(npc, ent:GetPos(), false, false)
		-- Return distance to target
		return entdist
	end
	return -1
end

local period = 0.25
hook.Add("Initialize", "pdsInit2", function()
	timer.Create("NPCStealthThink",period,0,function() 
		if !tobool(stealthmod.CVarCache.stealth_enabled) then return end
		
		local pds_barAdditive = {}
		for _, ply in pairs(player.GetAll()) do
			pds_barAdditive[ply:EntIndex()] = -math.abs(pds_gravity:GetFloat())
		end

		for k, v in pairs(stealthmod.NPCs) do
			if IsValid(v) then
				for o, p in pairs(v.stealth_MEnemies) do
					if !IsValid(p) then v.stealth_MEnemies[o] = nil end
				end
				
				for o,p in ipairs(player.GetAll()) do
					local isvisible = CheckLOSAdvanced(p,v)
					if isvisible then
						pds_barAdditive[p:EntIndex()] = math.max(pds_barAdditive[p:EntIndex()], npcSensitivity_list[v:GetClass()] or 1)
					end
				end
				
				if table.IsEmpty(v.stealth_MEnemies) then 
					v:SetNWBool("stealth_alerted",false)
				else
					continue -- If the NPC is alerted, nothing below this line is a priority, so don't even bother.
				end
				
				-- Check for suspicious objects, such as corpses.
				local nearestThing = nil
				local nearestDistance = -1
				for o, p in pairs(stealthmod.SuspiciousObjects) do
					if !IsValid(p) then 
						stealthmod.SuspiciousObjects[o] = nil
						continue 
					end
					
					if v.stealth_thingsseen[p:EntIndex()] == p then continue end
					
					local dist = checkEntityLOS(p,v)
					if dist == -1 then continue end
					
					if p:GetClass() == "footprint" then
						local stepper = p:GetOwner()
						if !IsValid(stepper) then continue end
						
						for _, a in ipairs(stepper.Footprints.age) do
							v.stealth_thingsseen[a:EntIndex()] = a -- ignore any footprints older than the first one we found.
							if a == p then break end
						end
						stealthmod.NPCInvestigate(v, stepper.Footprints.age[#stepper.Footprints.age], false, 2) -- instead of going to each print in the trail, go straight to the end.
						break
					end
					
					stealthmod.NPCInvestigate(v, p, false, 2)
				end
				
				for o, p in pairs(stealthmod.InterestingObjects) do
					if !IsValid(p) then 
						stealthmod.InterestingObjects[o] = nil
						continue 
					end
					
					if v.stealth_thingsseen[p:EntIndex()] == p then continue end
					
					local dist = checkEntityLOS(p,v)
					if dist == -1 then continue end
					
					stealthmod.NPCInvestigate(v, p, false, 1)
				end
				
				
				-- When an investigation is started, we handle it here.
				if v.stealth_investigation.status == 1 and v:GetPos():DistToSqr(v.stealth_investigation.targetPos)<10000 then
					v.stealth_investigation.status = 2
					
					if IsValid(v.stealth_investigation.targetEntity) and !v.stealth_investigation.targetEntity:IsPlayer() then
						v.stealth_thingsseen[v.stealth_investigation.targetEntity:EntIndex()] = v.stealth_investigation.targetEntity
					end
					v:SetSchedule( 1 )
					
					timer.Simple(1, function()
						if IsValid(v) and v.stealth_investigation.status == 2 and v.stealth_investigation.priority > 1 then -- make sure he's at step 2, or he'll get stuck.
							v:SetSchedule( SCHED_ALERT_SCAN )
						end
					end)
					
					timer.Create("stealth_NPCEndInvestigation"..v:EntIndex(), 4, 1, function()
						if IsValid(v) and v.stealth_investigation.status >= 2 then -- the NPC may have found something else and investigate further, don't return yet.
							if v.pr_prcontroller then
								v.stealth_investigation.status = 0
							else
								v.stealth_investigation.status = 3
								v.stealth_investigation.priority = 0
								v.stealth_investigation.targetEntity = NULL
								v:SetLastPosition(v.stealth_RoutineToResume.pos)
								v:SetSchedule( SCHED_FORCED_GO_RUN )
							end
						end
					end)
				end
				if v.stealth_investigation.status == 3 and v:GetPos():DistToSqr(v.stealth_RoutineToResume.pos)<2500 then
					
					v:SetSchedule( v.stealth_RoutineToResume.schedule )
					v.stealth_investigation.status = 0
					timer.Simple(1, function()
						if IsValid(v) then
							v:SetAngles(v.stealth_RoutineToResume.ang)
						end
					end)
				end
			else
				stealthmod.NPCs[k] = nil
				-- Send Clients the signal to remove NPC
				net.Start("RemoveNPCfromTable")
					net.WriteEntity(v)
				net.Broadcast()
			end
		end
		

		for idx, additive in pairs(pds_barAdditive) do
			local ply = Entity(idx)
			local add = additive * period
			if add > 0 then
				add = add * tonumber(stealthmod.CVarCache.stealth_multiplier)
			end
			if IsValid(ply) then
				ply:SetNWFloat('pds_bar', math.min(1, math.max(pds_height:GetFloat(), ply:GetNWFloat('pds_bar', 0) + add)))
			end
			// print(ply, additive, add, ply:GetNWFloat('pds_bar', 0))
		end	

	end)
end)



util.AddNetworkString('pdsNpcSensitivityData')
util.AddNetworkString('pdsNpcSensitivityWrite')


net.Receive('pdsNpcSensitivityData', function(len, ply)
	local result = ReadNpcSensitivity()

	local json = util.TableToJSON(result)
	local compressed = util.Compress(json)
	
	// if #compressed > 65530 then
	// 	error("Stealth Mod: Table 'stealth_"..source.."' is too big! Creating a backup (in garrysmod/data/stealth) and resetting!")
		
	// 	if !file.IsDir("stealth/backup", "DATA") then
	// 		file.CreateDir("stealth/backup")
	// 	end
	// 	file.Write("stealth/backup/"..source..".txt", toText)
		
	// 	sql.Query( "DROP TABLE stealth_"..source"; CREATE TABLE stealth_"..source.."("..databaseSetup[source]..")" )
	// end

	net.Start('pdsNpcSensitivityData')
		net.WriteUInt(#compressed, 16)
		net.WriteData(compressed)
	net.Send(ply)

end)


net.Receive('pdsNpcSensitivityWrite', function(len, ply)
	if !ply:IsSuperAdmin() then
		ply:ChatPrint("#stealth_adminwarn")
		return
	end
	
	local datalen = net.ReadUInt(16)
	local compressed = net.ReadData(datalen)
	local decompressed = util.Decompress(compressed)
	local list = util.JSONToTable(decompressed)
	
	WriteNpcSensitivity(list)
	local loadFromDisk = ReadNpcSensitivity()
	local merged = table.Merge(npcSensitivity_default, loadFromDisk)
	table.CopyFromTo(merged, npcSensitivity_list)
end)