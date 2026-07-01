local WeaponsConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local PlayerService = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Player = PlayerService.LocalPlayer


local Connections : {RBXScriptConnection} = {} 
local ThisTool = nil 
local IsFiring = false
local ThisAmmo 
local Waiting = false

local GunController = {}

local function DecrementAmmo() 
    if ThisAmmo == nil then return end 

    ThisAmmo = ThisAmmo - 1 
    ThisTool:SetAttribute("Ammo", ThisAmmo)
end 

local function Fire()
    print("bang bang")
end

local function AutomaticFire()
    while IsFiring and ThisAmmo > 0 and not Waiting do
        Fire() 
        DecrementAmmo()
        task.wait(WeaponsConfig["Plasma Rifle"].ROF)
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

local function InitGun(Tool)
    ThisAmmo = tonumber(Tool:GetAttribute("Ammo"))
    ThisTool = Tool
    local GunType = tostring(Tool:GetAttribute("SubType"))

    if not ThisAmmo then
        return 
    end


    if GunType == "AutomaticGun" then
        print("making auto conns")
        CreateAutoConnections() 
    elseif GunType == "SemiGun" then 
        print("making semi connections")
        CreateSemiConnections()
    else -- default to semi
        CreateSemiConnections()
    end

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