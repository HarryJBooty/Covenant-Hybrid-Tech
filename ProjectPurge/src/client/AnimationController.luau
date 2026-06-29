-- 3rd person character anims (idle, swing, sprint)

local AnimationController = {}
local PlayerService = game:GetService("Players")
local Player = PlayerService.LocalPlayer
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local CurrentIdleTrack : AnimationTrack
local CurrentSwingTrack 
local CurrentLungeTrack 
local CurrentDashTrack

-- maps the dash CardinalDirection to the key in MovementConfig.Dash.DashAnimations
local DASH_ANIM_DIRECTIONS = {
    Forward = "Front",
    Backwards = "Back",
    Left = "Left",
    Right = "Right",
}

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
    AnimationController:StopDash()
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

-- play the directional dash body anim (id from MovementConfig.Dash.DashAnimations) for this dash
function AnimationController.PlayDash(self, direction : string)
    local key = DASH_ANIM_DIRECTIONS[direction]
    if not key then return end

    local DashAnimations = MovementConfig.Dash.DashAnimations
    local animId = DashAnimations and DashAnimations[key]
    if not animId or animId == "" then return end

    local Character = Player.Character
    local Humanoid = Character and Character:FindFirstChild("Humanoid")
    if not Humanoid then return end
    local Animatior = Humanoid:FindFirstChildOfClass("Animator")
    if not Animatior then return end

    if CurrentDashTrack then
        CurrentDashTrack:Stop(0)
        CurrentDashTrack:Destroy()
        CurrentDashTrack = nil
    end

    local DashAnimation = Instance.new("Animation")
    DashAnimation.AnimationId = animId

    local Track = Animatior:LoadAnimation(DashAnimation)
    Track.Priority = Enum.AnimationPriority.Action
    Track.Looped = false
    CurrentDashTrack = Track

    local Speed = MovementConfig.Dash.AnimationSpeed or 1
    Track:Play(0.1, 1, Speed)

    -- one-shot: let it run its full length and clean itself up when it finishes, so the short
    -- velocity burst ending no longer cuts the animation off early
    Track.Stopped:Once(function()
        if CurrentDashTrack == Track then
            CurrentDashTrack = nil
        end
        Track:Destroy()
    end)

    return Track
end

function AnimationController.StopDash(self)
    if CurrentDashTrack then
        CurrentDashTrack:Stop(0.1)
        CurrentDashTrack:Destroy()
        CurrentDashTrack = nil
    end
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
