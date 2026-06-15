-- energy sword: hitbox overlap, lock-on cursor, ots camera

local SwordController = {} 
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)
local ViewController = require(script.Parent.ViewController)
local AnimationController = require(script.Parent.AnimationController)
local PlayerController = require(script.Parent.PlayerController)
local SwingRemote : RemoteEvent = game.ReplicatedStorage.Remotes.SwordSwing 


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
    local HitBox : BasePart = Sword:FindFirstChild("Hitbox", true)

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


-- TODO: implement sword lunge
-- 1. play lunge anim (WeaponConfig["Energy Sword"].Animations.Lunge)
-- 2. move player toward LungeData.CurrentTarget HRP, stop at ~5 studs or on hit
-- 3. run hit detection like Swing() but only on CurrentTarget
-- 4. set SwingActiveFlag so normal swing cant overlap
-- 5. reset LungeData after lunge ends
local function Lunge() 
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
    local Core =  PlayerGui:FindFirstChild("AJ")
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
                Swing() 
            else
                Swing() 
            end 
        end
    end)
    table.insert(Connections, Began)
    ToggleTargetingLoop(true)
end 

local function RemoveSword(Sword : Tool) 
    ToggleCursor(false)
    ClearConnections()
    AnimationController.ClearSwingAnim()
    AnimationController:PlayIdle(PlayerController:GetTool())
    ViewController.ToggleOTSView(false)
    ViewController.SetOTSToolEquipped(false)
    ViewController.ApplyCharFollowsCursorLock(false, 0)
    table.clear(WeaponData)
    print("Removing Sword")
    local Ammo = Sword:GetAttribute("Ammo")
    print(Ammo)
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

if Player.Character then
    OnCharacterAdded(Player.Character)
end

return SwordController