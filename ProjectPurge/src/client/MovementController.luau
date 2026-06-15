-- client movement: sprint, dash, grapple, low gravity

local PlayerService = game:GetService("Players")
local MovementController = {} 
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MovementConfig = require(game.ReplicatedStorage.Shared:WaitForChild("MovementConfig"))
local AnimationController = require(script.Parent:FindFirstChild("AnimationController"))
local ViewController = require(script.Parent:FindFirstChild("ViewController"))
local SFXController = require(script.Parent:FindFirstChild("SFXController"))
local InterfaceController = require(script.Parent:FindFirstChild("InterfaceController"))
local RemotesFolder = game.ReplicatedStorage:FindFirstChild("Remotes")
local Workspace = game.Workspace

local Player = PlayerService.LocalPlayer
local Connections: { RBXScriptConnection } = {} 

local GrappleActive = false
local GrappleBeamData = {
    FPS = {
        GrappleBeam = nil,
        GrappleHitAnchor = nil 
    },
    TPS = {
        GrappleBeam = nil,
        GrappleHitAnchor = nil, 
    }
}
local PullConnection: RBXScriptConnection? = nil 
local GrappleCurrentToolConnection :RBXScriptConnection? = nil 

local DashActive = false
local DashBoostConnection: RBXScriptConnection? = nil 

local MoonJumpConnection: RBXScriptConnection? = nil 

function MovementController.GetIsGrappling()
    return GrappleActive
end

local function ClearConnections()
    for _, Connection in Connections do 
        Connection:Disconnect()
    end 
    table.clear(Connections)

    if MoonJumpConnection then 
        MoonJumpConnection:Disconnect()
        MoonJumpConnection = nil
    end 

    if DashBoostConnection then
        DashBoostConnection:Disconnect()
        DashBoostConnection = nil   
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

local function EnforceDefaults(character, Humanoid : Humanoid)
    local HeldTool = GetTool(character)
    if not Humanoid then return end 

    Humanoid.WalkSpeed = MovementConfig.Walk.Walkspeed
    AnimationController:PlayIdle(HeldTool)
end 

local function ToggleSprint(Enabled : boolean, character, Humanoid : Humanoid)
    if not character then return end 
    local HeldTool = GetTool(character)

    if not Humanoid then return end 

    if Enabled then 
        AnimationController:PlaySprint(Humanoid, HeldTool)
        Humanoid.WalkSpeed = MovementConfig.Sprint.Walkspeed
    else
        AnimationController:StopSprint(Humanoid, HeldTool)
        Humanoid.WalkSpeed = MovementConfig.Walk.Walkspeed
    end 
end 

-- beam from arm attachment to raycast hit point
local function createGrappleBeam(grappleAttachment: Attachment, targetWorld: Vector3): (Beam, BasePart)
	local endPart = Instance.new("Part")
	endPart.Name = "GrappleHitAnchor"
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(0.2, 0.2, 0.2)
	endPart.Position = targetWorld
	endPart.Parent = workspace
	local endAttachment = Instance.new("Attachment")
	endAttachment.Name = "GrappleHit"
	endAttachment.Parent = endPart
	local beam = Instance.new("Beam")
	beam.Name = "GrappleBeam"
	beam.Attachment0 = grappleAttachment
	beam.Attachment1 = endAttachment
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.LightEmission = 0.4
	beam.Color = ColorSequence.new(Color3.fromRGB(5, 6, 8))
	beam.Parent = grappleAttachment.Parent
	return beam, endPart
end

local function CleanUpGrappleToolConn()
    if GrappleCurrentToolConnection then
        GrappleCurrentToolConnection:Disconnect()
        GrappleCurrentToolConnection = nil
    end 
end

local function destroyGrappleBeam(beam: Beam?, endPart: BasePart?)
	if beam then
		beam:Destroy()
	end
	if endPart then
		endPart:Destroy()
	end
end

local function CleanUpOnDeath()
    if GrappleActive then
        GrappleActive = false
        CleanUpGrappleToolConn()
        if PullConnection then
            PullConnection:Disconnect()
            PullConnection = nil
        end
        destroyGrappleBeam(GrappleBeamData.TPS.GrappleBeam, GrappleBeamData.TPS.GrappleHitAnchor)
        destroyGrappleBeam(GrappleBeamData.FPS.GrappleBeam, GrappleBeamData.FPS.GrappleHitAnchor)
        GrappleBeamData.TPS.GrappleBeam = nil
        GrappleBeamData.TPS.GrappleHitAnchor = nil
        GrappleBeamData.FPS.GrappleBeam = nil
        GrappleBeamData.FPS.GrappleHitAnchor = nil
    end
    ClearConnections()
    DashActive = false
end

local function FinishGrapple()
    if not GrappleActive then return end 
    GrappleActive = false
    CleanUpGrappleToolConn()

    if PullConnection then 
        PullConnection:Disconnect()
        PullConnection = nil 
    end 

    destroyGrappleBeam( GrappleBeamData.TPS.GrappleBeam, GrappleBeamData.TPS.GrappleHitAnchor)
    destroyGrappleBeam( GrappleBeamData.FPS.GrappleBeam, GrappleBeamData.FPS.GrappleHitAnchor)
    GrappleBeamData.TPS.GrappleBeam = nil 
    GrappleBeamData.TPS.GrappleHitAnchor = nil
    GrappleBeamData.FPS.GrappleBeam = nil 
    GrappleBeamData.FPS.GrappleHitAnchor = nil 

    local Character = Player.Character
    local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")

    if Character and HumanoidRootPart then
        HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    end

    local ViewModel = ViewController:ReceiveViewModel()
    if not ViewModel then return end 
    ViewController:EndGrapple()
    InterfaceController:RegenGrapple() 
end

-- velocity pull toward grapple point each heartbeat
local function PullPlayerToTarget(character : Model, TargetPosition : Vector3 ) : RBXScriptConnection
    local StudsPerSecond = 30
    local ArrivalDistance = 5 
    local MaxDurationSeconds = 5

    local HumanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local Humanoid = character:FindFirstChildOfClass("Humanoid")
    if not HumanoidRootPart or not Humanoid then return nil end 

    local StartTime = os.clock() 

    local Connection : RBXScriptConnection
    Connection = RunService.Heartbeat:Connect(function(deltaTime)
        if os.clock() - StartTime > MaxDurationSeconds then 
            Connection:Disconnect()
            HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
            FinishGrapple()
            return 
        end 

        local CurrentPosition = HumanoidRootPart.Position 
        local Offset = TargetPosition - CurrentPosition
        local offsetX = Offset.X 
        local offsetY = Offset.Y
        local offsetZ = Offset.Z 

        local DistanceMagnitude = math.sqrt((offsetX * offsetX) +  (offsetY * offsetY) + (offsetZ * offsetZ))

        if DistanceMagnitude <= ArrivalDistance then 
            Connection:Disconnect()
            HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
            FinishGrapple()
            return 
        end 

        local Direction = Vector3.new(offsetX / DistanceMagnitude, offsetY / DistanceMagnitude, offsetZ / DistanceMagnitude)
        HumanoidRootPart.AssemblyLinearVelocity = Direction * StudsPerSecond
    end)

    return Connection
end 

function MovementController.ToggleGrappleBeamVisibility(ViewState)
    -- only show beam for current camera mode
    if ViewState == "FPS" then
        GrappleBeamData.FPS.GrappleBeam.Enabled = true
        GrappleBeamData.TPS.GrappleBeam.Enabled = false
    else
        GrappleBeamData.TPS.GrappleBeam.Enabled = true
        GrappleBeamData.FPS.GrappleBeam.Enabled = false
    end
end 

local function InitGrapplePoint(character)
    local FPSGrapplePoint : Attachment
    local TPSGrapplePoint : Attachment

    local ViewModel = ViewController:ReceiveViewModel()
    if not ViewModel then return nil end 
    local LeftArm = ViewModel:FindFirstChild("LeftArm")
    local RightArm = ViewModel:FindFirstChild("RightArm")
    if not LeftArm or not RightArm then return nil end 
    FPSGrapplePoint = LeftArm:FindFirstChild("GrapplePoint")
    if not FPSGrapplePoint then 
        FPSGrapplePoint = RightArm:FindFirstChild("GrapplePoint")    
    end 

    local TPSLeftArm = character:FindFirstChild("Left Arm")
    TPSGrapplePoint = TPSLeftArm:FindFirstChild("TPSGrapplePoint")      

    if not TPSGrapplePoint or not FPSGrapplePoint then return nil end 

    return TPSGrapplePoint, FPSGrapplePoint
end 

-- rebuild beams when tool changes mid-grapple
local function GrappleToolChange(character, CurrentTargetPos)
    local FPSGrappleBeam = GrappleBeamData.FPS.GrappleBeam
    local FPSGrappleAnchor = GrappleBeamData.FPS.GrappleHitAnchor
    local TPSGrappleBeam =  GrappleBeamData.TPS.GrappleBeam
    local TPSGrappleAnchor = GrappleBeamData.TPS.GrappleHitAnchor
    if  FPSGrappleBeam or FPSGrappleAnchor then
        destroyGrappleBeam(FPSGrappleBeam, FPSGrappleAnchor)
        GrappleBeamData.FPS.GrappleBeam = nil 
        GrappleBeamData.FPS.GrappleHitAnchor = nil 
    end 
    if TPSGrappleBeam or TPSGrappleAnchor then
        destroyGrappleBeam(TPSGrappleBeam, TPSGrappleAnchor)
        GrappleBeamData.TPS.GrappleBeam = nil 
        GrappleBeamData.TPS.GrappleHitAnchor = nil
    end
    local TPSGrapplePoint, FPSGrapplePoint = InitGrapplePoint(character)
    if not TPSGrapplePoint or not FPSGrapplePoint then return end 

    GrappleBeamData.FPS.GrappleBeam, GrappleBeamData.FPS.GrappleHitAnchor = createGrappleBeam(FPSGrapplePoint, CurrentTargetPos)
    GrappleBeamData.TPS.GrappleBeam, GrappleBeamData.TPS.GrappleHitAnchor = createGrappleBeam(TPSGrapplePoint, CurrentTargetPos)
    local ViewState = ViewController:GetMode()
    MovementController.ToggleGrappleBeamVisibility(ViewState)
    ViewController:Grapple()
end

local function FireGrapple(character)
    if not character then return end 

    local TPSGrapplePoint, FPSGrapplePoint = InitGrapplePoint(character)
    if not TPSGrapplePoint or not FPSGrapplePoint then return end 

    local Camera = workspace.CurrentCamera
    local MouseLocation = UserInputService:GetMouseLocation() 
    local Ray = Camera:ViewportPointToRay(MouseLocation.X, MouseLocation.Y)
    local Range = MovementConfig.Grapple.GrappleRange

    local Paramters = RaycastParams.new()
    Paramters.FilterType = Enum.RaycastFilterType.Exclude
    Paramters.FilterDescendantsInstances = { character }

    local AimResult = workspace:Raycast(Ray.Origin, Ray.Direction * Range, Paramters)
    if not AimResult then
        return 
    end

    local TargetPosition = AimResult.Position
    local HitPart = AimResult.Instance 

    if GrappleActive then return end 
    GrappleActive = true
    GrappleBeamData.FPS.GrappleBeam, GrappleBeamData.FPS.GrappleHitAnchor = createGrappleBeam(FPSGrapplePoint, TargetPosition)
    GrappleBeamData.TPS.GrappleBeam, GrappleBeamData.TPS.GrappleHitAnchor = createGrappleBeam(TPSGrapplePoint, TargetPosition)
    local ViewState = ViewController:GetMode()
    MovementController.ToggleGrappleBeamVisibility(ViewState)
    ViewController:Grapple()
    SFXController:PlayGrappleShot(character)
    PullConnection = PullPlayerToTarget(character, TargetPosition)
    CleanUpGrappleToolConn()
    GrappleCurrentToolConnection = character:GetAttributeChangedSignal("CurrentTool"):Connect(function(...)  
        if not GrappleActive then return end 
        GrappleToolChange(character, TargetPosition)
    end)
    InterfaceController:UseGrapple() 
end 

local function Dash(character, Humanoid)
    if not character then return end 

    local DashDuration = MovementConfig.Dash.Duration
    local DashDistance = MovementConfig.Dash.Distance
    local DashCooldown = MovementConfig.Dash.Cooldown
    local DashAttribute = character:GetAttribute("Dashes")
    local DashNumber = tonumber(DashAttribute)
    local DashRemote : RemoteEvent = RemotesFolder:FindFirstChild("Dash")

    if not character or not Humanoid then return end
    local HumanoidRootPart : BasePart = character:FindFirstChild("HumanoidRootPart")
    if not HumanoidRootPart then return end 
    if not DashRemote then return end 
    if GrappleActive then return end 
    if DashActive then return end 
    if DashNumber <= 0 then return end 

    -- dash in current move direction, fallback to look vector
    local AssemblyLinearVelocity = HumanoidRootPart.AssemblyLinearVelocity
    local XZVelocity = Vector3.new(AssemblyLinearVelocity.X, 0, AssemblyLinearVelocity.Z)
    
    if XZVelocity.Magnitude <= 1e-3 then
        local LookVector = HumanoidRootPart.CFrame.LookVector
        XZVelocity = Vector3.new(LookVector.X, 0, LookVector.Z)
    end
    if XZVelocity.Magnitude <= 1e-3 then
        return 
    end

    local Direction = XZVelocity.Unit
    local Speed = DashDistance / DashDuration
    
    -- figure out which dash anim to play on viewmodel
    local flat = Vector3.new(Direction.X, 0, Direction.Z)
	local flatMag = flat.Magnitude
	if flatMag <= 1e-6 then
		return
	end
	flat = flat / flatMag
	local localDir = HumanoidRootPart.CFrame:VectorToObjectSpace(flat)
	local angleDeg = math.deg(math.atan2(localDir.X, -localDir.Z))
	local CardinalDirection: string
	if math.abs(angleDeg) <= 45 then
		CardinalDirection = "Forward"
	elseif angleDeg > 45 and angleDeg <= 135 then
		CardinalDirection = "Right"
	elseif angleDeg >= -135 and angleDeg < -45 then
		CardinalDirection = "Left"
	else
		CardinalDirection = "Backwards"
	end

    if DashBoostConnection then 
        DashBoostConnection:Disconnect()
        DashBoostConnection = nil 
    end

    DashActive = true
    ViewController:Dash(CardinalDirection)

    DashRemote:FireServer()
    local Time0 = os.clock() 
    DashBoostConnection = RunService.Heartbeat:Connect(function()
        if not HumanoidRootPart or os.clock() - Time0 >= DashDuration then
            if DashBoostConnection then
                DashBoostConnection:Disconnect()
                ViewController:EndDash()
                DashBoostConnection = nil
                task.delay(DashCooldown, function()
                    DashActive = false
                end)
                return 

            end
        end 

        local StartY = HumanoidRootPart.AssemblyLinearVelocity.Y
        HumanoidRootPart.AssemblyLinearVelocity = Direction * Speed + Vector3.new(0, 0, 0)
    end)
end 

-- low gravity in air via VectorForce on HRP
local function SetupMoonMovement(character: Model, humanoid: Humanoid)
	local cfg = MovementConfig.MoonMovement
	if not cfg or not cfg.Enabled then
		return
	end
	local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hrp then
		return
	end
	local airG = math.clamp(cfg.AirGravityScale or 0.35, 0.05, 1)
	local mult = cfg.JumpHeightMultiplier
	if typeof(mult) == "number" and mult > 0 then
		humanoid.JumpHeight = humanoid.JumpHeight * mult
	end
	local oldVf = hrp:FindFirstChild("MoonMovementVectorForce")
	if oldVf then
		oldVf:Destroy()
	end
	local oldAtt = hrp:FindFirstChild("MoonMovementAttachment")
	if oldAtt then
		oldAtt:Destroy()
	end
	local att = Instance.new("Attachment")
	att.Name = "MoonMovementAttachment"
	att.Parent = hrp
	local vf = Instance.new("VectorForce")
	vf.Name = "MoonMovementVectorForce"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Enabled = false
	vf.Force = Vector3.zero
	vf.Parent = hrp
	if MoonMovementConnection then
		MoonMovementConnection:Disconnect()
		MoonMovementConnection = nil
	end
	MoonMovementConnection = RunService.PostSimulation:Connect(function()
		if not character.Parent or not hrp.Parent or humanoid.Health <= 0 then
			vf.Enabled = false
			vf.Force = Vector3.zero
			return
		end
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Seated then
			vf.Enabled = false
			vf.Force = Vector3.zero
			return
		end
		if GrappleActive then
			vf.Enabled = false
			vf.Force = Vector3.zero
			return
		end
		local inAir = humanoid.FloorMaterial == Enum.Material.Air
		if inAir then
			local cancel = 1 - airG
			vf.Force = Vector3.new(0, hrp.AssemblyMass * Workspace.Gravity * cancel, 0)
			vf.Enabled = true
		else
			vf.Enabled = false
			vf.Force = Vector3.zero
		end
	end)
end

local function OnCharacterAdded(character)
    ClearConnections()

    local Humanoid : Humanoid = character:WaitForChild("Humanoid", 10)
    -- clone grapple attachment onto left arm for tps beam
    local GrapplePoint = ReplicatedStorage:FindFirstChild("Viewports"):FindFirstChild("TPSGrapplePoint")
    local LeftArm = character:FindFirstChild("Left Arm")
    if GrapplePoint then
        local ThisGrapplePoint = GrapplePoint:Clone()
        ThisGrapplePoint.Name = "TPSGrapplePoint"
        ThisGrapplePoint.Parent = LeftArm
    end
    if not Humanoid then return end 

    character:WaitForChild("Animate", 5)

    SetupMoonMovement(character, Humanoid)

    task.defer(function()
        RunService.Heartbeat:Wait()
        RunService.Heartbeat:Wait()
        EnforceDefaults(character, Humanoid)
    end)

    local Began = UserInputService.InputBegan:Connect(function(Input : InputObject, Gpe)
        if Gpe then return end 

        if Input.KeyCode == MovementConfig.Sprint.ToggleKey then 
            ToggleSprint(true, character, Humanoid)
        end 
        if Input.KeyCode == MovementConfig.Grapple.ToggleKey then 
            FireGrapple(character)
        end 
        if Input.KeyCode == MovementConfig.Dash.ToggleKey then 
            Dash(character, Humanoid)
        end 
        if Input.KeyCode == Enum.KeyCode.K then
            -- debug: print viewmodel name
            local tempmodel = ViewController:ReceiveViewModel()
           print(tempmodel.Name)
        end
    end)

    local Ended = UserInputService.InputEnded:Connect(function(Input : InputObject, Gpe)
        if Gpe then return end 

        if Input.KeyCode == MovementConfig.Sprint.ToggleKey then 
            ToggleSprint(false, character, Humanoid)
        end 
    end)

    table.insert(Connections, Began)
    table.insert(Connections, Ended)
    Humanoid.Died:Connect(CleanUpOnDeath)
end

Player.CharacterAdded:Connect(function(character)
    OnCharacterAdded(character)
end)

Player.CharacterRemoving:Connect(function()
    CleanUpOnDeath()
end)

if Player.Character then
    OnCharacterAdded(Player.Character)
end

return MovementController
