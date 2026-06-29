-- validates sword hits from client, applies shield then health damage

local SwordServer = {}

local PlayerService = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RemotesFolder = game.ReplicatedStorage.Remotes
local SwingRemote : RemoteEvent = RemotesFolder.SwordSwing 
local SetClashRemote : RemoteEvent = RemotesFolder.SetClash 
local LungeHitRemote : RemoteEvent = RemotesFolder:WaitForChild("LungeHit")

-- knockback is run on the owning client to avoid network-ownership desync (the "void" bug when airborne)
local ClashKnockbackRemote = RemotesFolder:FindFirstChild("ClashKnockback")
if not ClashKnockbackRemote then
    ClashKnockbackRemote = Instance.new("RemoteEvent")
    ClashKnockbackRemote.Name = "ClashKnockback"
    ClashKnockbackRemote.Parent = RemotesFolder
end

-- fired by the client on every swing so the woosh plays for everyone
local SwordSwungRemote = RemotesFolder:FindFirstChild("SwordSwung")
if not SwordSwungRemote then
    SwordSwungRemote = Instance.new("RemoteEvent")
    SwordSwungRemote.Name = "SwordSwung"
    SwordSwungRemote.Parent = RemotesFolder
end

-- server -> lunger: tells their client to abort the lunge (e.g. the target dashed out of the way)
local CancelLungeRemote = RemotesFolder:FindFirstChild("CancelLunge")
if not CancelLungeRemote then
    CancelLungeRemote = Instance.new("RemoteEvent")
    CancelLungeRemote.Name = "CancelLunge"
    CancelLungeRemote.Parent = RemotesFolder
end

local DashRemote : RemoteEvent = RemotesFolder:WaitForChild("Dash")

local ShieldConfig = require(game.ReplicatedStorage.Shared.ShieldConfig)
local WeaponsConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)

local SoundsFolder = game.ReplicatedStorage:FindFirstChild("Sounds")
local SwingSoundTemplate = SoundsFolder and SoundsFolder:FindFirstChild("Energy Sword Swing")
local HitSoundTemplate = SoundsFolder and SoundsFolder:FindFirstChild("Energy Sword Hit")

local ParryWindow = WeaponsConfig["Energy Sword"].ParryWindow or 0.5
-- bounce both players straight back by tweening their position, so ground friction can't eat the push
local PARRY_KNOCKBACK_DISTANCE = 10 -- studs each player slides away from the clash
local PARRY_KNOCKBACK_TIME = 0.18 -- short = snappy and powerful

-- generous on purpose: a fast lunge replicates with lag, and the client only fires once it is within 5 studs locally
local MAX_HIT_DISTANCE = 30 -- studs; melee reach sanity check on the server
local SwordDamage = WeaponsConfig["Energy Sword"].Damage
local CLASH_DAMAGE = SwordDamage / 4 -- chip damage per clash (1/4 base = 25), so you can't clash forever

local CLASH_GRACE = 0.3 -- keep a player clash eligible briefly after their lunge ends so two near simultaneous lunges still clash
local MAX_LUNGE_TIME = 6 -- hard cap: auto-clear CanClash even if the client never sends `false` (unequip/crash/exploit)
local SWING_PARRY_WINDOW = 0.4 -- after a swing, a player can still parry an incoming lunge for this long
local PARRY_REACTION_WINDOW = 0.15 -- hold lunge damage briefly so a defensive swing landing a hair later still clashes

local LastParry = {} -- character -> { Time, Partner }, debounces a clash across both swings
local ClashTokens = {} -- character -> token, guards the deferred CanClash clear
local LastSwing = {} -- character -> os.clock() of last swing, lets a swing parry an incoming lunge
local LungeDamageTokens = {} -- target character -> token, lets a parry cancel deferred lunge damage
local AttackCommitTime = {} -- character -> os.clock() they committed their current attack; lower = lunged/swung first
local LungeInfo = {} -- lunger character -> { Target = Model }, used so the target can dash-evade

local function GetEquippedSword(character : Model) : Tool?
    local tool = character:FindFirstChildOfClass("Tool")
    if tool and tool:GetAttribute("Type") == "Melee" then
        return tool
    end
    return nil
end

local function EnsureSwordAmmo(sword : Tool)
    local maxAmmo = tonumber(sword:GetAttribute("MaxAmmo")) or WeaponsConfig["Energy Sword"].Ammo or 0
    if sword:GetAttribute("MaxAmmo") == nil then
        sword:SetAttribute("MaxAmmo", maxAmmo)
    end
    if sword:GetAttribute("Ammo") == nil then
        sword:SetAttribute("Ammo", maxAmmo)
    end
end

local function TrySpendSwordAmmo(character : Model) : boolean
    local sword = GetEquippedSword(character)
    if not sword then
        return false
    end

    EnsureSwordAmmo(sword)
    local ammo = tonumber(sword:GetAttribute("Ammo")) or 0
    if ammo <= 0 then
        return false
    end

    sword:SetAttribute("Ammo", ammo - 1)
    return true
end

-- true if these two already clashed within the parry window
local function ParriedRecently(a, b, now)
    local rec = LastParry[a]
    return rec ~= nil and rec.Partner == b and (now - rec.Time) <= ParryWindow
end

-- true if this character swung recently enough to parry an incoming lunge
local function SwungRecently(character, now)
    local t = LastSwing[character]
    return t ~= nil and (now - t) <= SWING_PARRY_WINDOW
end

-- total damage a character can still soak (shield + health)
local function EffectiveHP(character : Model)
    local Shield = tonumber(character:GetAttribute("Shield")) or 0
    local Humanoid = character:FindFirstChildOfClass("Humanoid")
    local Health = Humanoid and Humanoid.Health or 0
    return Shield + Health
end

-- true if one more clash hit would kill them
local function InKillingDistance(character : Model)
    return EffectiveHP(character) <= CLASH_DAMAGE
end

-- slide one character straight back along the given (horizontal) direction by tweening its
-- position. driving the position instead of velocity means ground friction never gets to fight it.
local function KnockbackCharacter(character : Model, direction : Vector3)
    if not character then return end 
    local HumanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not HumanoidRootPart then return end 

    local Flat = Vector3.new(direction.X, 0, direction.Z)
    if Flat.Magnitude < 1e-3 then return end 
    Flat = Flat.Unit

    -- don't shove anyone into / through a wall: clip the distance to whatever is in the way
    local distance = PARRY_KNOCKBACK_DISTANCE
    local wallParams = RaycastParams.new()
    wallParams.FilterType = Enum.RaycastFilterType.Exclude
    wallParams.FilterDescendantsInstances = { character }
    wallParams.IgnoreWater = true
    local wallHit = workspace:Raycast(HumanoidRootPart.Position, Flat * (distance + 2), wallParams)
    if wallHit then
        distance = math.max((wallHit.Position - HumanoidRootPart.Position).Magnitude - 2, 0)
    end
    if distance < 1e-3 then return end 

    -- keep the same height + facing, only translate horizontally
    local rotation = HumanoidRootPart.CFrame - HumanoidRootPart.CFrame.Position
    local goalCFrame = CFrame.new(HumanoidRootPart.Position + Flat * distance) * rotation

    -- player characters are client owned; anchor + take ownership so the tween isn't fought by physics
    local Player = PlayerService:GetPlayerFromCharacter(character)
    if Player then
        pcall(function() HumanoidRootPart:SetNetworkOwner(nil) end)
    end

    local WasAnchored = HumanoidRootPart.Anchored
    HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    HumanoidRootPart.Anchored = true

    local Info = TweenInfo.new(PARRY_KNOCKBACK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local Tween = TweenService:Create(HumanoidRootPart, Info, { CFrame = goalCFrame })
    Tween:Play()

    Tween.Completed:Once(function()
        if HumanoidRootPart.Parent then
            HumanoidRootPart.Anchored = WasAnchored
            HumanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        end
        if Player and character.Parent and HumanoidRootPart.Parent then
            pcall(function() HumanoidRootPart:SetNetworkOwner(Player) end)
        end
    end)
end

-- push a character away from the clash. for real players we hand the bounce to their own client
-- (they own their physics) so the server never fights their prediction and flings them into the void.
local function PushCharacter(character : Model, direction : Vector3)
    local Player = PlayerService:GetPlayerFromCharacter(character)
    if Player then
        ClashKnockbackRemote:FireClient(Player, direction, PARRY_KNOCKBACK_DISTANCE, PARRY_KNOCKBACK_TIME)
    else
        KnockbackCharacter(character, direction) -- NPCs are server owned, drive them here
    end
end

local function ApplyParry(Char1 : Model, Char2 : Model)
    local Root1 = Char1:FindFirstChild("HumanoidRootPart")
    local Root2 = Char2:FindFirstChild("HumanoidRootPart")
    if not Root1 or not Root2 then return end 

    -- push each player directly away from the other, in opposite directions
    local Axis = Root1.Position - Root2.Position
    if Axis.Magnitude < 1e-3 then
        Axis = Root1.CFrame.LookVector -- fallback if they are stacked
    end

    -- only players who were actually lunging get knocked back. in a lunge-vs-lunge both bounce;
    -- when a defensive swing meets a lunge, the swinger holds their ground and only the lunger flies back.
    if Char1:GetAttribute("CanClash") then
        PushCharacter(Char1, Axis)
    end
    if Char2:GetAttribute("CanClash") then
        PushCharacter(Char2, -Axis)
    end
end

-- the target dashed out of our lock. don't kill the lunge outright: just drop the lock (so further
-- dashes can't keep re-triggering this) but KEEP CanClash set so a follow-up in-range LungeHit is
-- still honoured, then tell the lunger's client to commit to the target's last position.
local function RedirectLungeOnDash(lunger : Model)
    LungeInfo[lunger] = nil

    local LungerPlayer = PlayerService:GetPlayerFromCharacter(lunger)
    if LungerPlayer then
        CancelLungeRemote:FireClient(LungerPlayer)
    end
end

-- clone a sound onto the character and play it for everyone, cleaning up when it finishes
local function PlayGlobalSound(template : Sound?, character : Model?)
    if not template or not character then return end 
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end 

    local Sound = template:Clone()
    Sound.Parent = hrp
    Sound:Play()
    Sound.Ended:Once(function()
        Sound:Destroy()
    end)
end

-- shield absorbs first, leftover goes to health
local function DealDamage(Model : Model, Humanoid : Humanoid, amount : number)
    local TargetShieldAttr = tonumber(Model:GetAttribute("Shield")) or 0

    if amount > TargetShieldAttr then
        Model:SetAttribute("Shield", 0)
        Humanoid:TakeDamage(amount - TargetShieldAttr)
    else
        Model:SetAttribute("Shield", math.clamp(TargetShieldAttr - amount, 0, ShieldConfig.DEFAULT_SHIELD))
    end
end

local function ApplyDamage(Model : Model, Humanoid : Humanoid)
    DealDamage(Model, Humanoid, SwordDamage)
    PlayGlobalSound(HitSoundTemplate, Model)
end

-- resolve a clash between two characters exactly once. the LastParry debounce means whichever of
-- the two events (lunge-hit / swing) reaches the server first wins and the other becomes a no-op.
-- damage rules:
--   * normal clash: both take chip damage so they can't clash forever.
--   * if a clash hit would kill at least one of them it becomes decisive: whoever committed their
--     attack first wins and takes nothing; the one who committed last loses and eats the chip (and
--     dies if they were in killing distance). when both could die, first-to-commit still wins.
local function RegisterClash(CharA : Model, CharB : Model, now : number)
    if ParriedRecently(CharA, CharB, now) then return end
    LastParry[CharA] = { Time = now, Partner = CharB }
    LastParry[CharB] = { Time = now, Partner = CharA }

    local HumA = CharA:FindFirstChildOfClass("Humanoid")
    local HumB = CharB:FindFirstChildOfClass("Humanoid")

    if InKillingDistance(CharA) or InKillingDistance(CharB) then
        -- decisive: the later committer loses (a tie favours CharA, the side that triggered this)
        local TimeA = AttackCommitTime[CharA] or now
        local TimeB = AttackCommitTime[CharB] or now
        if TimeA <= TimeB then
            if HumB then DealDamage(CharB, HumB, CLASH_DAMAGE) end
        else
            if HumA then DealDamage(CharA, HumA, CLASH_DAMAGE) end
        end
    else
        if HumA then DealDamage(CharA, HumA, CLASH_DAMAGE) end
        if HumB then DealDamage(CharB, HumB, CLASH_DAMAGE) end
    end

    ApplyParry(CharA, CharB)
    PlayGlobalSound(HitSoundTemplate, CharA) -- clash reuses the hit sound, once from one side
end

PlayerService.PlayerRemoving:Connect(function(player)
    if player.Character then
        LastParry[player.Character] = nil
        ClashTokens[player.Character] = nil
        LastSwing[player.Character] = nil
        LungeDamageTokens[player.Character] = nil
        AttackCommitTime[player.Character] = nil
        LungeInfo[player.Character] = nil
    end
end)

-- dash-evade: dashing breaks the lunger's lock-on, but instead of cancelling outright we redirect
-- their lunge to where we were, so a short dodge still gets punished if it passes through our old
-- spot. runs alongside MovementServer's own dash-charge handler.
DashRemote.OnServerEvent:Connect(function(player)
    local Dasher = player.Character
    if not Dasher then return end 

    for Lunger, info in LungeInfo do
        if info.Target == Dasher and Lunger.Parent then
            RedirectLungeOnDash(Lunger)
        end
    end
end)

-- plain swing: validate target in reach, then either parry an incoming lunge or apply damage
SwingRemote.OnServerEvent:Connect(function(player, Model, Humanoid : Humanoid, WeaponData)
    local ThisChar = player.Character
    if not ThisChar then return end 
    if not Model or not Humanoid then return end 

    local TargetHealthAttr = Humanoid.Health
    if not TargetHealthAttr or TargetHealthAttr <= 0 then return end 

    local SelfRoot = ThisChar:FindFirstChild("HumanoidRootPart")
    local TargetRoot = Model:FindFirstChild("HumanoidRootPart")
    if not SelfRoot or not TargetRoot then return end 
    if (TargetRoot.Position - SelfRoot.Position).Magnitude > MAX_HIT_DISTANCE then return end 
    if not TrySpendSwordAmmo(ThisChar) then return end

    local Now = os.clock()
    -- swinging into a player who is mid-lunge parries it: clash instead of trading damage
    if Model:GetAttribute("CanClash") or ParriedRecently(ThisChar, Model, Now) then
        RegisterClash(ThisChar, Model, Now)
        return
    end

    ApplyDamage(Model, Humanoid)
end)

-- lunge connected: clash if the target is also lunging, otherwise damage them
LungeHitRemote.OnServerEvent:Connect(function(player, Model, Humanoid : Humanoid)
    local ThisChar = player.Character
    if not ThisChar then return end 
    if not Model or not Humanoid then return end 
    if not ThisChar:GetAttribute("CanClash") then return end -- only genuine lunges

    local TargetHealthAttr = Humanoid.Health
    if not TargetHealthAttr or TargetHealthAttr <= 0 then return end 

    local SelfRoot = ThisChar:FindFirstChild("HumanoidRootPart")
    local TargetRoot = Model:FindFirstChild("HumanoidRootPart")
    if not SelfRoot or not TargetRoot then return end 
    if (TargetRoot.Position - SelfRoot.Position).Magnitude > MAX_HIT_DISTANCE then return end 
    if not TrySpendSwordAmmo(ThisChar) then return end

    local Now = os.clock()
    -- immediate clash when the target is also mid-lunge, just swung at us, or we already clashed this pair
    if Model:GetAttribute("CanClash") or SwungRecently(Model, Now) or ParriedRecently(ThisChar, Model, Now) then
        RegisterClash(ThisChar, Model, Now)
        return
    end

    -- otherwise the lunge would damage a non-clashing target. hold the damage for a short reaction
    -- window so a defensive swing arriving a hair later (event order isn't guaranteed) still parries.
    local token = (LungeDamageTokens[Model] or 0) + 1
    LungeDamageTokens[Model] = token
    task.delay(PARRY_REACTION_WINDOW, function()
        if LungeDamageTokens[Model] ~= token then return end -- superseded by a newer lunge on this target
        LungeDamageTokens[Model] = nil

        local Later = os.clock()
        if ParriedRecently(ThisChar, Model, Later) then return end -- got parried in the window
        if Model:GetAttribute("CanClash") or SwungRecently(Model, Later) then
            RegisterClash(ThisChar, Model, Later)
            return
        end

        -- still a valid, in-range, living target?
        if not ThisChar.Parent or not Model.Parent then return end 
        if Humanoid.Health <= 0 then return end 
        local SelfRootNow = ThisChar:FindFirstChild("HumanoidRootPart")
        local TargetRootNow = Model:FindFirstChild("HumanoidRootPart")
        if not SelfRootNow or not TargetRootNow then return end 
        if (TargetRootNow.Position - SelfRootNow.Position).Magnitude > MAX_HIT_DISTANCE then return end 

        ApplyDamage(Model, Humanoid)
    end)
end)

-- every swing (hit or miss) plays the woosh for everyone, and arms the swing parry window
SwordSwungRemote.OnServerEvent:Connect(function(player)
    local Char = player.Character
    if Char then
        LastSwing[Char] = os.clock()
        -- a swing only counts as committing an attack if we aren't already mid-lunge (the lunge start
        -- already stamped an earlier, truer commit time we don't want this arrival swing to overwrite)
        if not Char:GetAttribute("CanClash") then
            AttackCommitTime[Char] = os.clock()
        end
    end
    PlayGlobalSound(SwingSoundTemplate, player.Character)
end)

SetClashRemote.OnServerEvent:Connect(function(player, state, Target)
    local Character = player.Character
    if not Character then return end

    if state == true then
        -- new lunge starting: flag immediately and invalidate any pending clear
        ClashTokens[Character] = (ClashTokens[Character] or 0) + 1
        local token = ClashTokens[Character]
        Character:SetAttribute("CanClash", true)
        AttackCommitTime[Character] = os.clock() -- stamp when this lunge was committed (for decisive clashes)

        -- remember who we're lunging at so they can dash-evade this lunge
        if typeof(Target) == "Instance" and Target:IsA("Model") then
            LungeInfo[Character] = { Target = Target }
        else
            LungeInfo[Character] = nil
        end

        -- safety net: a lunge can't last forever, so force the flag off after the max even if no
        -- `false` ever arrives. a newer lunge/clear bumps the token and cancels this.
        task.delay(MAX_LUNGE_TIME, function()
            if ClashTokens[Character] == token and Character then
                Character:SetAttribute("CanClash", false)
            end
        end)
    else
        LungeInfo[Character] = nil
        -- lunge ended: defer the clear so a slightly later lunge into us still reads CanClash.
        -- a fresh lunge bumps the token, which cancels this pending clear.
        local token = (ClashTokens[Character] or 0) + 1
        ClashTokens[Character] = token
        task.delay(CLASH_GRACE, function()
            if ClashTokens[Character] == token and Character then
                Character:SetAttribute("CanClash", false)
            end
        end)
    end
end)

return SwordServer
