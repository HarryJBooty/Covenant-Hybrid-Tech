local HitRemote : RemoteEvent = game.ReplicatedStorage.Remotes.GunHit 
local WeaponConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local GunServer = {}

HitRemote.OnServerEvent:Connect(function(player, Target, Weapon : string)

    if not Target or typeof(Weapon) ~= "string" then return end

    local cfg = WeaponConfig[Weapon]
    local Damage = cfg.DamageBody 
    -- TODO:
    -- Damage player:
    -- If killed: log killer + killed 
    -- Fire client killed enemy event for kill indicators 
    -- Fire kill feed event

    if not Target then return end 

    local TargetHumanoid : Humanoid = Target:FindFirstChildOfClass("Humanoid")

    local TargetShield = tonumber(Target:GetAttribute("Shield"))
    if TargetShield == nil then
        TargetShield = 0 
    end
    local TargetHealth = TargetHumanoid.Health

    if Damage > TargetShield then
        Target:SetAttribute("Shield", 0)
        local remainder = Damage - TargetShield
        TargetHumanoid:TakeDamage(remainder)
    else 
        Target:SetAttribute("Shield", TargetShield - Damage)
    end
end)


return GunServer