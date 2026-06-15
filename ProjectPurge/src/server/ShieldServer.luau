-- shield regen, highlight, break fx on all characters (server authoritative)

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local DataStoreService = game:GetService("DataStoreService")
local PlayerService = game:GetService("Players")
local ShieldConfig = require(game.ReplicatedStorage.Shared.ShieldConfig)
local EffectsFolder = game.ReplicatedStorage:FindFirstChild("Effects")
local SoundsFolder = game.ReplicatedStorage:FindFirstChild("Sounds")

local EmptyShieldTemplate = EffectsFolder:FindFirstChild("CharacterEmptyShield")
local ShieldPopTemplate = EffectsFolder:FindFirstChild("ShieldPop")
local BreakSoundTemplate = SoundsFolder:FindFirstChild("Break")

local GlobalShieldsEnabled = true -- toggle for break fx later maybe
local ShieldData = {} -- per-character regen state
local ShieldTrackerConnection : RBXScriptConnection? = nil 

-- tick shield up by 1, recurse until full
local function ApplyRegenStep(character) 
    local Data = ShieldData[character]
    if not Data then return end 
    if not character.Parent then return end 
    local CharacterHumanoid : Humanoid = character:FindFirstChildOfClass("Humanoid")
    if not CharacterHumanoid or CharacterHumanoid.Health <= 0 then return end 

    local Shield = tonumber(character:GetAttribute("Shield"))
    local MaxShield = tonumber(character:GetAttribute("MaxShield"))

    if (tick() - Data.LastDecrease) < ShieldConfig.REGEN_DELAY_AFTER_DAMAGE then 
		return 
	end 

    local token = Data.RegenToken
    character:SetAttribute("Shield", math.min(Shield + 1, MaxShield))


	task.spawn(function()
        task.wait(0.025)
		if not character.Parent then return end

		local Dat = ShieldData[character]
		if not Dat or Dat.RegenToken ~= token then
			return
		end
		local Shield = character:GetAttribute("Shield")
		local MaxShield = character:GetAttribute("MaxShield")
		if Shield < MaxShield then
			ApplyRegenStep(character)
		end
	end)
end 

-- wait REGEN_DELAY then start stepping
local function ScheduleShieldRegen(character) 
    local Data = ShieldData[character] 
    if not Data then return end 

    Data.RegenToken += 1 -- bump token so old regen loops bail 
    local ExpectedToken = Data.RegenToken

    task.delay(ShieldConfig.REGEN_DELAY_AFTER_DAMAGE, function()
        if not character.Parent then return end 
        local Dat = ShieldData[character]

        if not Dat or Dat.RegenToken ~= ExpectedToken then return end 
        ApplyRegenStep(character)

    end)

end 

-- shield went down? reset delay and schedule regen
local function InitRegenSequence(character) 
    local ShieldAttr = character:GetAttribute("Shield")
    local ShieldVal = tonumber(ShieldAttr)

    local PreviousShield = ShieldData[character].PreviousShield

    if ShieldVal > PreviousShield then
        ShieldData[character].PreviousShield = ShieldVal
        return 
    end

    ShieldData[character].LastDecrease = tick()
    ShieldData[character].PreviousShield = ShieldVal
    ScheduleShieldRegen(character)
    return 

end 

local function ApplyShieldHighlight(character)
    local Highlight : Highlight = Instance.new("Highlight")
    local HighlightConfig = ShieldConfig.SHIELD_HIGHLIGHT

    Highlight.FillColor = HighlightConfig.FillColor
    Highlight.FillTransparency = HighlightConfig.FillTransparency
    Highlight.OutlineColor = HighlightConfig.OutlineColor
    Highlight.OutlineTransparency = HighlightConfig.OutlineTransparency
    Highlight.DepthMode = HighlightConfig.DepthMode

    Highlight.Parent = character

    return Highlight
end 

-- strip lightning fx when shield comes back
local function CleanupBrokenShield(character : Model)
    for _, PotentialBpart in character:GetChildren() do
        if PotentialBpart:IsA("BasePart") then
            for _, PotentialEffect in PotentialBpart:GetChildren() do
                if PotentialEffect.Name == "Lightning" then 
                    PotentialEffect:Destroy()
                end 
            end 
        end 
    end 
end 

local function UpdateShieldHighlight(character : Model, Highlight : Highlight)
    local ShieldAttr = character:GetAttribute("Shield")
    local ShieldValue = tonumber(ShieldAttr)
    local MaxShieldAttr = character:GetAttribute("MaxShield")
    local MaxShieldValue = tonumber(MaxShieldAttr)

    if ShieldValue == 0 then 
        Highlight.Enabled = false
        -- shield break particles + sound on all body parts
        if GlobalShieldsEnabled then

            for _, Bodypart in character:GetChildren() do
                if Bodypart:IsA("BasePart") then 
                    local ThisEmptyShield = EmptyShieldTemplate:Clone()
                    ThisEmptyShield.Name = "Lightning"
                    ThisEmptyShield.Parent = Bodypart
                end 
            end 

            local PopEffect = ShieldPopTemplate:Clone()
            local hrp = character:FindFirstChild("HumanoidRootPart")
            PopEffect.Name = "ShieldPopSFX"
            PopEffect.Position = Vector3.new(0,0,0)
            PopEffect.Parent = hrp

            local BreakSound : Sound = BreakSoundTemplate:Clone()
            BreakSound.Name = "BreakSound" 
            BreakSound.Parent = hrp
            BreakSound:Play()

            for _, Emitter in PopEffect:GetChildren() do
                if Emitter:IsA("ParticleEmitter") then
                    if Emitter.Name == "others" then 
                        Emitter:Emit(2)
                    elseif Emitter.Name == "Shockwave3" or Emitter.Name == "Flash" then 
                        Emitter:Emit(1)
                    end 
                end
            end

            task.delay(2, function()
                if PopEffect and PopEffect.Parent then
                    PopEffect:Destroy()
                end
            end)

            BreakSound.Ended:Once(function(soundId)
                BreakSound:Destroy()
            end)

        end
        return
    end 

    CleanupBrokenShield(character)
    if GlobalShieldsEnabled then Highlight.Enabled = true end 

    local Ratio = math.clamp(ShieldValue / MaxShieldValue, 0, 1)
    Highlight.FillTransparency = ShieldConfig.SHIELD_HIGHLIGHT.FillTransparency * Ratio
end 

local function OnCharacterAdded(character)
    if not character then return end 

    -- attributes replicated to clients for ui + hit logic
    character:SetAttribute("Shield", ShieldConfig.DEFAULT_SHIELD)
    character:SetAttribute("MaxShield", ShieldConfig.DEFAULT_SHIELD)
    character:SetAttribute("Health", ShieldConfig.DEFAULT_HEALTH)
    character:SetAttribute("MaxHealth", ShieldConfig.DEFAULT_HEALTH)

    ShieldData[character] = {
        PreviousShield = ShieldConfig.DEFAULT_SHIELD,
        LastDecrease = 0,
        RegenToken = 0 
    }

    local ShieldHighlight = ApplyShieldHighlight(character)
    ShieldTrackerConnection = character:GetAttributeChangedSignal("Shield"):Connect(function(...) 
        UpdateShieldHighlight(character, ShieldHighlight)
        InitRegenSequence(character)
    end)
    
end 

PlayerService.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(OnCharacterAdded)
end)


return {} 