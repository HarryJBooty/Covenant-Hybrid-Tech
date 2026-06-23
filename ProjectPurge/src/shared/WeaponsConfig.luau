-- weapon stats + animation ids

local WeaponsConfig = {

    ["Plasma Rifle"] = {
        DamageBody = 10,
        DamageHead = 14,
        DamageMelee = 50,
        Ammo = 50,
        Reload = 0.02,
    },

    ["Energy Sword"] = {
        Damage = 100,
        LungeDistance = 60, -- raycast range for lock-on cursor
        -- TODO: lunge movement tuning (used by SwordController.Lunge)
        -- LungeSpeed = 40,
        -- LungeStopDistance = 5,
        Ammo = 100,
        ParryWindow = 0.5,
        Animations = {
            Swing = "rbxassetid://127641094268918",
            Idle = "rbxassetid://105706163181264",
            Lunge = "rbxassetid://138470867002148",
        }
    },

    Hands = {
        DamageMelee = 50,
    }
}

return WeaponsConfig
