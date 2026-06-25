-- 3rd person character anims (idle, swing, sprint)

local AnimationController = {}
local PlayerService = game:GetService("Players")
local Player = PlayerService.LocalPlayer
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local CurrentIdleTrack : AnimationTrack
local CurrentSwingTrack 
local CurrentLungeTrack 

function AnimationController.ClearSwingAnim()
    -- stop one-shot swing so idle can resume
    if CurrentSwingTrack then
        CurrentSwingTrack:Stop(0.2)
        CurrentSwingTrack:Destroy()
        CurrentSwingTrack = nil
    end
end 

local function ClearIdleAnim()
    if CurrentIdleTrack then
        CurrentIdleTrack:Stop(0.2)
        CurrentIdleTrack:Destroy()
        CurrentIdleTrack = nil
    end
end 

function AnimationController.ClearOnDeath()
    AnimationController.ClearSwingAnim()
    AnimationController.StopSwordLunge()
    ClearIdleAnim()
end

function AnimationController.PlaySwordSwing()
    local Character = Player.Character
    local Humanoid = Character:FindFirstChild("Humanoid")
    if not Humanoid then return end 
    if not Humanoid then return nil end  
    local Animatior = Humanoid:FindFirstChildOfClass("Animator")
    if not Animatior then return end 

    local SwingAnimation = Instance.new("Animation")
    SwingAnimation.AnimationId = WeaponConfig["Energy Sword"].Animations.Swing

    CurrentSwingTrack = Animatior:LoadAnimation(SwingAnimation)
    CurrentSwingTrack.Priority = Enum.AnimationPriority.Action3
    CurrentSwingTrack.Looped = false
    CurrentSwingTrack:Play()

    return CurrentSwingTrack
end

-- looped pose held for the duration of a lunge, stopped by StopSwordLunge
function AnimationController.PlaySwordLunge()
    if CurrentLungeTrack then return CurrentLungeTrack end -- already looping

    local Character = Player.Character
    local Humanoid = Character and Character:FindFirstChild("Humanoid")
    if not Humanoid then return end 
    local Animatior = Humanoid:FindFirstChildOfClass("Animator")
    if not Animatior then return end 

    local LungeAnimation = Instance.new("Animation")
    LungeAnimation.AnimationId = WeaponConfig["Energy Sword"].Animations.Lunge

    CurrentLungeTrack = Animatior:LoadAnimation(LungeAnimation)
    CurrentLungeTrack.Priority = Enum.AnimationPriority.Action2
    CurrentLungeTrack.Looped = true
    CurrentLungeTrack:Play()

    return CurrentLungeTrack
end

function AnimationController.StopSwordLunge()
    if CurrentLungeTrack then
        CurrentLungeTrack:Stop(0.15)
        CurrentLungeTrack:Destroy()
        CurrentLungeTrack = nil
    end
end

function AnimationController.PlayIdle(self, Tool : Tool)
    ClearIdleAnim()
    local Character = Player.Character
    local Humanoid = Character:FindFirstChild("Humanoid")
    if not Humanoid then return end 
    if not Humanoid then return nil end  
    local Animatior = Humanoid:FindFirstChildOfClass("Animator")
    if not Animatior then return end 

    local Animation = Instance.new("Animation")

    if Tool == "Empty" then  
        return 
    elseif Tool == "Melee" then 
        Animation.AnimationId = WeaponConfig["Energy Sword"].Animations.Idle
    end 

    CurrentIdleTrack = Animatior:LoadAnimation(Animation)
    CurrentIdleTrack.Priority = Enum.AnimationPriority.Idle
    CurrentIdleTrack.Looped = true
    CurrentIdleTrack:Play()

    return CurrentIdleTrack
end

function AnimationController.PlaySprint(self, Humanoid: Humanoid, Tool : Tool)
    -- todo: play sprint track from MovementConfig.Sprint
end

function AnimationController.StopSprint(self, Humanoid : Humanoid, Tool : Tool)
    AnimationController:PlayIdle(Tool)
end 

Player.CharacterRemoving:Connect(function()
    AnimationController.ClearOnDeath()
end)

return AnimationController
