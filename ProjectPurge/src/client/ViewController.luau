-- fps viewmodels, tps/fps switch, ots lock, dash/grapple anims on arms

local PlayerService = game:GetService("Players")
local Player = PlayerService.LocalPlayer
local StarterPack = game:GetService("StarterPack")
local UIS = game:GetService("UserInputService") 
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ViewportConfig = require(game.ReplicatedStorage.Shared.ViewportsConfig)
local ViewportFolder = game.ReplicatedStorage:WaitForChild("Viewports")
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)
local ViewModelAnimations = require(game.StarterPlayer.StarterPlayerScripts.Client.ViewModelAnimations)


local FirstLoaded = false

local ThisTool 
local ViewController = {}
local Enabled = false
local MouseLockConnection : RBXScriptConnection
local ViewDetectionConnection : RBXScriptConnection -- hey it rhymes 
local CharacterFollowsCursorConnection : RBXScriptConnection 
local ViewModelTemplate = nil
local ActiveViewModel = nil
local CamOffsetInitial = nil 
local IsOTSToolEquipped = false
local OriginalNeckC0
local OriginalArmC0 = {} 

local ViewModelInstances = {
    Idle = nil,
    Gun = nil,
    Melee = nil,
} -- cached clones per tool type

local function ApplyCharacterDirectionLoop()
    -- tilt neck + shoulders toward cursor/camera pitch
    local Character = Player.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local Torso : BasePart = Character and Character:FindFirstChild("Torso")
    local Neck : Motor6D = Torso and Torso:FindFirstChild("Neck")
    local RightShoulder : Motor6D = Torso and Torso:FindFirstChild("Right Shoulder")
    local LeftShoulder : Motor6D = Torso and Torso:FindFirstChild("Left Shoulder")
    local Camera = Workspace.CurrentCamera
    local yAlpha
    local Pitch 
    local RightZ
    local LeftZ 

    if not Character or not Humanoid or not Torso or not Camera or not Neck then return end 

    local MouseLocation = UIS:GetMouseLocation()
    local CameraDirection = Camera.CFrame.LookVector

    -- Head orientation between +45 and -15     
    -- Smaller y values > top of the screen, bigger y values > bottom of screen
    if UIS.MouseBehavior == Enum.MouseBehavior.LockCenter then 
        Pitch = math.asin(CameraDirection.Y)
    else 
        yAlpha = math.clamp(MouseLocation.Y / Camera.ViewportSize.Y, 0, 1)
        Pitch = math.rad(45 + (-15 - 45) * yAlpha)
    end

    -- Arms are mirrored, so the same visual floor reads as -5 on the right and +5 on the left
    RightZ = math.clamp(Pitch,  math.rad(-5),   math.rad(100))
    LeftZ  = math.clamp(-Pitch, math.rad(-100), math.rad(5))

    Neck.C0          = OriginalNeckC0                * CFrame.Angles(-Pitch, 0, 0)
    RightShoulder.C0 = OriginalArmC0[RightShoulder]  * CFrame.Angles(0, 0, RightZ)
    LeftShoulder.C0  = OriginalArmC0[LeftShoulder]   * CFrame.Angles(0, 0, LeftZ)
end 

function ViewController.ApplyCharFollowsCursorLock(state, AutomaticTimeout)
    if AutomaticTimeout == 0 then
        AutomaticTimeout = math.huge
    end

    local Character = Player.Character
    local Torso = Character and Character:FindFirstChild("Torso")
    local Neck = Torso and Torso:FindFirstChild("Neck")

    if not state or not Character then
        if CharacterFollowsCursorConnection then
            CharacterFollowsCursorConnection:Disconnect()
            CharacterFollowsCursorConnection = nil 
            Neck.C0 = OriginalNeckC0
            return 
        end
    end 

    CharacterFollowsCursorConnection = RunService.RenderStepped:Connect(ApplyCharacterDirectionLoop)

    if AutomaticTimeout < math.huge then
        task.delay(AutomaticTimeout, function()
            if CharacterFollowsCursorConnection then
                CharacterFollowsCursorConnection:Disconnect()
                CharacterFollowsCursorConnection = nil  
                Neck.C0 = OriginalNeckC0
                return 
            end
        end)
    end
end 

function ViewController.SetOTSToolEquipped(state)
    IsOTSToolEquipped = state
end 

function ViewController.GetMode()
    local Character = Player.Character
    local Mode = tostring(Character:GetAttribute("ViewState"))
    return Mode
end

function ViewController.ApplyOTSLock()
    -- over-shoulder: lock char facing camera yaw, offset cam right
    local Character = Player.Character
    local Humanoid = Character and Character:FindFirstChild("Humanoid")
    local hrp = Character and Character:FindFirstChild("HumanoidRootPart")
    local Camera=  workspace.CurrentCamera

    if not Humanoid or not hrp then return end 
    if Humanoid then Humanoid.AutoRotate = false end 
    Humanoid.CameraOffset = Vector3.new(4, 1 , 0)

    local LookVector = Camera.CFrame.LookVector
    local FlatLookVector = Vector3.new(LookVector.X, 0, LookVector.Z)

    if FlatLookVector.Magnitude > 0 then
        hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + FlatLookVector)
    end
end 

function ViewController.ReleaseOTSLock()
    local Character = Player.Character
    local Humanoid = Character:FindFirstChild("Humanoid")
    local Hrp = Character:FindFirstChild("HumanoidRootPart")

    local Camera = workspace.CurrentCamera
    Humanoid.AutoRotate = true
    if CamOffsetInitial then
        Humanoid.CameraOffset = CamOffsetInitial
    end
end 

function ViewController.ToggleOTSView(state : boolean)
    local Character = Player.Character
    local Humanoid = Character:FindFirstChild("Humanoid")
    if state then
        if Humanoid then
            CamOffsetInitial = Humanoid.CameraOffset
        end
        UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
        MouseLockConnection =  RunService.RenderStepped:Connect(ViewController.ApplyOTSLock)
    else 
        UIS.MouseBehavior = Enum.MouseBehavior.Default
        if MouseLockConnection then
            MouseLockConnection:Disconnect()
            MouseLockConnection = nil 
        end
        ViewController:ReleaseOTSLock()
    end
end

local function GetTool(character) 
    for _, Child in character:GetChildren() do
        if Child:IsA("Tool") then
            local ToolType = Child:GetAttribute("Type")
            return ToolType
        end 
    end

    return "Empty"
end 

function ViewController.Dash(self, Direction)
    if not ActiveViewModel then return end 

    ViewModelAnimations:PlayDash(ActiveViewModel, Direction, ThisTool)
end

function ViewController.EndDash()
    if not ActiveViewModel then return end 
    ViewModelAnimations:DashStop(ActiveViewModel)
end

function ViewController.ReceiveViewModel(self)
    if not ActiveViewModel then 
        return nil
    end 

    return ActiveViewModel
end 

function ViewController.Grapple()
    if not ActiveViewModel then return end 
        
    ViewModelAnimations:Grapple(ActiveViewModel, ThisTool)
end

function ViewController.EndGrapple()
    if not ActiveViewModel then return end 
    ViewModelAnimations:GrappleStop(ActiveViewModel)
end

local function ToggleFPSarmsVisibility(state)
    local ViewModel = ViewController:ReceiveViewModel()

    if not state then
        for _, Child in ViewModel:GetChildren() do
            if Child:IsA("BasePart") or Child:IsA("MeshPart") then
                Child.Transparency = 1
            end
        end
    else
        for _, Child in ViewModel:GetChildren() do
            if Child:IsA("BasePart") or Child:IsA("MeshPart") then
                Child.Transparency = 0
            end
        end
    end 
end 


function ViewController.UpdateFPSarms(self, deltaTime : number, Tool)
    -- swap viewmodel template based on equipped tool, follow camera
    local OldViewModel
    if FirstLoaded then 
        OldViewModel = ViewController:ReceiveViewModel()
    end

    if Tool == "Empty" then 
        ViewModelTemplate = ViewportFolder:FindFirstChild(ViewportConfig.Idle)
    elseif Tool == "Melee" then
        ViewModelTemplate = ViewportFolder:FindFirstChild("Melee")
    else 
        ViewModelTemplate = ViewportFolder:FindFirstChild(ViewportConfig.Idle)
    end 

    if not ViewModelTemplate then return end

    if not ViewModelInstances[Tool] then
        ActiveViewModel = ViewModelTemplate:Clone()
        ActiveViewModel.Parent = workspace.CurrentCamera
        ViewModelInstances[Tool] = ActiveViewModel
    else 
        ActiveViewModel = ViewModelInstances[Tool]
    end

    if OldViewModel then
        for _, Child : BasePart in OldViewModel:GetDescendants() do
            if Child:IsA("BasePart") then
                Child.Transparency = 1
                Child.LocalTransparencyModifier = 1
                --Child.Anchored = true
                Child.CanCollide = false
                Child.Massless = true
            end
        end
    end

    for _, Child :BasePart in ActiveViewModel:GetDescendants() do
        if Child:IsA("BasePart") then
            Child.Transparency = 0
            Child.LocalTransparencyModifier = 0
            --Child.Anchored = true
            Child.CanCollide = false
            Child.Massless = true
        end
    end
    
    local Camera = workspace.CurrentCamera
    local Offset = CFrame.new(0, -1.3, 0)
    ActiveViewModel:PivotTo(Camera.CFrame * Offset)
    if FirstLoaded == false then FirstLoaded = true end 
end 


function ViewController.Enable(self, Tool, character)
    RunService:UnbindFromRenderStep("MyFPSarms")

    -- runs after camera, keeps arms glued to cam
    RunService:BindToRenderStep(
        "MyFPSarms",
        Enum.RenderPriority.Camera.Value + 1, 
        function(deltaTime: number)
            self:UpdateFPSarms(deltaTime, Tool)
            if character:GetAttribute("CurrentTool") ~= Tool then 
                character:SetAttribute("CurrentTool", Tool)
                print("changed tool to ", Tool)
            end 
        end
    )
end

local function HideTools(character)
    -- fps mode hides 3rd person tool mesh
    for _, PotentialTool in character:GetChildren() do
        if PotentialTool:IsA("Tool") then
            for _, ToolPart : Part in PotentialTool:GetChildren() do
                ToolPart.Transparency = 1
            end
        end
    end
end 

local function RevealTools(character)
    for _, PotentialTool : Tool in character:GetChildren() do
        if PotentialTool:IsA("Tool") then
            for _, PotentialPart in PotentialTool:GetChildren() do
                if PotentialPart.Name ~= "Hitbox" then
                    PotentialPart.Transparency = 0
                end
            end
        end
    end
end

local function EnsureRemovedToolVisibility(Tool)
    for _, Child in Tool:GetChildren() do
        if Child.Name ~= "Hitbox" then
            Child.Transparency = 0 
        end
    end
end

function ViewController.ToggleViewModelParticles(state)
    for _, Child in ActiveViewModel:GetChildren() do
        if Child.Name == "LeftArm" or Child.Name == "RightArm" then
            for _, SubChild in Child:GetChildren() do
                if SubChild:IsA("ParticleEmitter") then
                    if state then
                        SubChild.Enabled = true
                    else 
                        SubChild.Enabled = false
                    end
                end
            end
        end
    end
end 

local function GetViewState()
    -- zoom distance decides FPS vs TPS attr
    local Player = PlayerService.LocalPlayer
    local Character = Player.Character
    if not Player or not Character then return end 
    local Camera = Workspace.CurrentCamera
    if not Camera then return end 

    local Distance : Vector3 = (Camera.CFrame.Position - Camera.Focus.Position)
    local ZoomMagnitude = Distance.Magnitude
    local StateAttr = Character:GetAttribute("ViewState")
    local ThisState = tostring(StateAttr)
    if ZoomMagnitude < 0.6 and ThisState ~= "FPS" then
        Character:SetAttribute("ViewState", "FPS")
        print("set attr fps")
        return 
    elseif ZoomMagnitude >= 0.6 and ThisState ~= "TPS" then
        Character:SetAttribute("ViewState", "TPS")
        print("set attr tps")
        return 
    end

    return 
end

local function OnCharacterAdded(character)
    ThisTool = GetTool(character)
    ViewController:Enable(ThisTool, character)
    ViewDetectionConnection = RunService.RenderStepped:Connect(GetViewState)
    local Torso = character:WaitForChild("Torso")
    local Neck : Motor6D = Torso:FindFirstChild("Neck") 
    local RightShoulder = Torso:FindFirstChild("Right Shoulder")
    local LeftShoulder = Torso:FindFirstChild("Left Shoulder")
    OriginalNeckC0 = Neck.C0
    OriginalArmC0[RightShoulder] = RightShoulder.C0 
    OriginalArmC0[LeftShoulder] = LeftShoulder.C0

    character.ChildAdded:Connect(function()
        ThisTool = GetTool(character)
        if tostring(character:GetAttribute("ViewState")) == "FPS" then
            ViewController:Enable(ThisTool, character)
            HideTools(character) 
        end
    end)
    
    character.ChildRemoved:Connect(function(child)
        ThisTool = GetTool(character)
        EnsureRemovedToolVisibility(child) 
        if tostring(character:GetAttribute("ViewState")) == "FPS" then
            ViewController:Enable(ThisTool, character)
        end
    end)

    character:GetAttributeChangedSignal("ViewState"):Connect(function()
        local MovementController = require(script.Parent.MovementController) -- lazy require avoids cycle
        if MovementController.GetIsGrappling() then
            MovementController.ToggleGrappleBeamVisibility(ViewController:GetMode())
        end
        if tostring(character:GetAttribute("ViewState")) == "FPS" then
            ViewController:Enable(ThisTool, character)
            ViewController.ToggleOTSView(false)
            HideTools(character)
            ToggleFPSarmsVisibility(true)
            ViewController.ToggleViewModelParticles(true)
        else
            RunService:UnbindFromRenderStep("MyFPSarms")
            ToggleFPSarmsVisibility(false)
            RevealTools(character)
            ViewController.ToggleViewModelParticles(false)
            if IsOTSToolEquipped then
                ViewController.ToggleOTSView(true)
            end
        end
    end)

    character.Destroying:Connect(function()
        table.clear(OriginalArmC0)
        ViewModelInstances.Gun = nil
        ViewModelInstances.Idle = nil
        ViewModelInstances.Melee = nil 
        if ViewDetectionConnection then
            ViewDetectionConnection:Disconnect()
            ViewDetectionConnection = nil
        end
    end)
end


Player.CharacterAdded:Connect(function(character)
    OnCharacterAdded(character)
end)

if Player.Character then
    OnCharacterAdded(Player.Character)
end


return ViewController
