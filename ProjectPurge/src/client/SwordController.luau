-- energy sword: hitbox overlap, lock-on cursor, ots camera

local SwordController = {} 
local HttpService = game:GetService("HttpService")
local StarterPack = game:GetService("StarterPack")
local UIS = game:GetService("UserInputService")
local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)
local ViewController = require(script.Parent.ViewController)
local AnimationController = require(script.Parent.AnimationController)
local PlayerController = require(script.Parent.PlayerController)
local SwingRemote : RemoteEvent = game.ReplicatedStorage.Remotes.SwordSwing 
local SetClashRemote : RemoteEvent = game.ReplicatedStorage.Remotes.SetClash 
local LungeHitRemote : RemoteEvent = game.ReplicatedStorage.Remotes:WaitForChild("LungeHit")
local ClashKnockbackRemote : RemoteEvent = game.ReplicatedStorage.Remotes:WaitForChild("ClashKnockback")
local SwordSwungRemote : RemoteEvent = game.ReplicatedStorage.Remotes:WaitForChild("SwordSwung")
local CancelLungeRemote : RemoteEvent = game.ReplicatedStorage.Remotes:WaitForChild("CancelLunge")

local SoundsFolder = game.ReplicatedStorage:FindFirstChild("Sounds")
local EquipSoundTemplate = SoundsFolder and SoundsFolder:FindFirstChild("Energy Sword Equip")


local LungeLoopConnection : RBXScriptConnection
local TargetingLoopConnection : RBXScriptConnection
local KnockbackConnection : RBXScriptConnection?
local ActiveLungeFinish : (() -> ())? = nil -- ends the in-progress lunge; lets a clash stop both lunges together
local Cursor : ImageLabel
local WeaponData = {} 
-- TODO: sword lunge — see Lunge() below
local LungeData = {
    CanLunge = false, -- true when targeting loop finds a humanoid under cursor
    CurrentTarget = nil, -- model to dash toward
}
local CamOffsetInitial = nil 
local Connections : RBXScriptConnection = {} 
local SwingActiveFlag = false


local Player = PlayerService.LocalPlayer
local Character = Player.Character
local PlayerGui = Player.PlayerGui

local function CastDebugSwingPart(Hitbox : BasePart)
    -- red box shows hitbox for tuning, remove later
    local Size = Hitbox.Size
    local HitboxVector = Hitbox.CFrame

    local Debugpart = Instance.new("Part")
    Debugpart.Anchored = true
    Debugpart.Color = Color3.fromRGB(255, 0, 0)
    Debugpart.Transparency = 0.5    
    Debugpart.CanCollide = false
    Debugpart.Parent = game.Workspace
    Debugpart.CFrame = HitboxVector

    task.wait(0.5)
    Debugpart:Destroy() 
end 

local function Swing()
    print("Swinging")
    local Character = Player.Character
    local Camera = Workspace.CurrentCamera
    if not Character then return end 

    local Humanoid = Character:FindFirstChild("Humanoid")

    if not Humanoid then return end
    if Humanoid.Health <= 0 then return end 

    local Sword = Character:FindFirstChildOfClass("Tool")
    if not Sword then return end 
    local HitBox : BasePart = Sword:FindFirstChild("Hitbox", true)
    if not HitBox then return end 

    local OverlapParams = OverlapParams.new()
    OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
    OverlapParams.FilterDescendantsInstances = {
        Character,
        Camera
    }
    OverlapParams.MaxParts = 50
    local AlreadyHit = {} -- one hit per humanoid per swing

    local HitDetectionConnection : RBXScriptConnection
    local SwingRuntime = 0.3
    local StartTime = os.clock()
    SwingActiveFlag = true
    AnimationController.PlaySwordSwing()
    SwordSwungRemote:FireServer() -- woosh plays globally
    HitDetectionConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if os.clock() - StartTime > SwingRuntime then
            table.clear(AlreadyHit)
            HitDetectionConnection:Disconnect()
            task.delay(0.5, function()
                SwingActiveFlag = false
            end)
            return 
        end

        local HitParts = workspace:GetPartBoundsInBox(HitBox.CFrame, HitBox.Size, OverlapParams)
        for _, PotentialHit in HitParts do
            local Model = PotentialHit:FindFirstAncestorOfClass("Model")
            local Humanoid = Model and Model:FindFirstChild("Humanoid")
            if Humanoid and not AlreadyHit[Humanoid] then
                AlreadyHit[Humanoid] = true
                print("Hit:", Model.Name)
                SwingRemote:FireServer(Model, Humanoid, WeaponData)
            end
        end
        --CastDebugSwingPart(HitBox)
    end)

end 

local function HasLungeLineOfSight(origin: Vector3, targetModel: Model, targetPart: BasePart, excludeList: { Instance }): boolean
    local offset = targetPart.Position - origin
    local distance = offset.Magnitude
    if distance < 0.01 then
        return true
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList
    params.IgnoreWater = true

    local result = Workspace:Raycast(origin, offset, params)
    if not result then
        return true
    end

    local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
    return hitModel == targetModel
end

local function StartLungeLoop(Character, Target)
    if LungeLoopConnection then
        LungeLoopConnection:Disconnect()
        LungeLoopConnection = nil
    end

    if not Character or not Target or not Target:IsA("Model") then
        return
    end

    local hrp = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local humanoid = Character:FindFirstChildOfClass("Humanoid")
    local targetHrp = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
    local targetHumanoid = Target:FindFirstChildOfClass("Humanoid")

    SetClashRemote:FireServer(true, Target) -- pass the target so they can dash-evade this lunge

    if not hrp or not humanoid or not targetHrp or not targetHumanoid then
        return
    end
    if humanoid.Health <= 0 or targetHumanoid.Health <= 0 then
        return
    end

    AnimationController.PlaySwordLunge() -- looped pose held while dashing in

    local ARRIVAL_DISTANCE = 5
    local INITIAL_SPEED = 24
    local ACCELERATION = 120
    local MAX_SPEED = 72
    local MAX_DURATION = 5

    local startTime = os.clock()
    local currentSpeed = INITIAL_SPEED
    local losExclude = { Character, Workspace.CurrentCamera }
    local finished = false

    local function finishLunge()
        if finished then return end -- may be called by arrival, a stop condition, or a clash; run once
        finished = true
        if ActiveLungeFinish == finishLunge then
            ActiveLungeFinish = nil
        end

        if LungeLoopConnection then
            LungeLoopConnection:Disconnect()
            LungeLoopConnection = nil
        end

        AnimationController.StopSwordLunge()

        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
        end

        -- clash flag only lasts for the duration of the lunge
        SetClashRemote:FireServer(false)

        LungeData.CanLunge = false
        LungeData.CurrentTarget = nil
        if Cursor then
            Cursor.ImageColor3 = Color3.new(255, 255, 255)
        end
    end

    ActiveLungeFinish = finishLunge -- expose so a server clash can end this lunge in sync

    local function shouldStopLunge(): boolean
        if not Character.Parent or Player.Character ~= Character then
            return true
        end

        if not hrp.Parent or not targetHrp.Parent then
            return true
        end

        if humanoid.Health <= 0 or targetHumanoid.Health <= 0 then
            return true
        end

        local tool = Character:FindFirstChildOfClass("Tool")
        if not tool or tool:GetAttribute("Type") ~= "Melee" then
            return true
        end

        if os.clock() - startTime > MAX_DURATION then
            return true
        end

        local distance = (targetHrp.Position - hrp.Position).Magnitude
        if distance <= ARRIVAL_DISTANCE then
            -- lunge connected: swing anim + let the server damage the target or resolve a clash
            AnimationController.PlaySwordSwing()
            SwordSwungRemote:FireServer() -- woosh plays globally
            LungeHitRemote:FireServer(Target, targetHumanoid)
            return true
        end

        local losOrigin = hrp.Position + Vector3.new(0, 1.5, 0)
        if not HasLungeLineOfSight(losOrigin, Target, targetHrp, losExclude) then
            return true
        end

        return false
    end

    LungeLoopConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if shouldStopLunge() then
            finishLunge()
            return
        end

        local offset = targetHrp.Position - hrp.Position
        local distance = offset.Magnitude
        if distance <= ARRIVAL_DISTANCE then
            finishLunge()
            return
        end

        -- Face the target so the screen centre stays on them without moving the camera.
        local flatLook = Vector3.new(offset.X, 0, offset.Z)
        if flatLook.Magnitude > 0.01 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
        end

        currentSpeed = math.min(currentSpeed + ACCELERATION * deltaTime, MAX_SPEED)
        hrp.AssemblyLinearVelocity = offset.Unit * currentSpeed
    end)
end 


local function Lunge() 
    local Character = Player.Character
    if not Character then return end

    local Humanoid : Humanoid = Character:FindFirstChild("Humanoid")
    if not Humanoid then return end 
    if Humanoid.Health <= 0 then return end 

    if LungeData.CurrentTarget and LungeData.CanLunge then
        StartLungeLoop(Character, LungeData.CurrentTarget) 
    end

end 

local function SetTargetAquired(state, Target : Instance)

    if state then  
        LungeData.CanLunge = true
        LungeData.CurrentTarget = Target
        Cursor.ImageColor3 = Color3.fromRGB(255, 0, 0) -- red = locked
    else
        LungeData.CanLunge = false
        LungeData.CurrentTarget = nil
        Cursor.ImageColor3 = Color3.new(255, 255, 255)
    end 

end

local function ToggleTargetingLoop(state : boolean)
    local RayLength = WeaponConfig["Energy Sword"].LungeDistance
    local SwordRayParams = RaycastParams.new()
    SwordRayParams.FilterType = Enum.RaycastFilterType.Exclude
    SwordRayParams.FilterDescendantsInstances = {
        Player.Character,
        workspace.CurrentCamera
    }
    SwordRayParams.IgnoreWater = true
    if state == true then
            -- ray from the exact screen centre each frame (matches the centred reticle in both
            -- TPS over-shoulder and FPS, since ViewportPointToRay uses the live camera projection)
            TargetingLoopConnection = RunService.RenderStepped:Connect(function(deltaTime)
                local Camera = game.Workspace.CurrentCamera
                local Center = Camera.ViewportSize / 2

                local UnitRay = Camera:ViewportPointToRay(Center.X, Center.Y)
                -- Unit ray has: Ray.Origin and Ray.Direction
                local Direction = UnitRay.Direction * RayLength

                local RayResult : RaycastResult = workspace:Raycast(UnitRay.Origin, Direction, SwordRayParams) 
                if RayResult then
                    local ThisModel = RayResult.Instance:FindFirstAncestorOfClass("Model")
                    if not ThisModel then SetTargetAquired(false, "None") return end 
                    local Humanoid = ThisModel:FindFirstChildOfClass("Humanoid")
                    if Humanoid then
                        SetTargetAquired(true, ThisModel) -- enables lunge on next click
                    else
                        SetTargetAquired(false, "None")
                    end 
                else
                    SetTargetAquired(false, "None")
                end
        end)
    else 
        if TargetingLoopConnection then
            TargetingLoopConnection:Disconnect()
            TargetingLoopConnection = nil
        end
    end



end

local function ClearConnections()
    for _, Connection in Connections do
        Connection:Disconnect() 
    end 

    table.clear(Connections)
end 

local function ToggleCursor(state : boolean)
    local Core = PlayerGui:FindFirstChild("AJ")
    if not Core then
        if not state then
            UIS.MouseIconEnabled = true
        end
        return 
    end 
    Cursor = Core:FindFirstChild("EnergySwordCursor")


    if not Cursor then return end 
    print("cursor found")
    if state == true then 
        print("set vis")
        -- pin the reticle to the true viewport centre so it lines up with the centre-cast ray.
        -- compensate for the topbar inset only when the gui doesn't already ignore it.
        local Camera = Workspace.CurrentCamera
        if Camera then
            local InsetY = Core.IgnoreGuiInset and 0 or GuiService:GetGuiInset().Y
            Cursor.AnchorPoint = Vector2.new(0.5, 0.5)
            Cursor.Position = UDim2.fromOffset(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2 - InsetY)
        end
        Cursor.Visible = true
        UIS.MouseIconEnabled = false
    else 
        print("set invis")
        Cursor.Visible = false
        UIS.MouseIconEnabled = true
    end 
end 

local function InitSword(Sword : Tool)
    local Char = Player.Character 
    if not Char then return end  
    local Mode = ViewController:GetMode()
    ToggleCursor(true)
    ViewController.SetOTSToolEquipped(true)

    -- equip sound is local to us only
    if EquipSoundTemplate then
        local EquipSound = EquipSoundTemplate:Clone()
        EquipSound.Parent = Char
        EquipSound:Play()
        EquipSound.Ended:Once(function()
            EquipSound:Destroy()
        end)
    end
    if Mode == "TPS" then
        ViewController:ToggleOTSView(true) -- over shoulder when sword out
    end
    if Sword:GetAttribute("Ammo") == nil then
        Sword:SetAttribute("Ammo", WeaponConfig["Energy Sword"].Ammo)
    end    
    local Ammo = Sword:GetAttribute("Ammo")
    WeaponData = table.clone(WeaponConfig["Energy Sword"])
    AnimationController:PlayIdle(PlayerController:GetTool())
    ViewController.ApplyCharFollowsCursorLock(true, 0)

    local Began = UIS.InputBegan:Connect(function(input, gameProcessedEvent)
        if gameProcessedEvent then return end 

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if SwingActiveFlag then return end 
            print("Left click")
            if LungeData.CanLunge == true then 
                -- TODO: call Lunge() here instead of Swing()
                Lunge()  
            else
                Swing() 
            end 
        end
    end)
    table.insert(Connections, Began)
    ToggleTargetingLoop(true)
end 

local function RemoveSword(Sword : Tool?)
    PlayerGui = Player.PlayerGui
    ClearConnections()
    if LungeLoopConnection then
        LungeLoopConnection:Disconnect()
        LungeLoopConnection = nil
    end
    -- finish any in-progress lunge so the server clears CanClash; otherwise unequipping mid-lunge
    -- leaves us permanently clash-eligible (immune to incoming hits)
    if ActiveLungeFinish then
        local finish = ActiveLungeFinish
        ActiveLungeFinish = nil
        finish()
    end
    if KnockbackConnection then
        KnockbackConnection:Disconnect()
        KnockbackConnection = nil
    end
    ToggleTargetingLoop(false)
    ViewController.ToggleOTSView(false)
    ViewController.SetOTSToolEquipped(false)
    ViewController.ApplyCharFollowsCursorLock(false, 0)
    ToggleCursor(false)
    SwingActiveFlag = false
    LungeData.CanLunge = false
    LungeData.CurrentTarget = nil
    AnimationController.ClearSwingAnim()
    AnimationController.StopSwordLunge()
    table.clear(WeaponData)
    AnimationController:PlayIdle(PlayerController:GetTool())
    if Sword then
        print("Removing Sword")
        print(Sword:GetAttribute("Ammo"))
    end
end


-- run the clash bounce on our own character (we own its physics, so it stays in sync with what we
-- render). we only drive the HORIZONTAL position each frame and never anchor: anchoring the root
-- hands network ownership to the server, which then fights our client and flings us into the void,
-- especially mid-jump. leaving the vertical axis to physics lets jumps/gravity carry on naturally.
local function PerformClashKnockback(direction : Vector3, distance : number, duration : number)
    -- a clash just resolved on the server, which fires the bounce to both players at once. end our
    -- lunge right here so both lunges (and their animations) finish together instead of whenever each
    -- player happens to arrive.
    if ActiveLungeFinish then
        local finish = ActiveLungeFinish
        ActiveLungeFinish = nil
        finish()
    end

    local Char = Player.Character
    if not Char then return end 
    local hrp = Char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end 

    local Flat = Vector3.new(direction.X, 0, direction.Z)
    if Flat.Magnitude < 1e-3 then return end 
    Flat = Flat.Unit

    -- clip against walls so we don't slide into geometry
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { Char, Workspace.CurrentCamera }
    params.IgnoreWater = true
    local hit = Workspace:Raycast(hrp.Position, Flat * (distance + 2), params)
    if hit then
        distance = math.max((hit.Position - hrp.Position).Magnitude - 2, 0)
    end
    if distance < 1e-3 then return end 

    if KnockbackConnection then
        KnockbackConnection:Disconnect()
        KnockbackConnection = nil
    end

    local startPos = hrp.Position
    local goalPos = startPos + Flat * distance
    local elapsed = 0

    KnockbackConnection = RunService.RenderStepped:Connect(function(dt)
        if not hrp.Parent or Player.Character ~= Char then
            if KnockbackConnection then KnockbackConnection:Disconnect() KnockbackConnection = nil end
            return
        end

        elapsed += dt
        local t = math.clamp(elapsed / duration, 0, 1)
        local eased = 1 - (1 - t) * (1 - t) -- quad-out: punchy at the start, settles at the end
        local target = startPos:Lerp(goalPos, eased)

        -- drive XZ to the eased target, leave Y (and vertical velocity) to physics so jumps survive
        local current = hrp.Position
        local rotation = hrp.CFrame - hrp.CFrame.Position
        hrp.CFrame = CFrame.new(Vector3.new(target.X, current.Y, target.Z)) * rotation
        local velocity = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)

        if t >= 1 then
            if KnockbackConnection then KnockbackConnection:Disconnect() KnockbackConnection = nil end
        end
    end)
end

ClashKnockbackRemote.OnClientEvent:Connect(PerformClashKnockback)

-- the server cancelled our lunge (the target dashed clear): stop moving and drop the lunge animation
CancelLungeRemote.OnClientEvent:Connect(function()
    if ActiveLungeFinish then
        local finish = ActiveLungeFinish
        ActiveLungeFinish = nil
        finish()
    end
end)

local function OnCharacterAdded(character : Model)
    PlayerGui = Player.PlayerGui

    character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and child:GetAttribute("Type") == "Melee" then
            InitSword(child)
        end
    end)

    character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child:GetAttribute("Type") == "Melee" then
            RemoveSword(child)
        end
    end)

end

PlayerService.LocalPlayer.CharacterAdded:Connect(function(character)
        OnCharacterAdded(character)
end)

PlayerService.LocalPlayer.CharacterRemoving:Connect(function()
    RemoveSword()
end)

if Player.Character then
    OnCharacterAdded(Player.Character)
end

return SwordController