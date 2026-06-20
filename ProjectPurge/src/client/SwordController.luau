-- energy sword: hitbox overlap, lock-on cursor, ots camera

local SwordController = {} 
local HttpService = game:GetService("HttpService")
local StarterPack = game:GetService("StarterPack")
local UIS = game:GetService("UserInputService")
local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)
local ViewController = require(script.Parent.ViewController)
local AnimationController = require(script.Parent.AnimationController)
local PlayerController = require(script.Parent.PlayerController)
local SwingRemote : RemoteEvent = game.ReplicatedStorage.Remotes.SwordSwing 


local LungeLoopConnection : RBXScriptConnection
local TargetingLoopConnection : RBXScriptConnection
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
        CastDebugSwingPart(HitBox)
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

    if not hrp or not humanoid or not targetHrp or not targetHumanoid then
        return
    end
    if humanoid.Health <= 0 or targetHumanoid.Health <= 0 then
        return
    end

    local ARRIVAL_DISTANCE = 5
    local INITIAL_SPEED = 24
    local ACCELERATION = 120
    local MAX_SPEED = 72
    local MAX_DURATION = 5

    local startTime = os.clock()
    local currentSpeed = INITIAL_SPEED
    local losExclude = { Character, Workspace.CurrentCamera }

    local function finishLunge()
        if LungeLoopConnection then
            LungeLoopConnection:Disconnect()
            LungeLoopConnection = nil
        end

        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
        end

        LungeData.CanLunge = false
        LungeData.CurrentTarget = nil
        if Cursor then
            Cursor.ImageColor3 = Color3.new(255, 255, 255)
        end
    end

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
            Swing() 
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

    --local Humanoid : Humanoid = Player.Humanoid 
    --if not Humanoid then return end 
    --if Humanoid.Health <= 0 then return end 

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
            -- ray from mouse each frame, check for humanoid
            TargetingLoopConnection = RunService.RenderStepped:Connect(function(deltaTime)
                local MouseLocation = UIS:GetMouseLocation()
                local Camera = game.Workspace.CurrentCamera
 

                local UnitRay = Camera:ViewportPointToRay(MouseLocation.X, MouseLocation.Y)
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
    ToggleTargetingLoop(false)
    ViewController.ToggleOTSView(false)
    ViewController.SetOTSToolEquipped(false)
    ViewController.ApplyCharFollowsCursorLock(false, 0)
    ToggleCursor(false)
    SwingActiveFlag = false
    LungeData.CanLunge = false
    LungeData.CurrentTarget = nil
    AnimationController.ClearSwingAnim()
    table.clear(WeaponData)
    AnimationController:PlayIdle(PlayerController:GetTool())
    if Sword then
        print("Removing Sword")
        print(Sword:GetAttribute("Ammo"))
    end
end


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