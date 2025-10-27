local warnMaterial = Material("pds/warning.png")
local hunters = {}

local pds_hud_size = CreateClientConVar('pds_hud_size', '300', true, false)
local pds_hud_x = CreateClientConVar('pds_hud_x', '0', true, false)
local pds_hud_y = CreateClientConVar('pds_hud_y', '0', true, false)
local pds_hud_alpha = CreateClientConVar('pds_hud_alpha', '0.8', true, false)
local pds_hud_mat = CreateClientConVar('pds_hud_mat', 'pds/warning.png', true, false)
local pds_sound = CreateClientConVar('pds_sound', '', true, false)

local pds_hud_nodraw = CreateClientConVar('pds_hud_nodraw', '0', true, false)
local pds_slient = CreateClientConVar('pds_slient', '0', true, false)

local pds_height = CreateConVar('pds_height', '0', { FCVAR_ARCHIVE, FCVAR_CLIENTCMD_CAN_EXECUTE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE })

cvars.AddChangeCallback("pds_hud_mat", function(name, old, new)
    if new == "" then 
        warnMaterial = Material('error')
    else
        warnMaterial = Material(new)
    end
end)

local bar_lerp = 0
hook.Add("HUDPaint", "pdsHUD", function()
    if pds_hud_nodraw:GetBool() then return end
    local bar = LocalPlayer():GetNWFloat('pds_bar', 0)
    // print(#hunters, bar)
    if bar <= pds_height:GetFloat() + 0.0001 or #hunters > 0 then return end
    
    local size = pds_hud_size:GetFloat()
    local posx = ScrW() * 0.5 - size * 0.5 + pds_hud_x:GetFloat() * ScrW()
    local posy = ScrH() * 0.5 - size * 0.5 + pds_hud_y:GetFloat() * ScrH()

    bar_lerp = Lerp(0.3, bar_lerp, bar)

    surface.SetDrawColor(255, 255, 255, pds_hud_alpha:GetFloat() * 255)
    surface.SetMaterial(warnMaterial)
    surface.DrawTexturedRectUV(posx, posy, size, size * bar_lerp, 0, 0, 1, bar_lerp)
end)


local barLastValue = 0

hook.Add("Initialize", "pdsInit", function()
    timer.Create("pdsListenBarValue", 0.1, 0, function()
        local currentValue = LocalPlayer():GetNWFloat('pds_bar', 0)
        
        if barLastValue == 0 and currentValue ~= barLastValue and !pds_slient:GetBool() and #hunters < 1 then
            local sound = pds_sound:GetString()
            if sound ~= "" then 
                surface.PlaySound(sound)
            end
        end

        barLastValue = LocalPlayer():GetNWFloat('pds_bar', 0)
    end)

    timer.Create("pdsClear", 2, 0, function()
        for i = #hunters, 1, -1 do
            local v = hunters[i]
            if !IsValid(v) then
                table.remove(hunters, i)
            end
        end
    end)
end)

hook.Add("Stealth_NPCAlerted", "pdsGetAlerted", function(ply, npc, silent)
	if IsValid( npc ) and !table.HasValue(hunters, npc) then
		table.insert(hunters, npc)
	end
end)


hook.Add("Stealth_NPCCalmed", "pdsGetCalmed", function(ply, npc)
	if IsValid( npc ) and table.HasValue(hunters, npc) then
		table.RemoveByValue(hunters, npc)
	end
end)



