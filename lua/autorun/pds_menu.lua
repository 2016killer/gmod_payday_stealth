CreateConVar('pds_gravity', '1', { FCVAR_ARCHIVE, FCVAR_CLIENTCMD_CAN_EXECUTE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE })
CreateConVar('pds_height', '0', { FCVAR_ARCHIVE, FCVAR_CLIENTCMD_CAN_EXECUTE, FCVAR_NOTIFY, FCVAR_SERVER_CAN_EXECUTE })

if CLIENT then
	CreateClientConVar('pds_hud_size', '150', true, false)
	CreateClientConVar('pds_hud_x', '0', true, false)
	CreateClientConVar('pds_hud_y', '0', true, false)
	CreateClientConVar('pds_hud_alpha', '0.8', true, false)
	CreateClientConVar('pds_hud_mat', 'pds/warning.png', true, false)
	CreateClientConVar('pds_sound', '', true, false)

	CreateClientConVar('pds_hud_nodraw', '0', true, false)
	CreateClientConVar('pds_slient', '0', true, false)

	hook.Add('PopulateToolMenu', 'pds_menu_client', function()
		spawnmenu.AddToolMenuOption('Options', 
			'Stealth Mod',
			'pds_menu_client', 
			language.GetPhrase('pds.menu.clientname'), '', '', 
			function(panel)
				panel:Clear()
				panel:NumSlider('#pds.hud_size', 'pds_hud_size', 0, 500, 0)
				panel:NumSlider('#pds.hud_x', 'pds_hud_x', -0.5, 0.5, 3)
				panel:NumSlider('#pds.hud_y', 'pds_hud_y', -0.5, 0.5, 3)
				panel:NumSlider('#pds.hud_alpha', 'pds_hud_alpha', 0, 1, 3)

				panel:TextEntry('#pds.hud_mat', 'pds_hud_mat')
				panel:TextEntry('#pds.sound', 'pds_sound')

				panel:CheckBox('#pds.hud_nodraw', 'pds_hud_nodraw')
				panel:CheckBox('#pds.slient', 'pds_slient')
			end
		)
	end)

	hook.Add('PopulateToolMenu', 'pds_menu_server', function()
		spawnmenu.AddToolMenuOption('Options', 
			'Stealth Mod',
			'pds_menu_server', 
			language.GetPhrase('pds.menu.servername'), '', '', 
			function(panel)
				panel:Clear()
				panel:NumSlider('#pds.gravity', 'pds_gravity', 0.1, 5, 2)
				panel:ControlHelp('#pds.help.gravity')

				panel:NumSlider('#pds.height', 'pds_height', 0, 1, 3)
				panel:ControlHelp('#pds.help.height')



				local actualList = {}
				
				local tree = vgui.Create("DTree")
				panel:AddItem(tree)
				tree:SetSize(200, 200)
				
				local curSelectedNode = nil -- keep track of the current selected node so we can delete the "Add" dialog.
				tree.OnNodeSelected = function(self, selNode)
					if curSelectedNode == selNode then return end -- do nothing if we selected the same node twice.
					
					if selNode.textBox then -- We clicked the "+" icon in the "Add" dialog.
						local item = selNode.textBox:GetValue()
						if item == "" then return end -- do nothing if it's empty.
						
						local item2 = selNode.textBox2:GetValue()
						if item2 == "" then return end -- do nothing if it's empty.

						selNode:SetText(item) -- begin replacing this dialog with an actual entry on the list.
						selNode.textBox:Remove()
						selNode.textBox = nil

						selNode.textBox2:Remove()
						selNode.textBox2 = nil

						
						local removeButton = vgui.Create("DButton", selNode)
						--removeButton:AlignRight(-168)
						removeButton:SetSize(18,18)
						removeButton:SetPos(170,0)
						
						removeButton:SetText("")
						removeButton:SetIcon("icon16/delete.png")
						
						local nextnode = selNode
						if selNode.depth == 2 then
							if false then
								actualList[selNode:GetText()] = {}
								--curSelectedNode = selNode
							else
								actualList[selNode:GetText()] = tonumber(item2) or 1
								nextnode = selNode:GetParentNode()
							end
							
							selNode:SetIcon('icon16/user_red.png')
							
							removeButton.DoClick = function()
								selNode:Remove()
								actualList[selNode:GetText()] = nil
							end
						else
							--table.insert(actualList[selNode:GetParentNode():GetText()], selNode:GetText())
							actualList[selNode:GetParentNode():GetText()][selNode:GetText()] = true
							nextnode = selNode:GetParentNode()
							selNode:SetIcon('icon16/user_red.png')
							
							removeButton.DoClick = function()
								selNode:Remove()
								actualList[selNode:GetParentNode():GetText()][selNode:GetText()] = nil
							end
						end
						PrintTable(actualList)
						
						curSelectedNode = nil
						tree:SetSelectedItem(nextnode)
						
						return
					end
					
					if selNode.depth > 1 and true then return end
					if selNode.depth > 2 then return end
					
					if IsValid(curSelectedNode) then
						curSelectedNode.addThingy:Remove()
					end
					
					curSelectedNode = selNode
					local addPanel = selNode:AddNode("Add", "icon16/add.png") -- Add button
					addPanel.depth = selNode.depth + 1
					
					local textField = vgui.Create("DTextEntry", addPanel)
					textField:SetSize(84, 16)
					textField:SetPos(38, 0)
					textField:SetPlaceholderText('')
					addPanel.textBox = textField
					
					selNode:SetExpanded(true)
					selNode.addThingy = addPanel

					local textField2 = vgui.Create("DTextEntry", addPanel)
					textField2:SetSize(84, 16)
					textField2:SetPos(122, 0)
					textField2:SetPlaceholderText('')
					textField2:SetValue('1')
					addPanel.textBox2 = textField2
				end
				
				local rootitem = tree:AddNode(language.GetPhrase('#pds.sensitivity'), 'icon16/user_red.png')
				rootitem.depth = 1
				
				local LoadFileButton = panel:Button(language.GetPhrase("stealth_list.reloadfromdisk"))
				
				LoadFileButton.DoClick = function()
					net.Start("pdsNpcSensitivityData") --Ask the server to read the list from disk and send it to the client.
					net.SendToServer()
				end

				net.Receive("pdsNpcSensitivityData", function() -- Receive the list from the server.
					local datalen = net.ReadUInt(16)
					local data = net.ReadData(datalen)
					local decompressed = util.Decompress(data)
					
					actualList = util.JSONToTable(decompressed)
					
					rootitem:Remove()
					rootitem = tree:AddNode('npc', 'icon16/user_red.png')
					rootitem.depth = 1
					
					for k, v in pairs(actualList) do
						local node = rootitem:AddNode(k, 'icon16/user_red.png')
						node.depth = 2
						
						local removeButton = vgui.Create("DButton", node)
						removeButton:SetSize(18,18)
						removeButton:SetPos(170,0)
						--removeButton:AlignRight(-168)
						
						removeButton:SetText("")
						removeButton:SetIcon("icon16/delete.png")
						removeButton.DoClick = function()
							node:Remove()
							actualList[node:GetText()] = nil
						end
						
						if type(v) == "table" then
							for a, b in pairs(v) do
								local subnode = node:AddNode(a, 'icon16/user_red.png')
								subnode.depth = 3
								
								local subremoveButton = vgui.Create("DButton", subnode)
								subremoveButton:SetSize(18,18)
								subremoveButton:SetPos(170,0)
								--subremoveButton:AlignRight(-168)
								
								subremoveButton:SetText("")
								subremoveButton:SetIcon("icon16/delete.png")
								subremoveButton.DoClick = function()
									subnode:Remove()
									actualList[node:GetText()][subnode:GetText()] = nil
								end
							end
						end
					end
					rootitem:ExpandRecurse(true)
					tree:SetSelectedItem(rootitem)
				end)
				
				
				local saveButton = vgui.Create("DButton")
				panel:AddItem(saveButton)
				saveButton:SetSize(150, 20)
				saveButton:SetText(language.GetPhrase("spawnmenu.savechanges"))
				saveButton.DoClick = function()
					if !LocalPlayer():IsSuperAdmin() then
						chat.AddText( language.GetPhrase("stealth_adminwarn") )
						return
					end
					
					local toJSON = util.TableToJSON(actualList)
					local compressed = util.Compress(toJSON)
					
					if #compressed > 65500 then
						chat.AddText( language.GetPhrase("stealth_netlimitwarn") )
						surface.PlaySound("buttons/button10.wav")
						return
					end
					
					net.Start("pdsNpcSensitivityWrite")
						net.WriteUInt(#compressed, 16)
						net.WriteData(compressed)
					net.SendToServer()
				end
				

				--Have the list loaded as soon as the menu opens.
				net.Start("pdsNpcSensitivityData")
				net.SendToServer()
				
				--return tree
				panel:ControlHelp('#pds.help.sensitivity')
			end
		)
	end)
end




