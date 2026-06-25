-- viewmodel arm anims (idle, dash dirs, grapple)

local ViewModelAnimations = {} 

local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local WeaponsConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)
local LastGrappleTrack: AnimationTrack? = nil 
local LastIdleTrack: AnimationTrack? = nil 
local LastDashTrack: AnimationTrack? = nil 
local LastSwingTrack: AnimationTrack? = nil 
local LastLungeTrack: AnimationTrack? = nil 
local LastLungeFinisherTrack: AnimationTrack? = nil


function ViewModelAnimations.LungeFinisher(self, ViewModel)
    if LastLungeFinisherTrack then
        LastLungeFinisherTrack:Stop()
        LastLungeFinisherTrack = nil
    end

    local AnimationController = ViewModel:FindFirstChildOfClass("AnimationController")
    if not AnimationController then return end 
    local Animator = AnimationController:FindFirstChildOfClass("Animator")
    if not Animator then return end 

    local ThisAnimation = Instance.new("Animation")
    ThisAnimation.AnimationId = WeaponsConfig["Energy Sword"].ViewportAnimations.LungeFinish
    LastLungeFinisherTrack = Animator:LoadAnimation(ThisAnimation)
    LastLungeFinisherTrack.Priority = Enum.AnimationPriority.Action3
    LastLungeFinisherTrack:Play(0.5, 1, 1)
end     

function ViewModelAnimations.DisableLunge(self, ViewModel) 
    if LastLungeTrack then
        LastLungeTrack:Stop()
        LastLungeTrack = nil 
    end   

    ViewModelAnimations:LungeFinisher(ViewModel)
end 

-- abruptly drop the lunge pose without the arrival flourish (used when the lunge is cancelled, e.g. the
-- target dashed clear or the sword was unequipped mid-lunge)
function ViewModelAnimations.CancelLunge(self, ViewModel)
    if LastLungeFinisherTrack then
        LastLungeFinisherTrack:Stop(0)
        LastLungeFinisherTrack = nil
    end

    if LastLungeTrack then
        LastLungeTrack:Stop(0)
        LastLungeTrack = nil
    end
end 


function ViewModelAnimations.EnableLunge(self, ViewModel) 
    if LastLungeTrack then
        LastLungeTrack:Stop()
        LastLungeTrack = nil 
    end    

    local AnimationController = ViewModel:FindFirstChildOfClass("AnimationController")
    if not AnimationController then return end 
    local Animator = AnimationController:FindFirstChildOfClass("Animator")
    if not Animator then return end 

    local ThisAnimation = Instance.new("Animation")
    ThisAnimation.AnimationId = WeaponsConfig["Energy Sword"].ViewportAnimations.Lunge
    LastLungeTrack = Animator:LoadAnimation(ThisAnimation)
    LastLungeTrack.Looped = true
    LastLungeTrack.Priority = Enum.AnimationPriority.Action2
    LastLungeTrack:Play(0.5, 1, 1)
end 

function ViewModelAnimations.SwingSword(self, ViewModel) 
    if LastSwingTrack then
        LastSwingTrack:Stop(0.5)
        LastSwingTrack = nil
    end

    local AnimationController = ViewModel:FindFirstChildOfClass("AnimationController")
    if not AnimationController then return end 
    local Animator = AnimationController:FindFirstChildOfClass("Animator")
    if not Animator then return end 

    local ThisAnimation = Instance.new("Animation")
    ThisAnimation.AnimationId = WeaponsConfig["Energy Sword"].ViewportAnimations.Swing
    LastSwingTrack = Animator:LoadAnimation(ThisAnimation)
    LastSwingTrack.Priority = Enum.AnimationPriority.Action3
    LastSwingTrack:Play(0.5, 1, 1)
end 

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
    LastIdleTrack.Priority = Enum.AnimationPriority.Idle
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
    LastGrappleTrack.Priority = Enum.AnimationPriority.Movement
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
