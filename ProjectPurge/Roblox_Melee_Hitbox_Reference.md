# Roblox Melee Hitbox Reference

This is a practical reference for building a melee combat system with persistent spatial-query hitboxes instead of `.Touched` events. It is written for your energy sword / fast melee use case: short active windows, hitboxes that follow the weapon, reliable humanoid detection, duplicate-hit prevention, client responsiveness, and server validation.

Official docs used while writing this:

- WorldRoot spatial queries: https://create.roblox.com/docs/reference/engine/classes/WorldRoot
- RaycastParams: https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams
- OverlapParams: https://create.roblox.com/docs/reference/engine/datatypes/OverlapParams
- RaycastResult: https://create.roblox.com/docs/reference/engine/datatypes/RaycastResult
- RunService: https://create.roblox.com/docs/reference/engine/classes/RunService
- RemoteEvent: https://create.roblox.com/docs/reference/engine/classes/RemoteEvent
- UnreliableRemoteEvent: https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent
- Client/server runtime: https://create.roblox.com/docs/projects/client-server
- Remote events guide: https://create.roblox.com/docs/scripting/events/remote
- BasePart, including `CanQuery`, `CanCollide`, and network ownership APIs: https://create.roblox.com/docs/reference/engine/classes/BasePart
- PhysicsService / collision groups: https://create.roblox.com/docs/reference/engine/classes/PhysicsService
- CollectionService tags: https://create.roblox.com/docs/reference/engine/classes/CollectionService
- CFrame: https://create.roblox.com/docs/reference/engine/datatypes/CFrame
- Vector3: https://create.roblox.com/docs/reference/engine/datatypes/Vector3

## Mental Model

For melee, you usually do not want physics contact events. You want to ask the world a question during the swing:

> "Which valid enemy parts are inside, or crossed by, this sword-shaped volume right now?"

Your hitbox is not necessarily a real visible part. It can be just:

- A `CFrame` describing the hitbox center and rotation.
- A `Vector3` describing the box size.
- A filter object (`OverlapParams` or `RaycastParams`).
- A loop that queries during the active swing frames.
- A per-swing record of what humanoids were already hit.

For an energy sword:

- The client can start the swing immediately for responsiveness.
- The server should be the authority for real damage.
- The server should validate timing, range, weapon state, and candidate targets.
- You should not trust a client saying "I hit this humanoid" without checking.

## Which API Should I Use?

### `workspace:GetPartBoundsInBox(cframe, size, overlapParams)`

Use this for most lingering melee hitboxes.

What it does:

- Returns an array of parts whose bounding boxes overlap the box.
- The box is defined by a center/rotation `CFrame` and a `Vector3` size.
- Uses `OverlapParams`.
- Good for "active hitbox exists for 0.1 seconds and checks every frame."

Important:

- It checks part bounding boxes, not the exact mesh shape.
- This is fast and usually good enough for humanoid hit detection.
- For swords, this is usually the best starting point.

Example:

```lua
local overlapParams = OverlapParams.new()
overlapParams.ExcludeInstances = { attackerCharacter }
overlapParams.MaxParts = 50

local boxCFrame = blade.CFrame * CFrame.new(0, 0, -2)
local boxSize = Vector3.new(4, 5, 6)

local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlapParams)
for _, part in parts do
    local model = part:FindFirstAncestorOfClass("Model")
    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        -- candidate hit
    end
end
```

### `workspace:Blockcast(cframe, size, direction, raycastParams)`

Use this when the hitbox moves fast and you want to detect what the box sweeps through between two positions.

What it does:

- Casts a box shape from a starting `CFrame` along a direction.
- Returns only the first hit as a `RaycastResult`.
- Uses `RaycastParams`, not `OverlapParams`.

Important:

- It does not detect parts that are already intersecting the box at the starting position.
- It returns the first eligible hit only.
- Useful for preventing tunneling when the sword moves far between frames.
- Less convenient if you want every enemy inside a wide sword arc.

Example:

```lua
local raycastParams = RaycastParams.new()
raycastParams.ExcludeInstances = { attackerCharacter }

local previousCFrame = lastBoxCFrame
local currentCFrame = blade.CFrame * CFrame.new(0, 0, -2)
local direction = currentCFrame.Position - previousCFrame.Position

if direction.Magnitude > 0 then
    local result = workspace:Blockcast(previousCFrame, boxSize, direction, raycastParams)
    if result then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        if humanoid then
            -- candidate swept hit
        end
    end
end
```

### `workspace:GetPartsInPart(part, overlapParams)`

Use this when you need exact part geometry overlap and can afford more cost.

What it does:

- Takes a real `BasePart` in the world.
- Returns parts whose actual occupied volume overlaps it.
- More accurate than `GetPartBoundsInBox`, usually slower.

Important:

- Requires a real part.
- Good for special cases, not usually necessary for normal sword swings.
- If you only need a box volume, `GetPartBoundsInBox` is simpler.

### `workspace:Raycast(origin, direction, raycastParams)`

Use this for line checks:

- Crosshair aim.
- Lunge target selection.
- Wall checks.
- Confirming line-of-sight.
- Finding the exact first surface hit.

Do not use a single ray as your entire sword hitbox unless the sword is intentionally needle-thin. A melee weapon has volume.

### `workspace:Spherecast(position, radius, direction, raycastParams)`

Use this for swept spheres:

- Punches.
- Shoulder charges.
- Simple lunges.
- Projectiles with thickness.

It is less naturally sword-shaped than a box, but useful for rounded attacks.

### `workspace:Shapecast(part, direction, raycastParams)`

Use this when you already have a real part whose shape should be swept.

For beginner melee systems, `GetPartBoundsInBox` plus optional `Blockcast` is usually easier to understand and debug.

## Overlap Checks vs Blockcasts

Use overlap checks when:

- The hitbox lingers for multiple frames.
- You want all humanoids inside the active volume.
- You want an AOE-like melee box.
- You want duplicate-hit prevention across the whole active window.
- You want simple "every frame, who is in this box?" logic.

Use blockcasts when:

- The sword or character moves quickly enough to skip over targets between frames.
- You need swept motion from previous position to current position.
- You want to catch tunneling.

For fast melee, a strong pattern is:

1. Each tick, run `GetPartBoundsInBox` at the current blade/hitbox position.
2. Also optionally `Blockcast` from the previous box position to the current one.
3. Feed both results into the same `tryHitHumanoid` function.
4. Use one per-swing `alreadyHit` table so the same humanoid cannot be damaged twice.

## Important Query Parameter Objects

### `OverlapParams`

Used by:

- `GetPartBoundsInBox`
- `GetPartBoundsInRadius`
- `GetPartsInPart`

Useful properties:

- `ExcludeInstances`: instances and descendants to ignore.
- `IncludeInstances`: only these instances and descendants are considered.
- `MaxParts`: limit returned parts. `0` means no limit.
- `CollisionGroup`: use collision-group filtering.
- `RespectCanCollide`: if true, query uses `CanCollide` instead of `CanQuery`.
- `Tolerance`: expands the query volume slightly, clamped between `0` and `0.05`.

Modern docs prefer `ExcludeInstances` and `IncludeInstances`. Older code often uses `FilterDescendantsInstances` and `FilterType`. They still exist, but for new code prefer the newer names.

Typical melee setup:

```lua
local params = OverlapParams.new()
params.ExcludeInstances = {
    attackerCharacter,
    workspace.CurrentCamera,
}
params.MaxParts = 50
params.RespectCanCollide = false
```

### `RaycastParams`

Used by:

- `Raycast`
- `Blockcast`
- `Spherecast`
- `Shapecast`

Useful properties:

- `ExcludeInstances`
- `IncludeInstances`
- `IgnoreWater`
- `CollisionGroup`
- `RespectCanCollide`

Typical melee/blockcast setup:

```lua
local params = RaycastParams.new()
params.ExcludeInstances = { attackerCharacter }
params.IgnoreWater = true
params.RespectCanCollide = false
```

## `CanQuery`, `CanCollide`, and Collision Groups

Spatial queries care about whether parts are queryable.

Important `BasePart` properties:

- `CanCollide`: whether the part physically collides.
- `CanTouch`: whether touch events work.
- `CanQuery`: whether spatial queries include the part.

For hitboxes and combat detection:

- Enemy body parts should normally have `CanQuery = true`.
- Invisible helper parts can have `CanCollide = false`, `CanTouch = false`, but still `CanQuery = true` if you want queries to find them.
- Pure visual parts that should never be hit can use `CanQuery = false`.

Collision groups can make query filtering much cleaner:

- Put players in a `"Characters"` group.
- Put sword visuals in a `"Weapons"` group.
- Put hitbox helper parts in a `"Hitboxes"` group if you use real parts.
- Use `OverlapParams.CollisionGroup` or `RaycastParams.CollisionGroup` so the query follows your collision matrix.

If your query misses parts unexpectedly, check:

- Is the part inside the filter include/exclude rules?
- Is `CanQuery` true?
- Is the collision group allowed?
- Is the part streamed in on the client?
- Are you doing the query on the server or client?

## Timing: `Heartbeat`, `PreSimulation`, `PostSimulation`, and Render Events

For melee hit detection:

- Server damage validation usually belongs on `RunService.Heartbeat` or `RunService.PostSimulation`.
- Client visuals can use `RenderStepped` / `BindToRenderStep`.
- Do not put expensive server combat logic in client-only render events.

Official docs summary:

- `RenderStepped` / `PreRender`: before the frame is drawn; client visual work.
- `PreSimulation`: before physics simulation.
- `PostSimulation`: after physics simulation.
- `Heartbeat`: after physics simulation; common for general gameplay systems.

Practical recommendation:

- Client: animate sword, play VFX, maybe local predictive hit sparks.
- Server: during active swing windows, run authoritative overlap checks on `Heartbeat` or `PostSimulation`.

Example active swing loop:

```lua
local RunService = game:GetService("RunService")

local function runSwingHitbox(attackerCharacter, blade, duration)
    local startTime = os.clock()
    local alreadyHit = {}
    local connection

    connection = RunService.Heartbeat:Connect(function()
        if os.clock() - startTime >= duration then
            connection:Disconnect()
            return
        end

        -- run spatial query here
    end)
end
```

## Basic Persistent Box Hitbox

This is the core pattern for a lingering sword hitbox.

```lua
local RunService = game:GetService("RunService")

local HITBOX_SIZE = Vector3.new(5, 5, 7)
local HITBOX_OFFSET = CFrame.new(0, 0, -3)
local ACTIVE_TIME = 0.15

local function findHumanoidFromPart(part: BasePart): Humanoid?
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then
        return nil
    end
    return model:FindFirstChildOfClass("Humanoid")
end

local function startSwordHitbox(attackerCharacter: Model, blade: BasePart)
    local params = OverlapParams.new()
    params.ExcludeInstances = { attackerCharacter }
    params.MaxParts = 50

    local hitHumanoids: { [Humanoid]: boolean } = {}
    local startTime = os.clock()
    local connection

    connection = RunService.Heartbeat:Connect(function()
        if os.clock() - startTime > ACTIVE_TIME then
            connection:Disconnect()
            return
        end

        local hitboxCFrame = blade.CFrame * HITBOX_OFFSET
        local parts = workspace:GetPartBoundsInBox(hitboxCFrame, HITBOX_SIZE, params)

        for _, part in parts do
            local humanoid = findHumanoidFromPart(part)
            if humanoid and not hitHumanoids[humanoid] then
                if humanoid.Health > 0 and humanoid.Parent ~= attackerCharacter then
                    hitHumanoids[humanoid] = true
                    humanoid:TakeDamage(50)
                end
            end
        end
    end)
end
```

This works because:

- The query follows `blade.CFrame`.
- The active window lasts a short time.
- `hitHumanoids` prevents repeated hits during one swing.
- The attacker is excluded.

## Adding Swept Detection for Fast Swings

If the sword moves very fast, a box at frame N and a box at frame N+1 can skip over a target. Add a blockcast from the previous box center to the current box center.

```lua
local previousCFrame: CFrame? = nil

connection = RunService.Heartbeat:Connect(function()
    local currentCFrame = blade.CFrame * HITBOX_OFFSET

    -- Current overlap
    local parts = workspace:GetPartBoundsInBox(currentCFrame, HITBOX_SIZE, overlapParams)
    for _, part in parts do
        tryHitPart(part)
    end

    -- Swept box from previous frame to this frame
    if previousCFrame then
        local travel = currentCFrame.Position - previousCFrame.Position
        if travel.Magnitude > 0 then
            local result = workspace:Blockcast(previousCFrame, HITBOX_SIZE, travel, raycastParams)
            if result then
                tryHitPart(result.Instance)
            end
        end
    end

    previousCFrame = currentCFrame
end)
```

Limitations:

- `Blockcast` returns the first hit only.
- `Blockcast` does not detect parts already intersecting the starting box.
- Keep the overlap check too.

For a very wide arc, you can also sample multiple boxes along the sword path:

```lua
local function sampleCFrame(a: CFrame, b: CFrame, alpha: number): CFrame
    return a:Lerp(b, alpha)
end

for i = 0, 3 do
    local alpha = i / 3
    local sample = sampleCFrame(previousCFrame, currentCFrame, alpha)
    local parts = workspace:GetPartBoundsInBox(sample, HITBOX_SIZE, overlapParams)
    for _, part in parts do
        tryHitPart(part)
    end
end
```

This is a simple way to make "arcs" feel less miss-prone.

## Following the Weapon / Blade Orientation

If the blade is a `BasePart`, the simplest hitbox is:

```lua
local boxCFrame = blade.CFrame * localOffset
```

`localOffset` is a `CFrame` in the blade's local space. For example:

```lua
local localOffset = CFrame.new(0, 0, -3)
```

That means "place the hitbox 3 studs along the blade's local negative Z axis."

Use Studio debug parts while tuning:

```lua
local debugPart = Instance.new("Part")
debugPart.Anchored = true
debugPart.CanCollide = false
debugPart.CanQuery = false
debugPart.Transparency = 0.7
debugPart.Color = Color3.fromRGB(255, 0, 0)
debugPart.Size = HITBOX_SIZE
debugPart.CFrame = boxCFrame
debugPart.Parent = workspace
```

Delete or disable debug parts in production.

## Duplicate-Hit Prevention

Never damage the same humanoid every query tick unless the attack is meant to multi-hit.

Use one table per swing:

```lua
local alreadyHit: { [Humanoid]: boolean } = {}

local function tryHitHumanoid(humanoid: Humanoid)
    if alreadyHit[humanoid] then
        return
    end

    alreadyHit[humanoid] = true
    humanoid:TakeDamage(50)
end
```

If you want one hit per target every X seconds instead:

```lua
local lastHitTime: { [Humanoid]: number } = {}
local HIT_COOLDOWN = 0.25

local function tryHitHumanoid(humanoid)
    local now = os.clock()
    local last = lastHitTime[humanoid]

    if last and now - last < HIT_COOLDOWN then
        return
    end

    lastHitTime[humanoid] = now
    humanoid:TakeDamage(10)
end
```

For normal sword swings, per-swing duplicate prevention is usually better.

## Finding the Actual Character Hit

Spatial queries return parts, not humanoids. Convert parts into humanoids:

```lua
local function getHumanoidFromPart(part: Instance): (Humanoid?, Model?)
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then
        return nil, nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return nil, nil
    end

    return humanoid, model
end
```

Then validate:

```lua
local humanoid, model = getHumanoidFromPart(part)
if not humanoid then return end
if model == attackerCharacter then return end
if humanoid.Health <= 0 then return end
```

Optional extra validation:

- Check teams.
- Check invincibility attributes.
- Check parry/block state.
- Check distance from attacker.
- Check line of sight if needed.

## Client Responsiveness and Server Validation

Roblox is client-server. The server is the authority for real game state.

Client responsibilities:

- Start animation instantly.
- Show local swing VFX.
- Play swing sounds.
- Optionally do local predictive hit sparks/crosshair feedback.
- Fire a `RemoteEvent` to request a swing.

Server responsibilities:

- Check the player is allowed to swing.
- Check the weapon is equipped.
- Check cooldowns, ammo/energy, stun state, etc.
- Run authoritative hit detection.
- Apply real damage.
- Replicate hit effects to other clients.

Good flow:

1. Client presses attack.
2. Client immediately plays animation and sword trail.
3. Client fires `SwingRequest` remote with minimal data, such as weapon id and client timestamp.
4. Server validates state.
5. Server starts a hitbox window tied to the server's weapon/character state.
6. Server applies damage.
7. Server fires hit confirmation / VFX remotes.

Do not do this:

```lua
-- Bad security pattern
RemoteEvent:FireServer(targetHumanoid, damage)
```

A cheater can send any target and damage. Instead, send intent:

```lua
-- Better
SwingRequest:FireServer("EnergySwordLight")
```

Then the server decides who, if anyone, was hit.

## RemoteEvent vs UnreliableRemoteEvent

Use `RemoteEvent` for:

- Swing requests.
- Damage confirmations.
- Important combat events.
- Anything that must arrive.

Use `UnreliableRemoteEvent` for:

- Cosmetic trails.
- Repeated aim updates.
- Non-critical VFX.
- Things that can be dropped without breaking gameplay.

Official docs note:

- Remote events are asynchronous and do not yield.
- Client-to-server remotes have rate limits.
- Unreliable remotes can arrive out of order or not arrive at all.
- Unreliable remote payloads larger than 1000 bytes are dropped.

For your melee system, `RemoteEvent` is the safe default.

## Latency and Fairness

Most players experience around 100-300 ms of latency. That means:

- Client hit feedback should feel immediate.
- Server damage may happen slightly later.
- Server positions may not perfectly match what the attacker saw.

Common melee validation approaches:

### Strict server-only hit detection

The server runs the hitbox from current server positions.

Pros:

- Most secure.
- Simple mental model.

Cons:

- Can feel unfair at high ping.
- Player may see a clear sword hit locally but server misses.

### Client-predicted, server-validated

The client does local hit detection for feedback, but the server still validates.

Client can say:

```lua
SwingHitReport:FireServer(attackId, targetModel, approximateHitTime)
```

Server checks:

- Was this attack active?
- Was this target near the sword/attacker?
- Is the target alive and valid?
- Is the target within a reasonable max range?
- Was the report received within a small allowed time window?

Pros:

- Feels responsive.
- Server still blocks obvious cheats.

Cons:

- More complex.
- Requires careful tolerance tuning.

### Recommended for your stage

Start with server-authoritative hitboxes. Add local predictive VFX only. Once the system works, consider allowing client-reported candidates that the server validates.

## Server Validation Checklist

When the server receives a swing request:

- Does the player have a character?
- Does the character have a humanoid and root part?
- Is the humanoid alive?
- Is the correct weapon equipped?
- Is the weapon allowed to swing right now?
- Is the player stunned, dead, grappling, sprint-locked, or otherwise unable?
- Is the swing cooldown ready?
- Is the attack id valid?
- Is the requested attack plausible for the current weapon?

When the server detects a hit:

- Is the target a different character?
- Is the target humanoid alive?
- Is the target within maximum range?
- Has this swing already hit that humanoid?
- Is the target on an enemy team?
- Is the target invincible, blocking, parrying, or shielded?
- Should this be body damage, shield damage, parry, lunge, etc.?

## Suggested Module Architecture

For your current project style, a good split would be:

- `WeaponConfig`: damage, cooldown, hitbox size, active time, offsets.
- `MeleeHitboxService` or `HitboxController`: shared hitbox creation/query logic.
- `SwordController`: input, equip/unequip, client visuals.
- `CombatServer`: validates swing requests and applies damage.
- `ViewController`: camera/viewmodel only.
- `ViewModelAnimations`: viewmodel animation playback only.

The hitbox module should not care about the energy sword specifically. It should accept a config.

Example config:

```lua
local WeaponConfig = {
    EnergySword = {
        Damage = 100,
        ActiveTime = 0.14,
        QueryRate = "Heartbeat",
        HitboxSize = Vector3.new(5, 5, 7),
        HitboxOffset = CFrame.new(0, 0, -3),
        MaxParts = 50,
        CanHitSameTargetOnce = true,
    },
}
```

## Example Hitbox Module Skeleton

```lua
local RunService = game:GetService("RunService")

local MeleeHitbox = {}

export type HitboxConfig = {
    Size: Vector3,
    Offset: CFrame,
    ActiveTime: number,
    MaxParts: number?,
    UseSweep: boolean?,
}

local function getHumanoidFromPart(part: Instance): Humanoid?
    local model = part:FindFirstAncestorOfClass("Model")
    return model and model:FindFirstChildOfClass("Humanoid")
end

function MeleeHitbox.Start(attackerCharacter: Model, blade: BasePart, config: HitboxConfig, onHit: (Humanoid, BasePart) -> ())
    local overlapParams = OverlapParams.new()
    overlapParams.ExcludeInstances = { attackerCharacter }
    overlapParams.MaxParts = config.MaxParts or 50

    local raycastParams = RaycastParams.new()
    raycastParams.ExcludeInstances = { attackerCharacter }

    local alreadyHit: { [Humanoid]: boolean } = {}
    local previousCFrame: CFrame? = nil
    local startTime = os.clock()
    local connection

    local function tryPart(part: BasePart)
        local humanoid = getHumanoidFromPart(part)
        if not humanoid then return end
        if humanoid.Health <= 0 then return end
        if alreadyHit[humanoid] then return end

        alreadyHit[humanoid] = true
        onHit(humanoid, part)
    end

    connection = RunService.Heartbeat:Connect(function()
        if os.clock() - startTime > config.ActiveTime then
            connection:Disconnect()
            return
        end

        local currentCFrame = blade.CFrame * config.Offset
        local parts = workspace:GetPartBoundsInBox(currentCFrame, config.Size, overlapParams)

        for _, part in parts do
            tryPart(part)
        end

        if config.UseSweep and previousCFrame then
            local travel = currentCFrame.Position - previousCFrame.Position
            if travel.Magnitude > 0 then
                local result = workspace:Blockcast(previousCFrame, config.Size, travel, raycastParams)
                if result then
                    tryPart(result.Instance)
                end
            end
        end

        previousCFrame = currentCFrame
    end)

    return connection
end

return MeleeHitbox
```

Server usage:

```lua
MeleeHitbox.Start(character, swordBlade, swordConfig, function(humanoid, hitPart)
    humanoid:TakeDamage(swordConfig.Damage)
end)
```

## Active Windows and Animation Markers

For clean melee, do not make the hitbox active for the whole animation. Use active frames:

- Windup: no hitbox.
- Active: hitbox runs.
- Recovery: no hitbox.

In Roblox animations, you can use animation markers to tell scripts when the damage window starts and ends.

Pseudo-flow:

```lua
local track = animator:LoadAnimation(swingAnimation)

track:GetMarkerReachedSignal("HitStart"):Connect(function()
    startHitbox()
end)

track:GetMarkerReachedSignal("HitEnd"):Connect(function()
    stopHitbox()
end)

track:Play()
```

If you do not use markers yet, use timed delays:

```lua
track:Play()
task.delay(0.12, function()
    startHitbox()
end)
task.delay(0.26, function()
    stopHitbox()
end)
```

Markers are better long term because the timing lives in the animation.

## Lunge / Lock-On Attacks

For Halo-style energy sword lunges:

1. Client finds target candidate under crosshair with a raycast.
2. Server validates target is alive, enemy, visible, and within `LungeDistance`.
3. Server moves attacker or applies a controlled velocity.
4. During lunge, run a slightly larger hitbox or a spherecast/box overlap.

Do not rely on one raycast for the actual lunge damage. Use the raycast for target selection, then a proper server hitbox for damage.

Validation checks:

```lua
local distance = (targetRoot.Position - attackerRoot.Position).Magnitude
if distance > WeaponConfig.EnergySword.LungeDistance then
    return
end
```

Line-of-sight check:

```lua
local direction = targetRoot.Position - attackerRoot.Position
local result = workspace:Raycast(attackerRoot.Position, direction, raycastParams)
if result and not result.Instance:IsDescendantOf(targetCharacter) then
    return
end
```

## Performance Guidelines

Do:

- Reuse `OverlapParams` and `RaycastParams` where possible.
- Keep active windows short.
- Use `MaxParts` when you can.
- Exclude the attacker's character.
- Prefer `GetPartBoundsInBox` for simple melee volumes.
- Use collision groups or include filters to reduce candidate parts.
- Convert parts to humanoids once per part, then dedupe by humanoid.
- Disconnect loops when the swing ends.
- Avoid printing every frame in live gameplay.

Avoid:

- Running queries forever when no attack is active.
- Creating/destroying debug parts every frame in production.
- Using `.Touched` for high-speed weapons.
- Trusting client damage reports.
- Querying the whole world without filters in a crowded game.
- `BruteForceAllSlow` in live experiences.

## Debugging Hitboxes

Useful debug tools:

- Draw transparent parts at the queried box CFrame.
- Print hitbox CFrame/size only when a debug flag is enabled.
- Print every humanoid candidate and why it was accepted/rejected.
- Log the attack id and already-hit table.
- Test with artificial network latency in Studio settings.

Debug visualization:

```lua
local DEBUG_HITBOXES = true

local function drawDebugBox(cframe: CFrame, size: Vector3, lifetime: number?)
    if not DEBUG_HITBOXES then return end

    local part = Instance.new("Part")
    part.Name = "DebugHitbox"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Transparency = 0.75
    part.Color = Color3.fromRGB(255, 0, 0)
    part.Size = size
    part.CFrame = cframe
    part.Parent = workspace

    task.delay(lifetime or 0.05, function()
        if part then
            part:Destroy()
        end
    end)
end
```

## Common Bugs and Fixes

### "My hitbox does not hit anything"

Check:

- Is the query running?
- Is the box CFrame where you think it is?
- Is the size large enough?
- Are enemy parts `CanQuery = true`?
- Are you excluding the enemy accidentally?
- Is `IncludeInstances = {}` set? Empty include list means include nothing.
- Are you querying on the client with StreamingEnabled and the target is not streamed in?

### "It hits myself"

Set:

```lua
params.ExcludeInstances = { attackerCharacter }
```

Also check that weapon/viewmodel parts are excluded if they are in workspace.

### "It hits the same enemy many times"

Use a per-swing `alreadyHit` table keyed by humanoid:

```lua
if alreadyHit[humanoid] then return end
alreadyHit[humanoid] = true
```

### "It misses fast targets"

Use:

- Larger hitbox.
- Multiple samples between previous and current CFrame.
- `Blockcast` sweep from previous to current.
- Slight `OverlapParams.Tolerance`.
- Server-side validation with small latency allowance.

### "Blockcast misses something already inside the sword"

This is expected. Official docs note that shapecasts like `Blockcast` do not detect parts initially intersecting the shape. Keep the current-frame overlap check too.

### "My server hit detection feels delayed"

Expected under latency. Use client prediction for visuals, but server validation for damage.

### "My client sees a hit but server says no"

Possible causes:

- Server target position differs because of latency.
- Server hitbox timing differs from animation timing.
- The hitbox is too small.
- Server and client use different offsets/sizes.
- Client target is streamed differently.

Fix by keeping one shared config module for hitbox sizes/timing and optionally allowing small server validation tolerance.

## Recommended Starting Design for Your Project

For an energy sword:

1. Store sword hitbox data in `WeaponsConfig`.
2. On client input, play animation immediately and fire `SwingRequest`.
3. On server, validate and start a hitbox window.
4. During the active window, run `GetPartBoundsInBox` every `Heartbeat`.
5. Optionally add `Blockcast` or multi-sampling for fast swings.
6. Use `alreadyHit` per swing.
7. Apply damage only on the server.
8. Fire cosmetic hit effects to clients.

Good first implementation:

- Server only applies damage.
- Client only handles visuals.
- Use `GetPartBoundsInBox`.
- Add debug box drawing until the hitbox feels right.

Then upgrade:

- Add blockcast/multi-sampling.
- Add animation markers.
- Add client-predicted hit sparks.
- Add parry/block rules.
- Add lunge validation.

## Quick API Memory Sheet

`GetPartBoundsInBox(cframe, size, overlapParams)`

- "Who is inside this box right now?"
- Returns many parts.
- Good for lingering melee hitboxes.

`Blockcast(cframe, size, direction, raycastParams)`

- "What does this box hit as it moves from here along this direction?"
- Returns first hit only.
- Good for sweep/tunneling prevention.

`Raycast(origin, direction, raycastParams)`

- "What is the first thing along this line?"
- Good for aim/line-of-sight, not full sword volume.

`OverlapParams`

- Used for overlap queries.
- Use `ExcludeInstances`, `IncludeInstances`, `MaxParts`, `CollisionGroup`.

`RaycastParams`

- Used for raycasts and shapecasts.
- Use `ExcludeInstances`, `IncludeInstances`, `IgnoreWater`, `CollisionGroup`.

`CanQuery`

- If false, spatial queries never include the part.

`RemoteEvent`

- Reliable one-way communication.
- Use for swing requests and damage events.

`UnreliableRemoteEvent`

- Unordered and can drop messages.
- Use only for non-critical VFX/aim spam.

`RunService.Heartbeat`

- Common server gameplay loop after physics.

`RenderStepped` / `BindToRenderStep`

- Client visual updates before rendering.

## Final Practical Advice

Start simple:

```lua
-- Server:
-- active for 0.12 seconds
-- every Heartbeat:
-- box follows sword blade
-- GetPartBoundsInBox
-- dedupe humanoids
-- TakeDamage
```

Do not overbuild the perfect Ultrakill/Halo melee system first. Make the hitbox visible with debug boxes, get damage correct, then improve feel with client prediction and swept checks.

Once your sword feels reliable at normal speed, test with:

- High player speed.
- High enemy speed.
- 100-300 ms simulated latency.
- Multiple targets inside the swing.
- Unequip/death during swing.
- Blocking/parrying/shield edge cases.

If the hitbox survives those tests, the architecture is probably solid.
