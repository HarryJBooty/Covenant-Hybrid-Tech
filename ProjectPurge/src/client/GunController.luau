local WeaponsConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local PlayerService = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local HitRemote : RemoteEvent = game.ReplicatedStorage.Remotes.GunHit  

local Debris = game:GetService("Debris")
local Player = PlayerService.LocalPlayer
local Mouse = Player:GetMouse()

local STD_RANGE = 500 

local Connections : {RBXScriptConnection} = {} 
local ThisTool = nil 
local IsFiring = false
local ThisAmmo 
local Waiting = false



local GunController = {}

local function Reload()
    local maxAmmo = WeaponsConfig[ThisTool.Name].Ammo 
    ThisAmmo = maxAmmo
    IsFiring = false
    Waiting = true
    task.wait(WeaponsConfig[ThisTool.Name].Reload)
    ThisTool:SetAttribute("Ammo", maxAmmo)
    Waiting = false
end 

local function DecrementAmmo() 
    if ThisAmmo == nil then return end 

    ThisAmmo = ThisAmmo - 1 
    ThisTool:SetAttribute("Ammo", ThisAmmo)
end 

local function RenderShotFPS() 

end 

local function RenderShotTPS(point, hit : Vector3, color : BrickColor)
    local origin = point.WorldPosition
    local distance = (origin - hit).Magnitude

    local bullet = Instance.new("Part")
    bullet.Anchored = true
    bullet.CanCollide = false
    bullet.CanQuery = false

    bullet.BrickColor = color
    bullet.Material = Enum.Material.Neon
    bullet.Transparency = 0.5
    bullet.Parent = workspace.Ignore

    local bulletMini = Instance.new("Part")
    bulletMini.Anchored = true
    bulletMini.CanCollide = false

    bulletMini.BrickColor = BrickColor.new("Institutional white")
    bulletMini.Material = Enum.Material.Neon
    bulletMini.Parent = workspace.Ignore

    local bullet2 = bullet:Clone()
    bullet2.Parent = workspace.Ignore

    local bulletMini2 = bulletMini:Clone()
    bulletMini2.Parent = workspace.Ignore

    bullet.Size = Vector3.new(0.15, 0.15, distance / 2)
	bullet.CFrame = CFrame.new(origin, hit) * CFrame.new(0, 0, (-distance / 4))
    bulletMini.Size = Vector3.new(0.05, 0.05, distance / 2)
	bulletMini.CFrame = CFrame.new(origin, hit) * CFrame.new(0, 0, (-distance / 4))

    bullet2.Size = Vector3.new(0.15, 0.15, distance / 2)
	bullet2.CFrame = CFrame.new(origin, hit) * CFrame.new(0, 0, (-distance / 4) * 3)
    bulletMini2.Size = Vector3.new(0.05, 0.05, distance / 2)
	bulletMini2.CFrame = CFrame.new(origin, hit) * CFrame.new(0, 0, (-distance / 4) * 3)

    Debris:AddItem(bullet, 0.02)
    Debris:AddItem(bulletMini, 0.02)
    Debris:AddItem(bullet2, 0.04)
    Debris:AddItem(bulletMini2, 0.04)
end

local function VerifyHit(Hit : RaycastResult) 
    local HitInstance = Hit.Instance
    local PotentialCharacter = HitInstance:FindFirstAncestorOfClass("Model")
    if not PotentialCharacter then return end 
    local PotentialHumanoid = PotentialCharacter:FindFirstChildOfClass("Humanoid")

    if not PotentialHumanoid then print("hit not a human") return end 

    HitRemote:FireServer(PotentialCharacter, ThisTool.Name)
end 

local function Fire()
    if Waiting then return end 
    local Character = Player.Character
    if not Character then return end 
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return end 
    if Humanoid.Health <= 0 then return end 

    local RaycastParams = RaycastParams.new() 
    local Handle = ThisTool:FindFirstChild("Handle")
    if not Handle then return end 
    
    local FirePoint = Handle:FindFirstChild("FirePoint")
    if not FirePoint then return end 
    
    local Origin = FirePoint.WorldPosition 
    local Direction = (Mouse.Hit.Position - Origin).Unit * STD_RANGE

    RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
    RaycastParams.FilterDescendantsInstances = {
        Player.Character,
        ThisTool,
        workspace.Ignore, 
    }
    RaycastParams.IgnoreWater = true



    local Hit : RaycastResult = workspace:Raycast(Origin, Direction, RaycastParams)
    local HitPosition = if Hit then Hit.Position else (Origin + Direction)
    RenderShotTPS(FirePoint, HitPosition, Player.TeamColor)
    VerifyHit(Hit)
end

local function AutomaticFire()
    while IsFiring and ThisAmmo > 0 and not Waiting do
        Fire() 
        DecrementAmmo()
        task.wait(WeaponsConfig[ThisTool.Name].ROF)
    end
end

local function ClearConnections()
    for _, Connection in Connections do
        Connection:Disconnect()
        Connection = nil
    end

    table.clear(Connections)
end


local function CreateAutoConnections() -- makes input conns for an automatic weapon type 

    local AutoFireConnection = UIS.InputBegan:Connect(function(input, gameProcessedEvent)
        if gameProcessedEvent then return end 
    
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if not IsFiring then
               IsFiring = true 
            end 
            AutomaticFire()
        end
    end)
    
    local EndFireConnection = UIS.InputEnded:Connect(function(input, gameProcessedEvent)
        if gameProcessedEvent then return end 
    
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            IsFiring = false
            print("Stopped firing")
        end
    end)

    table.insert(Connections, AutoFireConnection)
    table.insert(Connections, EndFireConnection)    
end 

local function CreateSemiConnections() -- makes input conns for semi weapon type  

end 

local function CreateStandardConnections()

    local ReloadConnection = UIS.InputBegan:Connect(function(input, gameProcessedEvent)
        if gameProcessedEvent then return end 

        if input.KeyCode == Enum.KeyCode.R then
            print("got reload")
            Reload() 
        end
    end)

    table.insert(Connections, ReloadConnection)
end 

local function InitGun(Tool)
    ThisAmmo = tonumber(Tool:GetAttribute("Ammo"))
    ThisTool = Tool
    local GunType = tostring(Tool:GetAttribute("SubType"))

    if not ThisAmmo then
        return 
    end

    Mouse.TargetFilter = workspace.Ignore

    if GunType == "AutomaticGun" then
        print("making auto conns")
        CreateAutoConnections() 
    elseif GunType == "SemiGun" then 
        print("making semi connections")
        CreateSemiConnections()
    else -- default to semi
        CreateSemiConnections()
    end
    CreateStandardConnections()

end

local function UnequipGun(Tool)
    ThisTool = nil
    ClearConnections() 
end 

local function OnCharacterAdded(character : Model)

    character.ChildAdded:Connect(function(child)
        local WeaponAttr = tostring(child:GetAttribute("Type"))
        if WeaponAttr == "Gun" then
            InitGun(child)
        end
    end)

    character.ChildRemoved:Connect(function(child)
        local WeaponAttr = tostring(child:GetAttribute("Type"))
        if WeaponAttr == "Gun" then
            UnequipGun(child)
        end
    end)


end

Player.CharacterAdded:Connect(OnCharacterAdded)

if Player.Character then
    OnCharacterAdded(Player.Character) 
end

return GunController