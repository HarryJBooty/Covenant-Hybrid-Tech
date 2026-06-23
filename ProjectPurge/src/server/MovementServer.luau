-- server side dash charges, client does the actual movement

MovementServer = {}
local PlayerService = game:GetService("Players")
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local RemotesFolder = game.ReplicatedStorage:FindFirstChild("Remotes")

local DashRemote : RemoteEvent = RemotesFolder:FindFirstChild("Dash")

-- relays so everyone EXCEPT the grappler draws the third-person beam locally; the grappler keeps
-- their own client beams and never sees this one (no overlap, no per-player hiding needed)
local function EnsureRemote(name : string) : RemoteEvent
    local Remote = RemotesFolder:FindFirstChild(name)
    if not Remote then
        Remote = Instance.new("RemoteEvent")
        Remote.Name = name
        Remote.Parent = RemotesFolder
    end
    return Remote
end

local GrappleStartRemote = EnsureRemote("GrappleBeamStart")
local GrappleStopRemote = EnsureRemote("GrappleBeamStop")

GrappleStartRemote.OnServerEvent:Connect(function(player, hitPart, targetPosition)
    if typeof(targetPosition) ~= "Vector3" then return end 
    if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then return end 
    for _, other in PlayerService:GetPlayers() do
        if other ~= player then
            GrappleStartRemote:FireClient(other, player, hitPart, targetPosition)
        end
    end
end)

GrappleStopRemote.OnServerEvent:Connect(function(player)
    for _, other in PlayerService:GetPlayers() do
        if other ~= player then
            GrappleStopRemote:FireClient(other, player)
        end
    end
end)

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
