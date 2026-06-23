-- movement tuning numbers, shared client + server

local MovementConfig = {
    Walk = {
        Walkspeed = 14,
        DefaultAnimation = "rbxassetid://91638669691966", -- 3rd person idle/walk
        LocalAnimation = "rbxassetid://89332954018990" -- viewmodel idle
    },

    Sprint = {
        Walkspeed = 20,
        ToggleKey = Enum.KeyCode.LeftShift,
        DefaultAnimation = "", -- todo: sprint anim
    },

    MoonMovement  = {
        Enabled = true,
        AirGravityScale = 0.3, -- lower = floatier (higher = less anti-gravity)
        JumpHeightMultiplier = 0.9,
    },

    Dash = {
        Distance = 10,
        Duration = 0.1,
        Cooldown = 1, -- client side lockout
        Recharge = 5, -- server regen per charge
        Uses = 2,
        ToggleKey = Enum.KeyCode.E,
        SoundEffect = "",
        LocalAnimations = {
            Forward = "rbxassetid://110733753326832",
            Backwards = "rbxassetid://72228040820840",
            Left = "rbxassetid://97229365987074",
            Right = "rbxassetid://97095623728087",
        },
        SwordAnimations = {
            Forward = "rbxassetid://91605093669816",
            Backwards = "rbxassetid://98013871485229",
            Left = "rbxassetid://107377379773288",
            Right = "rbxassetid://82205912435530",
        }
    },

    Grapple = {
        GrappleRange = 100,
        ToggleKey = Enum.KeyCode.Q,
        LocalAnimation = "rbxassetid://127112804819421",
        SwordAnimation = "rbxassetid://95039176681428",
        GunAnimation = "",
        SoundEffect = "rbxassetid://73256054215788"
    }
}

return MovementConfig
