-- validates sword hits from client, applies shield then health damage

local SwordServer = {}

local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local SwingRemote : RemoteEvent = game.ReplicatedStorage.Remotes.SwordSwing 
local ShieldConfig = require(game.ReplicatedStorage.Shared.ShieldConfig)

SwingRemote.OnServerEvent:Connect(function(player, Model, Humanoid : Humanoid, WeaponData)
    print("Swing Remote received")
    if not Model or not Humanoid then return end 

    local TargetShieldAttr = tonumber(Model:GetAttribute("Shield"))
    local TargetHealthAttr = Humanoid.Health

    if not TargetHealthAttr or not TargetHealthAttr then return end 
    if TargetHealthAttr <= 0 then return end 

    print("Passed checks")
    local Damage = WeaponData.Damage 

    -- shield absorbs first, leftover goes to health
    if Damage > TargetShieldAttr then
        print("taking shield then health")
        local RemainingDamage = Damage - TargetShieldAttr
        Model:SetAttribute("Shield", 0)
        Humanoid:TakeDamage(RemainingDamage)
        return
    else 
        print("taking shield only")
        Model:SetAttribute("Shield", math.clamp(TargetShieldAttr - Damage, 0, ShieldConfig.DEFAULT_SHIELD))
        return
    end

    return
end)

return SwordServer
