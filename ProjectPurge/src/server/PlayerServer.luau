-- sets player health on spawn from config

local PlayerService = game:GetService("Players")
local ShieldConfig = require(game.ReplicatedStorage.Shared.ShieldConfig)
local RemotesFolder = game.ReplicatedStorage:WaitForChild("Remotes")

local PlayerServer = {}

-- relay each player's look pitch to everyone else so they can pose the body the same way
local CharacterLookRemote = RemotesFolder:FindFirstChild("CharacterLook")
if not CharacterLookRemote then
    CharacterLookRemote = Instance.new("RemoteEvent")
    CharacterLookRemote.Name = "CharacterLook"
    CharacterLookRemote.Parent = RemotesFolder
end

CharacterLookRemote.OnServerEvent:Connect(function(player, pitch)
    if pitch ~= nil and typeof(pitch) ~= "number" then return end 
    for _, other in PlayerService:GetPlayers() do
        if other ~= player then
            CharacterLookRemote:FireClient(other, player, pitch)
        end
    end
end)

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
