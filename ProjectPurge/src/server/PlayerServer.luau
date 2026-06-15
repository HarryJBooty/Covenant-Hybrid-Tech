-- sets player health on spawn from config

local PlayerService = game:GetService("Players")
local ShieldConfig = require(game.ReplicatedStorage.Shared.ShieldConfig)

local PlayerServer = {}

local function SetHealth(Character)
    if not Character then
        return 
    end

    local Humanoid : Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return end 

    Humanoid.Health = ShieldConfig.DEFAULT_HEALTH
    Humanoid.MaxHealth = ShieldConfig.DEFAULT_HEALTH
end

local function OnCharacterAdded(character)
    print("new player char")
    SetHealth(character)
end

PlayerService.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(OnCharacterAdded)
end)

return PlayerServer
