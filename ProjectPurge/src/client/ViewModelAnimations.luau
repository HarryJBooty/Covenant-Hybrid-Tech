-- viewmodel arm anims (idle, dash dirs, grapple)

local ViewModelAnimations = {} 

local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local LastGrappleTrack: AnimationTrack? = nil 
local LastIdleTrack: AnimationTrack? = nil 
local LastDashTrack: AnimationTrack? = nil 

function ViewModelAnimations.DashStop(self, ViewModel)
    if LastDashTrack then
        LastDashTrack:Stop(0.5)
        LastDashTrack = nil
    end
    
    ViewModelAnimations:PlayIdle(ViewModel)
end

function ViewModelAnimations.PlayDash(self, ViewModel, Direction, WeaponType)
    print(WeaponType)
    local AnimationId 
    if WeaponType == "Empty" then 
        local LocalsMap = MovementConfig.Dash.LocalAnimations 
        AnimationId = LocalsMap[Direction]
        print("Empty confirmed!") 
    elseif WeaponType == "Melee" then
        print("melee confirrmed!")
        local LocalsMap = MovementConfig.Dash.SwordAnimations
        AnimationId = LocalsMap[Direction]
    end 

    if not AnimationId then return end 

    local AnimationController = ViewModel:FindFirstChildOfClass("AnimationController")
    if not AnimationController then return end 
    local Animator = AnimationController:FindFirstChildOfClass("Animator")
    if not Animator then return end 

    if LastDashTrack then 
        LastDashTrack:Stop(0.5)
    end 

    local ThisAnimation = Instance.new("Animation")
    ThisAnimation.AnimationId = AnimationId

    LastDashTrack = Animator:LoadAnimation(ThisAnimation)
    LastDashTrack.Looped = false
    LastDashTrack.Priority = Enum.AnimationPriority.Action
    LastDashTrack:Play(0.05, 1, 1)
    
end 

function ViewModelAnimations.PlayIdle(self, ViewModel)
    print("Play idle called!")
    local AnimtionID = MovementConfig.Walk.LocalAnimation
    if not AnimtionID then return end 
    print("Idle anim", AnimtionID)

    local AnimationController = ViewModel:FindFirstChildOfClass("AnimationController")
    
    local Animator = AnimationController:FindFirstChildOfClass("Animator")
    if not Animator then return end 

    if  LastIdleTrack then
        LastIdleTrack:Stop(0.5)
    end

    local ThisAnimation = Instance.new("Animation")
    ThisAnimation.AnimationId = AnimtionID

    LastIdleTrack = Animator:LoadAnimation(ThisAnimation)
    LastIdleTrack.Looped = true
    LastIdleTrack.Priority = Enum.AnimationPriority.Action
    LastIdleTrack:Play(0.05, 1, 1)
end 

function ViewModelAnimations.Grapple(self, ViewModel, WeaponType)
    local AnimiationID 

    if WeaponType == "Empty" then
        AnimiationID = MovementConfig.Grapple.LocalAnimation
    elseif WeaponType == "Melee" then
        AnimiationID = MovementConfig.Grapple.SwordAnimation
    elseif WeaponType == "Gun" then
        AnimiationID = MovementConfig.Grapple.GunAnimation
    else
        AnimiationID = MovementConfig.Grapple.LocalAnimation
    end

    if not AnimiationID then return end 

    local AnimationController = ViewModel:FindFirstChildOfClass("AnimationController")
    
    local Animator = AnimationController:FindFirstChildOfClass("Animator")
    if not Animator then return end 

    if LastGrappleTrack then
        LastGrappleTrack:Stop(0.5)
    end

    local ThisAnimation = Instance.new("Animation")
    ThisAnimation.AnimationId = AnimiationID

    LastGrappleTrack = Animator:LoadAnimation(ThisAnimation)
    LastGrappleTrack.Looped = false
    LastGrappleTrack.Priority = Enum.AnimationPriority.Action
    LastGrappleTrack:Play(0.05, 1, 1)
end

function ViewModelAnimations.GrappleStop(self, ViewModel)
    if LastGrappleTrack then
        LastGrappleTrack:Stop(0.5)
        LastGrappleTrack = nil
    end
    
    ViewModelAnimations:PlayIdle(ViewModel)
end

return ViewModelAnimations
