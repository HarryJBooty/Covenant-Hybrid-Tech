-- for local sounds generally 

local PlayerService = game:GetService("Players")
local Player = PlayerService.LocalPlayer

local SFXController = {}
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)

local GrappleSoundEffect = nil 

local function CleanUpConnections()
    if GrappleSoundEffect then
        GrappleSoundEffect:Destroy()
        GrappleSoundEffect = nil 
    end
end 

function SFXController.PlayGrappleShot(self, character)
    if not character then return end 

    -- reuse one sound instance per life
    if not GrappleSoundEffect then
        local GrappleSFXTemplate = MovementConfig.Grapple.SoundEffect
        GrappleSoundEffect = Instance.new("Sound")
        GrappleSoundEffect.SoundId = GrappleSFXTemplate
        GrappleSoundEffect.Parent = character
    end
    GrappleSoundEffect:Play() 
end

Player.CharacterRemoving:Connect(function(character)
    CleanUpConnections()
end)

return SFXController