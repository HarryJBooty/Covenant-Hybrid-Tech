# Roblox Gun System Reference

This is a practical reference for building a hitscan / energy-weapon gun system in Roblox: aim from camera or crosshair, raycast for hits, show tracers and impacts, apply server-authoritative damage with head/body multipliers, and keep the client responsive without trusting client hit claims.

Written for your **Plasma Rifle** use case (see `WeaponsConfig.luau`: `DamageBody`, `DamageHead`, ammo, reload) and the same client/server split you already use for the energy sword.

Official docs used while writing this:

- Raycasting guide: https://create.roblox.com/docs/workspace/raycasting
- WorldRoot spatial queries: https://create.roblox.com/docs/reference/engine/classes/WorldRoot
- RaycastParams: https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams
- RaycastResult: https://create.roblox.com/docs/reference/engine/datatypes/RaycastResult
- Camera (aim rays): https://create.roblox.com/docs/reference/engine/classes/Camera
- UserInputService (cursor / mouse): https://create.roblox.com/docs/reference/engine/classes/UserInputService
- Mouse (legacy pointer ray): https://create.roblox.com/docs/reference/engine/classes/Mouse
- GuiService (screen insets): https://create.roblox.com/docs/reference/engine/classes/GuiService
- Humanoid (damage): https://create.roblox.com/docs/reference/engine/classes/Humanoid
- BasePart (`CanQuery`, collision): https://create.roblox.com/docs/reference/engine/classes/BasePart
- PhysicsService / collision groups: https://create.roblox.com/docs/reference/engine/classes/PhysicsService
- Beam (tracers): https://create.roblox.com/docs/reference/engine/classes/Beam
- Attachment: https://create.roblox.com/docs/reference/engine/classes/Attachment
- Trail: https://create.roblox.com/docs/reference/engine/classes/Trail
- ParticleEmitter: https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter
- Debris (VFX cleanup): https://create.roblox.com/docs/reference/engine/classes/Debris
- RunService: https://create.roblox.com/docs/reference/engine/classes/RunService
- RemoteEvent: https://create.roblox.com/docs/reference/engine/classes/RemoteEvent
- UnreliableRemoteEvent: https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent
- Client/server runtime: https://create.roblox.com/docs/projects/client-server
- Remote events guide: https://create.roblox.com/docs/scripting/events/remote
- Tool: https://create.roblox.com/docs/reference/engine/classes/Tool

---

## Mental Model

For most FPS / TPS shooters (including a Halo-style plasma rifle), you do **not** simulate a physical bullet part flying through the world for hit detection. You ask the world a single question at fire time:

> "If a ray travels from the muzzle (or camera) in this direction for `Range` studs, what is the first valid thing it hits?"

That is **hitscan**. The bullet you see is cosmetic. The ray is authoritative (on the server) or predictive (on the client for instant feedback).

Core pieces of a gun shot:

1. **Aim vector** — where the player is pointing (camera center, crosshair screen point, or muzzle forward).
2. **Ray origin** — world position the ray starts from (viewmodel muzzle attachment, camera with depth offset, or character head).
3. **Ray direction** — a `Vector3` whose **magnitude is the max range**. Roblox raycasts only test out to `direction.Magnitude` (max 15,000 studs).
4. **Filter** — `RaycastParams` excluding shooter, viewmodel, camera, teammates, etc.
5. **Hit resolution** — read `RaycastResult.Instance`, walk up to `Humanoid`, decide head vs body, apply damage on server.
6. **Feedback** — tracer beam, impact particles, hit marker, sound — mostly client-side, optionally replicated.

For your project:

- The **client** should fire immediately: muzzle flash, tracer, recoil animation, ammo UI tick, click sound.
- The **server** decides whether the shot was legal and whether anyone was hit.
- The client should **not** send `"I hit Humanoid X for 14 damage"`. It should send **intent + aim data** the server can re-verify.

---

## Hitscan vs Physical Projectile

| Approach | Hit detection | Best for | Notes |
|---|---|---|---|
| **Hitscan raycast** | `workspace:Raycast()` at fire time | Rifles, pistols, plasma weapons, lasers | Fast, deterministic, industry standard for "instant" guns |
| **Thick hitscan** | `workspace:Spherecast()` or multiple offset rays | Shotguns, forgiving weapons | Sphere has max radius 256, max travel 1024 studs |
| **Physical projectile** | Part with velocity + per-frame raycast sweep, or rare `.Touched` | Rockets, arrows, slow blobs | Higher cost; needs server simulation or client prediction + validation |
| **Moving hitbox** | `Blockcast` / overlap queries over time | Beams, flamethrowers | See melee doc; not primary for plasma rifle |

**Recommendation for Plasma Rifle:** start with hitscan `Raycast`. Add spread by perturbing direction slightly per shot if needed.

---

## Which Spatial Query API Should I Use?

### `workspace:Raycast(origin, direction, raycastParams)` — primary gun API

**What it does:** Casts a zero-thickness ray from `origin` along `direction`. Returns the **first** eligible `BasePart` or Terrain cell hit, or `nil`.

**Use it for:**

- Every standard bullet / plasma bolt hit check.
- Crosshair aim confirmation on client (predictive).
- Server-authoritative hit validation.
- Wallbang checks, penetration (chain multiple raycasts after subtracting entry distance).
- Line-of-sight checks before applying damage.

**Critical details from official docs:**

- `direction` magnitude **is** the max ray length. `Raycast(origin, Vector3.new(0, -100, 0))` only checks 100 studs down.
- Max direction length: **15,000 studs**.
- Does not use the legacy `Ray` object directly, but you can copy `Ray.Origin` and `Ray.Direction * range`.
- With `StreamingEnabled`, clients may not have distant parts loaded — raycasts on client can miss targets the server would see.
- Parts with `CanQuery = false` are never hit.
- Low-detail streaming "imposter" terrain/models are visual only and **not** raycast targets.

**Gun system example:**

```lua
local raycastParams = RaycastParams.new()
raycastParams.ExcludeInstances = { character, viewModel, workspace.CurrentCamera }
raycastParams.IgnoreWater = true

local origin = muzzleAttachment.WorldPosition
local direction = aimUnitVector * weaponConfig.Range -- e.g. 500 studs

local result = workspace:Raycast(origin, direction, raycastParams)
if result then
    local hitPart = result.Instance
    local hitPosition = result.Position
    local hitNormal = result.Normal
    local hitDistance = result.Distance
    -- resolve humanoid, head/body, apply damage on server
end
```

---

### `workspace:Spherecast(position, radius, direction, raycastParams)` — forgiving hitscan

**What it does:** Sweeps a **sphere** along a direction; returns first hit. Like a ray, but with thickness.

**Use it for:**

- Shotgun pellets (one spherecast or several raycasts).
- Generous hit registration on fast-moving targets.
- Plasma bolts that should feel "fat" without simulating a part.

**Limits (official):** max radius **256 studs**, max travel **1024 studs**. Does not detect parts already intersecting the sphere at the start position.

**When not to use:** Standard precision rifle shots — a thin ray is correct and cheaper.

---

### `workspace:Blockcast(cframe, size, direction, raycastParams)` — swept box

**What it does:** Sweeps an oriented box through space; returns first hit.

**Use it for:**

- Piercing shots that hit multiple targets in a thick corridor (uncommon).
- Special weapons, not typical plasma rifle shots.

**Limits:** max box size **512 studs** per axis, max travel **1024 studs**.

---

### `workspace:Shapecast(part, direction, raycastParams)` — custom shape sweep

**What it does:** Sweeps an arbitrary part's shape along a direction.

**Use it for:** exotic weapons where the projectile shape matches a specific mesh/part. Higher setup cost; rarely needed for rifles.

---

### Overlap queries (`GetPartBoundsInBox`, etc.) — generally not for guns

Melee uses overlap boxes that linger for several frames. Guns fire discrete rays at discrete times. Overlap queries are useful for:

- Flamethrower / continuous beam damage zones.
- Explosion radius damage (sphere overlap at impact point).
- "Did anything leave cover?" area checks.

For Plasma Rifle primary fire, prefer `Raycast`.

---

## RaycastParams — Filtering What Gets Hit

Reusable filter object for all ray/shapecast methods. Unlike most Luau datatypes, you can mutate it in place and reuse across shots.

### Properties that matter for guns

| Property | Purpose in gun system |
|---|---|
| `ExcludeInstances` | Exclude shooter character, equipped tool, viewmodel, `CurrentCamera`, local-only FX folders |
| `IncludeInstances` | Restrict to `"Characters"` folder or tagged enemies only (performance in large maps) |
| `CollisionGroup` | Use `"WeaponRay"` group that collides with `"Characters"` and `"World"` but not `"ViewModels"` |
| `IgnoreWater` | Set `true` so terrain water does not block shots |
| `RespectCanCollide` | If `true`, uses `CanCollide` instead of `CanQuery` for eligibility — usually leave `false` for combat |
| `BruteForceAllSlow` | **Never** in live gameplay — checks every part, destroys performance |

### Include vs exclude gotcha

- `IncludeInstances = nil` → include everything (default permissive).
- `IncludeInstances = {}` → include **nothing** (empty whitelist = no hits). Easy bug.
- If a part matches both include and exclude, **exclude wins**.

### Typical rifle setup

```lua
local params = RaycastParams.new()
params.ExcludeInstances = {
    shooterCharacter,
    shooterCharacter:FindFirstChildOfClass("Tool"),
    viewModelFolder, -- client-only first-person arms/weapon
    workspace.CurrentCamera,
}
params.IgnoreWater = true
params.CollisionGroup = "WeaponRay" -- optional, if configured in PhysicsService
```

Legacy `FilterDescendantsInstances` + `FilterType` still work but prefer `ExcludeInstances` / `IncludeInstances` for new code.

---

## RaycastResult — Reading a Hit

Returned when a ray/shapecast hits something.

| Property | Gun system use |
|---|---|
| `Instance` | The `BasePart` struck — walk up to `Model`, find `Humanoid`, check part name/tag for headshot |
| `Position` | World impact point — spawn impact VFX, decal, spark particles |
| `Normal` | Surface normal — orient impact effects, ricochet direction |
| `Distance` | Studs from ray origin to hit — validate max range server-side, falloff damage |
| `Material` | Surface type — metal spark vs dirt dust impact effects |

```lua
local function getHumanoidFromResult(result: RaycastResult): (Humanoid?, Model?)
    local part = result.Instance
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return nil, nil end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid, model
end

local function isHeadshot(hitPart: BasePart): boolean
    return hitPart.Name == "Head" -- or CollectionService tag, or attribute
end
```

---

## Aiming — Getting Origin and Direction

This is the most important design choice for a gun. **Where the ray starts** and **which direction it uses** determine fairness, feel, and exploit surface.

### Option A: Camera center ray (FPS standard)

Best when the crosshair is screen-center and the camera is authoritative for aim.

```lua
local camera = workspace.CurrentCamera
local viewportSize = camera.ViewportSize

-- Screen center, accounting for top bar inset:
local screenPoint = Vector2.new(viewportSize.X / 2, viewportSize.Y / 2)
local unitRay = camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)

-- Muzzle origin, camera direction (common FPS pattern):
local origin = muzzleAttachment.WorldPosition
local direction = unitRay.Direction * weaponConfig.Range
```

**`Camera:ScreenPointToRay(x, y, depth?)`**

- Creates a **unit** ray (1 stud long) from screen pixel `(x, y)`.
- Accounts for **GUI inset** (top bar) — matches where ScreenGui elements draw when `IgnoreGuiInset = false`.
- Optional `depth` offsets origin into the world along the camera forward axis (useful if you want origin slightly in front of camera).
- Extend: `unitRay.Direction * range` for actual raycast length.
- Only works for `workspace.CurrentCamera`.

**`Camera:ViewportPointToRay(x, y, depth?)`**

- Same idea but uses **device safe viewport** coordinates (does not account for CoreUI/top bar the same way).
- Prefer `ScreenPointToRay` when aligning with ScreenGui crosshairs.

**`Camera:WorldToScreenPoint(worldPoint)`**

- Inverse: 3D → 2D screen position. Use for hit markers over enemies, confirming target is on screen, off-screen indicators.

### Option B: Muzzle forward (TPS / strict muzzle alignment)

Ray starts at muzzle, direction is muzzle look vector (or blended toward camera aim).

```lua
local origin = muzzleAttachment.WorldPosition
local direction = muzzleAttachment.WorldCFrame.LookVector * weaponConfig.Range
```

Pros: tracers always leave the barrel. Cons: close-range shots can miss crosshair target if camera and muzzle disagree.

### Option C: Hybrid (recommended for third-person)

1. Ray from **camera** to find aim point (`Raycast` or max range into void).
2. Ray from **muzzle** toward that aim point for actual hit check.

This keeps crosshair accuracy while tracers originate from the weapon.

```lua
-- Step 1: where is the player aiming?
local camRay = camera:ScreenPointToRay(screenX, screenY)
local aimResult = workspace:Raycast(camRay.Origin, camRay.Direction * weaponConfig.Range, params)
local aimPoint = aimResult and aimResult.Position or (camRay.Origin + camRay.Direction * weaponConfig.Range)

-- Step 2: shot from muzzle toward aim point
local origin = muzzleAttachment.WorldPosition
local direction = (aimPoint - origin)
if direction.Magnitude > 0 then
    direction = direction.Unit * math.min(direction.Magnitude, weaponConfig.Range)
end
local hitResult = workspace:Raycast(origin, direction, params)
```

### Option D: Legacy `Mouse` (avoid for new code)

`Player:GetMouse()` provides:

- `Mouse.UnitRay` — unit ray from camera through mouse (1 stud long; extend for raycast).
- `Mouse.Hit` / `Mouse.Target` — continuous internal raycast to 1000 studs.
- `Mouse.TargetFilter` — instance to ignore (like exclude list).

Official docs say Mouse is **superseded by UserInputService** and `WorldRoot:Raycast()`. Your sword already uses `UserInputService` + manual raycasts for lunge — follow that pattern for guns.

### `UserInputService:GetMouseLocation()`

Returns screen pixel position of cursor. Pair with `ScreenPointToRay` for non-center crosshair aim (free cursor / TPS targeting reticle).

```lua
local mousePos = UserInputService:GetMouseLocation()
local unitRay = camera:ScreenPointToRay(mousePos.X, mousePos.Y)
```

Note: does not account for GUI inset by itself — use `GuiService:GetGuiInset()` if aligning custom UI with ray origin.

### Spread / inaccuracy

Apply random rotation to direction before raycast:

```lua
local function applySpread(baseDirection: Vector3, spreadRadians: number): Vector3
    local rng = Random.new()
    local x = (rng:NextNumber() - 0.5) * 2 * spreadRadians
    local y = (rng:NextNumber() - 0.5) * 2 * spreadRadians
    return (CFrame.lookAt(Vector3.zero, baseDirection) * CFrame.Angles(x, y, 0)).LookVector
end
```

**Server must apply the same spread rules** (or its own seeded spread) — do not trust client-only spread for damage.

---

## Visualizing Rays and Bullets

Hit detection ray is invisible. Players expect feedback. All of these are **cosmetic** — they do not replace server raycasts.

### 1. Debug ray line (development only)

Spawn a thin anchored part or use `Debug.DrawLine`-style helper between origin and `result.Position`:

```lua
local function drawDebugRay(origin: Vector3, hitPosition: Vector3, lifetime: number?)
    local distance = (hitPosition - origin).Magnitude
    local part = Instance.new("Part")
    part.Name = "DebugTracer"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 255, 0)
    part.Size = Vector3.new(0.1, 0.1, distance)
    part.CFrame = CFrame.lookAt(origin, hitPosition) * CFrame.new(0, 0, -distance / 2)
    part.Parent = workspace
    Debris:AddItem(part, lifetime or 0.1)
end
```

### 2. Beam tracer (best for plasma / laser)

**`Beam`** connects two `Attachment`s with a textured line. Official docs: cubic Bézier curve between attachments; highly customizable color, width, transparency, texture scroll.

**Gun system use:**

- Clone a beam template on each shot.
- `Attachment0` at muzzle, `Attachment1` at impact point (or max range point).
- Enable `FaceCamera = true` so tracer reads from all angles.
- Use `LightEmission = 1` for glowing plasma look.
- Parent under `workspace` or a client FX folder; destroy with `Debris:AddItem(beam, 0.15)`.

```lua
local function spawnTracer(muzzle: Attachment, hitPosition: Vector3)
    local endAtt = Instance.new("Attachment")
    endAtt.WorldPosition = hitPosition
    endAtt.Parent = workspace.Terrain

    local beam = tracerTemplate:Clone()
    beam.Attachment0 = muzzle
    beam.Attachment1 = endAtt
    beam.Enabled = true
    beam.Parent = muzzle

    Debris:AddItem(beam, 0.12)
    Debris:AddItem(endAtt, 0.12)
end
```

**`Attachment`** — defines muzzle point on viewmodel and world gun; use `WorldPosition` / `WorldCFrame` at fire time.

### 3. Fast moving part (physical-looking bolt)

Small neon part anchored or moved each frame along ray path:

- Spawn at muzzle.
- Each `RenderStepped`, move toward target over ~1-3 frames.
- **Do not use `.Touched` for damage** — damage already decided by raycast.
- `Debris:AddItem` for cleanup.

Good for slower plasma blobs; overkill for instant hitscan if beam suffices.

### 4. Trail

**`Trail`** attached to a part moving briefly through space — leaves motion streak. Parent trail to a fast part moving muzzle → impact. Useful for arcing projectiles; less common for instant rifles.

### 5. ParticleEmitter at muzzle and impact

**`ParticleEmitter`** — burst at fire (`Emit(n)`) for muzzle flash; clone emitter at `result.Position` aligned to `result.Normal` for impact sparks. Parent to `Attachment` for correct orientation.

### 6. Debris service

**`Debris:AddItem(instance, lifetime)`** — schedules destroy without yielding. Survives if firing script stops. Max **1000** tracked items; oldest evicted if over limit. Default lifetime 10s if omitted.

Use for all one-shot tracers, impact parts, temporary attachments.

---

## Cursors, Crosshair, and Mouse Lock

Guns interact heavily with pointer behavior. Your sword toggles `UserInputService.MouseIconEnabled` — guns need a fuller setup.

### Crosshair UI (recommended primary reticle)

A **ScreenGui** `ImageLabel` or `Frame` at screen center:

- Always visible in FPS/TPS aim mode.
- Does not replace the system cursor — it *is* the aim reference.
- Pair with `MouseIconEnabled = false` so OS arrow does not distract.
- Scale with `UIScale` / anchor center for different resolutions.
- `InterfaceController` is the right home for ammo + crosshair state (you already call `EquipPrimary` for sword).

Advantages over replacing `MouseIcon` with a crosshair image:

- Full control over shape, hit marker overlays, dynamic spread circle, team colors.
- Works identically with `MouseBehavior.LockCenter`.

### `UserInputService.MouseIconEnabled`

Set `false` to hide the default arrow. **Do not** use a transparent image to hide cursor — official docs explicitly say to use this property.

Your sword sets `MouseIconEnabled = true` in TPS targeting mode; rifle aim mode will likely set `false` and show GUI crosshair instead.

### `UserInputService.MouseIcon` / `MouseIconContent`

Replace cursor image with custom texture (ContentId / asset URI). Overridden while hovering `TextButton`, `ImageButton`, `TextBox`, `ProximityPrompt`.

**Gun use:** optional for TPS free-cursor targeting (sword-style). For FPS, prefer hidden system cursor + GUI crosshair.

Save previous icon before overriding (official sample pattern) so unequip restores correctly.

### `UserInputService.MouseBehavior`

| Value | Gun use |
|---|---|
| `Default` | TPS free aim — cursor moves on screen; ray through `GetMouseLocation()` |
| `LockCenter` | FPS standard — cursor hidden/locked center; camera driven by mouse delta; ray through screen center |
| `LockCurrentPosition` | Rare — locks where cursor was |

When locked, `InputChanged` still fires with mouse movement delta — camera scripts keep working.

Overridden when a `Modal` `GuiButton` is visible (unless RMB held).

### `UserInputService.MouseDeltaSensitivity`

Scales delta for `GetMouseDelta()` — does **not** change Roblox client camera sensitivity setting. Useful for scoped aim or temporary slowdown.

### `UserInputService:GetMouseDelta()`

Returns pixel delta since last frame when mouse is locked. Use for custom camera or verifying aim movement — not usually needed if default camera controller handles look.

### `UserInputService:GetMouseLocation()`

Screen pixel of cursor. Use with `ScreenPointToRay` for TPS reticle-at-cursor aiming.

### `GuiService:GetGuiInset()`

Returns top-left and bottom-right insets. Needed if manually converting screen coords or aligning crosshair with `ScreenPointToRay` coordinate spaces.

### First-person vs your existing view modes

Your project has FPS/TPS/OTS via `ViewController`. Gun aim should respect mode:

| Mode | Aim origin | Cursor |
|---|---|---|
| FPS | Camera center ray + viewmodel muzzle for tracer | LockCenter + GUI crosshair |
| TPS / OTS | Camera or cursor ray + muzzle hybrid | Free or locked depending on design; sword uses free cursor + targeting |

---

## Damage — Humanoid and Head/Body

All **real** damage must happen in a **server Script**. Clients may predict hits for VFX only.

### `Humanoid:TakeDamage(amount)`

Official behavior:

- Subtracts `amount` from `Humanoid.Health`.
- Respects **ForceField** — no damage if protected.
- Accepts negative values (healing).
- To bypass ForceField, set `Humanoid.Health` directly (usually avoid for PvP fairness).

```lua
-- SERVER ONLY
local damage = isHeadshot and config.DamageHead or config.DamageBody
targetHumanoid:TakeDamage(damage)
```

Your `WeaponsConfig["Plasma Rifle"]` already splits `DamageBody = 10` and `DamageHead = 14`.

### Headshot detection patterns

Roblox does not have a built-in headshot flag. Common approaches:

1. **Part name** — `hitPart.Name == "Head"` (R6/R15 both have Head).
2. **CollectionService tag** — tag `"HeadHitbox"` on head parts; query `HasTag`.
3. **Attribute** — `hitPart:GetAttribute("HitZone") == "Head"`.
4. **Separate head hitbox part** — invisible `"HeadShot"` part parented to character.

Prefer tags/attributes over name alone if custom characters differ.

### ForceField / spawn protection

Check before damage:

```lua
if targetCharacter:FindFirstChildOfClass("ForceField") then
    return
end
```

Or rely on `TakeDamage` and accept that ForceField blocks it.

### Friendly fire / teams

Validate attacker and target teams on server before `TakeDamage`. Never trust client team flag.

### Damage replication

`Humanoid.Health` replicates from server to clients automatically. Clients should listen to `Humanoid.HealthChanged` or your combat events for hit markers / kill feed — not apply damage locally.

---

## Client / Server Architecture

Official client-server model: **server is authority** for game state. Replication syncs property changes. Typical player latency: **100–300 ms** — test with Studio Network Simulation (50–150 ms inbound + outbound).

### What runs where

| Responsibility | Client | Server |
|---|---|---|
| Input (fire button) | ✓ | |
| Crosshair / cursor | ✓ | |
| Aim ray for prediction | ✓ | |
| Muzzle FX, tracer, recoil | ✓ (local); optional replicate | |
| Ammo display | ✓ (predict); server confirms | ✓ authoritative ammo |
| Hit detection for damage | optional prediction only | ✓ **required** |
| `TakeDamage` | ✗ | ✓ |
| Anti-cheat validation | | ✓ |
| Replicate shots to other players | | ✓ (event + FX) |

### Recommended fire flow

```
1. Client: click → check local cooldown/ammo → play FX → show tracer (predicted hit)
2. Client: FireServer(weaponId, shotToken, origin, direction, timestamp)
3. Server: validate weapon equipped, fire rate, ammo, character alive
4. Server: Raycast(origin, direction, serverParams) — same rules as client
5. Server: if hit → TakeDamage, deduct ammo, record shot
6. Server: FireAllClients(shooter, origin, hitPosition, weaponId) for other players' tracers
7. Client: reconcile prediction if server result differs (optional advanced)
```

### What to send over the network

**Good (intent + aim):**

```lua
FireRequest:FireServer("Plasma Rifle", shotId, origin, direction.Unit, os.clock())
```

**Bad (trust client hit):**

```lua
-- NEVER
FireRequest:FireServer(targetHumanoid, 14, "Head")
```

**Also bad:** sending only `"Fire"` with no aim data — server cannot fairly reconstruct shot.

Server should recompute or validate:

- `origin` near actual muzzle / plausible camera position (anti teleport exploit).
- `direction` unit vector within max angle of where server thinks player is aiming.
- `os.clock()` within fire-rate window (anti macro / fire too fast).
- Distance to hit ≤ weapon range + small latency tolerance.

### RemoteEvent vs UnreliableRemoteEvent

| Type | Use for guns |
|---|---|
| **`RemoteEvent`** | Fire requests, damage confirmations, equip/ammo sync — must arrive, ordered |
| **`UnreliableRemoteEvent`** | Rapid cosmetic tracers, optional aim preview — can drop, out of order; **>1000 byte payloads dropped** |

Official limits: ~**500 requests/second/client** shared across all remotes of same type. Full-auto weapons should not fire one remote per bullet at 1000 RPM without batching or server-side tick validation.

For Plasma Rifle: **`RemoteEvent` for fire request**; optional **`UnreliableRemoteEvent`** for purely cosmetic tracer replication if bandwidth matters.

### Latency strategies

#### 1. Strict server raycast (start here)

Server raycasts from its view of character + received aim direction.

- Pros: secure, simple.
- Cons: high-ping player may see tracer hit but server misses.

#### 2. Client-predicted FX + server authority

Client raycasts immediately for tracer/hit marker; server raycasts separately for damage.

- Pros: feels instant.
- Cons: occasional mismatch; need graceful correction (don't spawn floating hit numbers client-only without confirmation).

#### 3. Lag compensation (advanced)

Server rewinds target positions to what shooter saw at `timestamp`. Roblox has no built-in rollback netcode — you implement history buffers for character positions if needed. Defer until basic system works.

### Ammo authority

Pattern matching your sword (`Ammo` attribute on Tool):

- Server owns `Tool:SetAttribute("Ammo", newValue)` after validated shot.
- Client may decrement optimistically for UI; rollback if server rejects.
- Reload validates on server with rate limit.

---

## CanQuery, CanCollide, and Collision Groups

From **BasePart** docs:

- **`CanQuery`** — if `false`, part is invisible to all spatial queries including gun rays.
- **`CanCollide`** — physical collision only.
- **`CanTouch`** — `.Touched` events only.

For combat:

- Enemy body parts: `CanQuery = true`.
- Viewmodel / local weapon arms: `CanQuery = false` (and exclude in params).
- Pure decorative meshes: `CanQuery = false` so shots pass through visually non-solid props.

**PhysicsService** collision groups (server-configured):

- `"Characters"`, `"World"`, `"ViewModels"`, `"WeaponRay"`.
- Set `RaycastParams.CollisionGroup = "WeaponRay"` so query respects matrix (e.g. rays hit characters + world, ignore viewmodels).

If shots pass through enemies: check `CanQuery`, exclude list accidentally including enemy, empty `IncludeInstances`, wrong collision group, or target not streamed on client.

---

## Tool Integration

**`Tool`** — Roblox container for equipped weapons.

Gun-relevant behaviors:

- Parented to character when equipped, backpack when unequipped.
- `Tool.Activated` / `Tool.Deactivated` — built-in click events (works but many FPS games use `UserInputService` for finer control while unarmed/armed states differ).
- `Equipped` / `Unequipped` — setup/teardown per your `InitSword` / `RemoveSword` pattern.
- Handle part required for grip; put **Muzzle** `Attachment` on handle or barrel mesh.

Suggested parallel to sword:

- `GunController.luau` (client) — input, aim, FX, fire remote.
- `GunServer.luau` (server) — validate, raycast, damage, ammo.
- Shared `WeaponsConfig["Plasma Rifle"]`.

---

## RunService — When to Run Code

| Event | Gun use |
|---|---|
| `RenderStepped` | Update crosshair dynamic spread, move cosmetic bolt, align viewmodel — **client only**, runs before frame render |
| `Heartbeat` | Fixed-ish timestep logic; server fire-rate cooldown ticks |
| `Stepped` | Physics step; avoid hitscan here unless tied to physics |

Fire input: event-driven (`InputBegan`), not per-frame polling unless holding full-auto with `InputEnded` to stop.

---

## Suggested Module Architecture (ProjectPurge)

Align with existing sword split:

```
WeaponsConfig.luau          -- DamageBody, DamageHead, Range, FireRate, Ammo, Reload
GunController.luau          -- Client: equip, aim, cursor, fire input, local FX
GunServer.luau              -- Server: validate, raycast, damage, ammo
GunRaycast.luau (shared)    -- build params, cast, resolve humanoid, headshot helper
GunVFX.luau (client)        -- tracers, impacts, Debris cleanup
InterfaceController.luau    -- crosshair, ammo counter (extend EquipPrimary pattern)
ViewController.luau         -- FPS/OTS camera; mouse lock while aiming
ViewModelAnimations.luau    -- viewmodel fire/recoil/reload anims
```

`GunRaycast` should be weapon-agnostic — accepts origin, direction, exclude list, range.

---

## Example: Minimal Hitscan Module

```lua
-- GunRaycast.luau (shared logic; damage only called from server)
local GunRaycast = {}

export type CastConfig = {
    Range: number,
    ExcludeInstances: { Instance },
    CollisionGroup: string?,
}

export type HitInfo = {
    Part: BasePart,
    Humanoid: Humanoid,
    Model: Model,
    Position: Vector3,
    Normal: Vector3,
    Distance: number,
    IsHeadshot: boolean,
}

local function getHumanoid(part: BasePart): (Humanoid?, Model?)
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return nil, nil end
    return model:FindFirstChildOfClass("Humanoid"), model
end

function GunRaycast.Cast(origin: Vector3, directionUnit: Vector3, config: CastConfig): HitInfo?
    local params = RaycastParams.new()
    params.ExcludeInstances = config.ExcludeInstances
    params.IgnoreWater = true
    if config.CollisionGroup then
        params.CollisionGroup = config.CollisionGroup
    end

    local result = workspace:Raycast(origin, directionUnit * config.Range, params)
    if not result then return nil end

    local humanoid, model = getHumanoid(result.Instance)
    if not humanoid or humanoid.Health <= 0 then return nil end

    return {
        Part = result.Instance,
        Humanoid = humanoid,
        Model = model,
        Position = result.Position,
        Normal = result.Normal,
        Distance = result.Distance,
        IsHeadshot = result.Instance.Name == "Head",
    }
end

return GunRaycast
```

Server usage:

```lua
local hit = GunRaycast.Cast(origin, direction.Unit, castConfig)
if hit and hit.Model ~= shooterCharacter then
    local dmg = hit.IsHeadshot and weaponConfig.DamageHead or weaponConfig.DamageBody
    hit.Humanoid:TakeDamage(dmg)
end
```

---

## Example: Client Fire + Server Request

```lua
-- CLIENT (GunController)
local function firePlasmaRifle()
    if not canFire then return end
    canFire = false

    local camera = workspace.CurrentCamera
    local vp = camera.ViewportSize
    local unitRay = camera:ScreenPointToRay(vp.X / 2, vp.Y / 2)

    local origin = viewModelMuzzle.WorldPosition
    local direction = unitRay.Direction

    -- Predict locally for instant feedback
    local localHit = GunRaycast.Cast(origin, direction, localCastConfig)
    GunVFX.PlayShot(origin, localHit and localHit.Position or (origin + direction * range))

    local shotId = HttpService:GenerateGUID(false)
    FireRequest:FireServer("Plasma Rifle", shotId, origin, direction, os.clock())

    task.delay(fireInterval, function()
        canFire = true
    end)
end

-- SERVER (GunServer)
FireRequest.OnServerEvent:Connect(function(player, weaponId, shotId, origin, direction, clientTime)
    -- validate player, weapon, cooldown, ammo ...
    local hit = GunRaycast.Cast(origin, direction, serverCastConfig)
    if hit then
        -- team check, range check, line-of-sight optional
        local cfg = WeaponsConfig[weaponId]
        hit.Humanoid:TakeDamage(hit.IsHeadshot and cfg.DamageHead or cfg.DamageBody)
    end
    -- deduct ammo, broadcast FX to other clients
end)
```

---

## Server Validation Checklist

When a fire request arrives:

- Does the player have a character with `Humanoid` alive?
- Is the requested weapon equipped as a `Tool`?
- Is `weaponId` valid and matches equipped tool?
- Is fire rate respected (server-side last-fire time)?
- Is ammo > 0?
- Is player stunned, dead, in menu, or otherwise unable to shoot?
- Is `origin` within reasonable distance of character muzzle/head?
- Is `direction` a unit vector (or close enough)?
- Is `shotId` unique (replay protection)?

When applying a hit:

- Is target a different character?
- Is target `Humanoid` alive?
- Is target on an enemy team?
- Is hit distance ≤ weapon range (+ small tolerance)?
- Has this `shotId` already been processed?

---

## Performance Guidelines

**Do:**

- Reuse one `RaycastParams` instance; mutate `ExcludeInstances` only when needed.
- Use `ExcludeInstances` / collision groups to skip viewmodels and shooter.
- Keep tracer lifetime short (`Debris:AddItem` 0.05–0.2s).
- Event-drive fire input; raycast once per shot per side (client predict + server authority = 2 raycasts max per shot).
- Convert hit part → humanoid once.
- Batch full-auto validation on server tick if fire rate is very high.

**Avoid:**

- Per-frame raycasts while not firing (unless continuous beam weapon).
- `BruteForceAllSlow`.
- Spawning unanchored physics parts for every bullet for hit detection.
- Trusting client hit results.
- Firing remotes faster than needed without server-side rate cap.
- Creating new `RaycastParams` every shot in a minigun loop without reason.

---

## Debugging

Enable flags:

- Draw debug ray from origin to hit (yellow) or max range (red).
- Log server vs client hit mismatch (part name, distance delta).
- Print exclude list count and collision group.
- Test with Studio latency simulation (50–150 ms each direction).

Common bugs:

| Symptom | Likely cause |
|---|---|
| Always misses on client, hits on server | Client streaming — target not loaded client-side |
| Never hits enemies | `CanQuery = false`, or enemy in exclude list, or `IncludeInstances = {}` |
| Hits self | Shooter not excluded; muzzle inside own hitbox |
| Tracer ≠ damage | Client and server use different origin/direction — align hybrid aim |
| Remote throttle | Too many FireServer calls; batch or enforce server fire rate |
| Crosshair misaligned | Using `ViewportPointToRay` vs ScreenGui coords wrong; check GUI inset |

---

## Plasma Rifle Config Mapping

From your `WeaponsConfig.luau`:

```lua
["Plasma Rifle"] = {
    DamageBody = 10,
    DamageHead = 14,
    DamageMelee = 50,
    Ammo = 50,
    Reload = 0.02,
}
```

Suggested additions when implementing:

```lua
Range = 500,           -- max raycast studs
FireRate = 0.1,        -- seconds between shots (adjust feel)
Spread = 0,            -- radians; 0 = perfect accuracy
MuzzleAttachment = "Muzzle", -- name in tool
```

---

## Quick API → Gun Role Summary

| API | Role in gun system |
|---|---|
| `WorldRoot:Raycast` | Primary hit detection every shot |
| `WorldRoot:Spherecast` | Thick / shotgun shots |
| `RaycastParams` | Filter shooter, viewmodel, teams, water |
| `RaycastResult` | Impact point, part, distance, material FX |
| `Camera:ScreenPointToRay` | FPS crosshair aim |
| `Camera:ViewportPointToRay` | Viewport-native coords (rare) |
| `Camera:WorldToScreenPoint` | Hit markers, target UI |
| `UserInputService.MouseBehavior` | Lock center for FPS |
| `UserInputService.MouseIconEnabled` | Hide OS cursor |
| `UserInputService:GetMouseLocation` | TPS cursor aim |
| `GuiService:GetGuiInset` | Align screen coords with UI |
| `Beam` + `Attachment` | Plasma tracers |
| `ParticleEmitter` | Muzzle flash, impact sparks |
| `Debris:AddItem` | Cleanup tracers/FX |
| `Humanoid:TakeDamage` | Server damage application |
| `RemoteEvent` | Fire requests, confirmed combat events |
| `UnreliableRemoteEvent` | Optional cosmetic-only replication |
| `RunService.RenderStepped` | Viewmodel / cosmetic bolt motion |
| `BasePart.CanQuery` | Ensure hittable body parts |
| `PhysicsService` | Collision groups for rays vs world/characters |
| `Tool` | Equip lifecycle, muzzle on weapon model |

---

## Related Doc

For overlap/box hitboxes, melee swings, and blockcast sweeping, see `Roblox_Melee_Hitbox_Reference.md` in this folder. Guns use rays first; melee uses volumes — but explosion radius and melee bayonet could reuse overlap queries from that doc.
