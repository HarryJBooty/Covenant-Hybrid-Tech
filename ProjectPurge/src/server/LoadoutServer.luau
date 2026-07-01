-- builds the teams from LoadoutConfig and hands each player their team loadout on spawn.
-- tools are cloned out of ServerStorage.Tools into the player's Backpack with a Slot attribute
-- (1 = primary, 2 = secondary) so the client HUD + equip keybinds know where each one belongs.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Teams = game:GetService("Teams")

local LoadoutConfig = require(game.ReplicatedStorage.Shared.LoadoutConfig)
local WeaponsConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local LoadoutServer = {}

-- find the tool source folder, creating an empty one as a fallback so we never hard-error if the
-- studio-side folder hasn't been made yet (tools dropped in there later still work).
local function GetToolsFolder()
	local folder = ServerStorage:FindFirstChild("Tools")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Tools"
		folder.Parent = ServerStorage
		warn("LoadoutServer: ServerStorage.Tools was missing; created an empty one. Put loadout tools inside it.")
	end
	return folder
end

local ToolsFolder = GetToolsFolder()

-- create any team that doesn't exist yet, and keep its colour/auto-assign in sync with the config
local function EnsureTeams()
	for teamName, data in LoadoutConfig.Teams do
		local team = Teams:FindFirstChild(teamName)
		if not team then
			team = Instance.new("Team")
			team.Name = teamName
			team.Parent = Teams
		end
		team.AutoAssignable = data.AutoAssignable == true
		if data.TeamColor then
			team.TeamColor = data.TeamColor
		end
	end
end

-- seed ammo attributes from WeaponsConfig so the HUD shows the right numbers before the tool is
-- ever equipped (the sword/server systems still own decrementing it during play)
local function ApplyAmmoAttributes(tool : Tool)
	local config = WeaponsConfig[tool.Name]
	if not config or config.Ammo == nil then
		return
	end

	if tool:GetAttribute("MaxAmmo") == nil then
		tool:SetAttribute("MaxAmmo", config.Ammo)
	end
	if tool:GetAttribute("Ammo") == nil then
		tool:SetAttribute("Ammo", config.Ammo)
	end
end

local function ApplyTypeAttributes(tool : Tool) 
	local config = WeaponsConfig[tool.Name]
	if not config or config.SubType == nil then return end 

	if tool:GetAttribute("SubType") == nil then 
		tool:SetAttribute("SubType", config.SubType)
	end
end 

local function GiveTool(player : Player, toolName : string?, slot : number)
	if not toolName then
		return
	end

	local template = ToolsFolder:FindFirstChild(toolName)
	if not template or not template:IsA("Tool") then
		warn(string.format("LoadoutServer: tool %q not found in ServerStorage.Tools", toolName))
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local tool = template:Clone()
	tool:SetAttribute("Slot", slot)
	ApplyAmmoAttributes(tool)
	ApplyTypeAttributes(tool)
	tool.Parent = backpack
end

-- wipe any tools currently on the player so a respawn / re-grant doesn't stack duplicates
local function ClearTools(player : Player)
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
end

local function GiveLoadout(player : Player)
	local teamName = player.Team and player.Team.Name
	local loadout = LoadoutConfig.GetLoadout(teamName)

	ClearTools(player)
	GiveTool(player, loadout.Primary, 1)
	GiveTool(player, loadout.Secondary, 2)
end

local function OnCharacterAdded(player : Player)
	-- defer so Roblox has finished resetting the Backpack from StarterGear before we fill it,
	-- otherwise our freshly granted tools can be cleared out from under us
	task.defer(function()
		if player.Parent then
			GiveLoadout(player)
		end
	end)
end

local function HookPlayer(player : Player)
	player.CharacterAdded:Connect(function()
		OnCharacterAdded(player)
	end)

	if player.Character then
		OnCharacterAdded(player)
	end
end

EnsureTeams()

Players.PlayerAdded:Connect(HookPlayer)

-- catch players who joined before this module finished requiring (e.g. live reload)
for _, player in Players:GetPlayers() do
	HookPlayer(player)
end

return LoadoutServer
