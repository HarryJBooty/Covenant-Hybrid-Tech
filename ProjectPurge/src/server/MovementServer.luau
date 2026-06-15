-- server side dash charges, client does the actual movement

MovementServer = {}
local PlayerService = game:GetService("Players")
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local RemotesFolder = game.ReplicatedStorage:FindFirstChild("Remotes")

local DashRemote : RemoteEvent = RemotesFolder:FindFirstChild("Dash")

-- client fired dash, spend a charge and regen later
DashRemote.OnServerEvent:Connect(function(player)
    local Character = player.Character
    local Dashes = Character:GetAttribute("Dashes")

    Character:SetAttribute("Dashes", Dashes - 1)
    task.delay(MovementConfig.Dash.Recharge, function()
        local CurrentDashes = Character:GetAttribute("Dashes")
        Character:SetAttribute("Dashes", CurrentDashes + 1)
    end)
end)

local function OnCharacterAdded(character) 
    if not character then return end 

    character:SetAttribute("Dashes", MovementConfig.Dash.Uses)
end 

PlayerService.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(OnCharacterAdded)
end)

-- players already in game when script loads
for _, Player in PlayerService:GetPlayers() do
    Player.CharacterAdded:Connect(OnCharacterAdded)
end

return MovementServer
