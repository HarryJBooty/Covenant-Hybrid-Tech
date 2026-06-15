-- client shield bar, highlight on viewmodel, regen sfx

local ShieldController = {}

local PlayerService = game:GetService("Players")
local ShieldConfig = require(game.ReplicatedStorage.Shared.ShieldConfig)
local ViewController = require(game.StarterPlayer.StarterPlayerScripts.Client.ViewController)
local EffectsFolder = game.ReplicatedStorage:FindFirstChild("Effects")
local SoundsFolder = game.ReplicatedStorage:FindFirstChild("Sounds")

local Player = PlayerService.LocalPlayer
local PlayerGui = Player.PlayerGui
local Character = Player.Character 
local MaxShield 
local PreviousViewModel 
local ShieldsDown = false

-- sound relevant variables:
local ArmRegenSFX = true -- only play regen sfx once per damage event
local PrevShield = nil :: IntValue
local BeepSoundPlaying = false 
local BeepSound: Sound? = SoundsFolder.Deplete

local RegenSoundPlaying = false
local RegenSound: Sound? = SoundsFolder.Charge


local COLOR_GLOW_NORMAL = Color3.fromRGB(76, 163, 255)
local COLOR_LOW = Color3.fromRGB(255, 90, 93)
local LOW_SHIELD_RATIO = 0.25
local DAMAGE_WARNING_VISIBILITY = { Min = 0.1, Max = 1 }
local PROGRESS_OFFSET = 0.003

local UiRefs = {
	TopHealth = nil :: ImageLabel?,
	HealthBack = nil :: ImageLabel?,
	Container = nil :: Frame?,
	Fill = nil :: ImageLabel?,
	FillProgress = nil :: UIGradient?,
	Chip = nil ::ImageLabel?,
	ChipProgress = nil :: UIGradient?,
	Glow = nil :: ImageLabel?,
	LowHP = nil :: ImageLabel?,
	LowHpProgress = nil :: UIGradient?,
}

local function StartBeep()
	if BeepSoundPlaying then
		return 
	end
	BeepSoundPlaying = true

	BeepSound.Ended:Connect(function()
		BeepSoundPlaying = false
	end)

	BeepSound:Play()
end 

local function StopBeep()
	if not BeepSoundPlaying then 
		return 
	end 
	BeepSoundPlaying = false
	if BeepSound and BeepSound.IsPlaying then 
		BeepSound:Stop()
	end 
end 

local function StartRegenSFX()
	if RegenSoundPlaying then 
		return 
	end
	local Character = Player.Character
	local CharacterHumanoid = Character and Character:FindFirstChildOfClass("Humanoid")
	if not CharacterHumanoid or CharacterHumanoid.Health <= 0 then return end

	RegenSoundPlaying = true

	RegenSound.Ended:Connect(function()
		RegenSoundPlaying = false
	end)

	RegenSound.TimePosition = 3 -- 3 CONST FOR THIS SPECIFIC TIME, REMOVE THIS IF NEEDED OR FIND A BETTER REGEN SOUND
	RegenSound:Play()
end

local function StopRegenSFX()
	if not RegenSoundPlaying then
		return
	end
	RegenSoundPlaying = false
	if RegenSound and RegenSound.IsPlaying then 
		RegenSound:Stop()
	end 
end 

local function PlayShieldSound(char)
	local Shield = char:GetAttribute("Shield")
	local MaxShield = char:GetAttribute("MaxShield")
	if Shield == 0 then
		StartBeep()
	end

	if Shield == MaxShield then
		StopRegenSFX()
		ArmRegenSFX = true
		PrevShield = Shield
		return 
	end

	if Shield < PrevShield then
		StopRegenSFX()
		ArmRegenSFX = true
	elseif Shield > PrevShield then 
		StopBeep()
		if ArmRegenSFX then 
			StartRegenSFX()
			ArmRegenSFX = false
		end 
	end

	PrevShield = Shield
end

local function WaitForServerSetup(character : Model)
    -- shield attr set by ShieldServer on spawn
    if character:GetAttribute("Shield") ~= nil then 
		print("setup done")
        return 
    end 
	print("starting wait")
    character:GetAttributeChangedSignal("Shield"):Wait()
end     

local function WaitForViewModel(timeoutSeconds: number?): Instance?
	local deadline = if timeoutSeconds then os.clock() + timeoutSeconds else math.huge
	while os.clock() < deadline do
		local vm = ViewController:ReceiveViewModel()
		if vm ~= nil then
			return vm
		end
		task.wait()
	end
	return nil
end

local function ApplyShieldBrokenEffect(state : boolean)
    -- lightning on viewmodel arms when shield hits 0
    if PreviousViewModel ~= nil then
		for _, Child in PreviousViewModel:GetChildren() do
			if Child.Name == "LeftArm" or Child.Name == "RightArm" then
				for _, SubChild in Child:GetChildren() do
					if SubChild.Name == "Lightning" then
						SubChild:Destroy()
					end
				end
			end
		end
	end
	local ViewModel = ViewController:ReceiveViewModel() 
	PreviousViewModel = ViewModel
	local LightningFX = EffectsFolder:FindFirstChild("EmptyShield")

	for _, Child in ViewModel:GetChildren() do
		if Child.Name == "LeftArm" or Child.Name == "RightArm" then

			if state == true then
				local ThisEffect = LightningFX:Clone() 
				ThisEffect.Name = "Lightning"
				ThisEffect.Parent = Child
			else 
				for _, SubChild in Child:GetChildren() do
					if SubChild.Name == "Lightning" then
						SubChild:Destroy() 
					end
				end
			end
		end 
	end

	local ViewState = ViewController:GetMode()
	if ViewState == "TPS" then 
		ViewController.ToggleViewModelParticles(false)
	end 
end

local function UpdateShieldHighlight(character, Highlight)
	local CurrentShield = character:GetAttribute("Shield")
	local MaxShieldnum = tonumber(MaxShield)
	local CurrentShieldnum = tonumber(CurrentShield)
	
	if CurrentShieldnum <= 0 or MaxShieldnum == 0 then
		Highlight.Enabled = false
		if MaxShieldnum ~= 0 then
			ShieldsDown = true
			ApplyShieldBrokenEffect(true)
		end
		return 
	end

	ShieldsDown = false
	Highlight.Enabled = true
	ApplyShieldBrokenEffect(false)
	local Ratio = math.clamp(CurrentShield / MaxShield, 0, 1)
	Highlight.FillTransparency = ShieldConfig.SHIELD_HIGHLIGHT.FillTransparency * Ratio
end

local function setBarColors(normal: boolean)
	if not UiRefs.HealthBack or not UiRefs.Fill or not UiRefs.Glow then
		return
	end

	local back = UiRefs.HealthBack
	if back:IsA("ImageLabel") or back:IsA("ImageButton") then
		(back :: ImageLabel).ImageColor3 = if normal then Color3.new(1, 1, 1) else COLOR_LOW
	elseif back:IsA("Frame") then
		(back :: Frame).BackgroundColor3 = if normal then Color3.new(1, 1, 1) else COLOR_LOW
	end
	UiRefs.Fill.ImageColor3 = if normal then Color3.new(1, 1, 1) else COLOR_LOW
	UiRefs.Glow.ImageColor3 = if normal then COLOR_GLOW_NORMAL else COLOR_LOW
end

local function UpdateLowShieldOverlay(currentProgress: number)
	if not UiRefs.LowHpProgress then
		return
	end

	local sequence = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(
			math.clamp(currentProgress, DAMAGE_WARNING_VISIBILITY.Min, DAMAGE_WARNING_VISIBILITY.Max),
			1
		),
		NumberSequenceKeypoint.new(1, 0),
	})

	UiRefs.LowHpProgress.Transparency = sequence
end

local function ApplyLowShieldIndicator(currentShield: number, maxShield: number)
	local threshold = math.max(maxShield * LOW_SHIELD_RATIO, 1e-3)

	if currentShield > threshold then
		if UiRefs.LowHP then
			UiRefs.LowHP.Visible = false
		end
	else
		if UiRefs.LowHP then
			UiRefs.LowHP.Visible = true
		end
	end

	if UiRefs.LowHpProgress then
		local overlayProgress = math.clamp(currentShield / threshold, 0, 1)
		UpdateLowShieldOverlay(overlayProgress)
	end
end

local function UpdateShieldUI(character)
    -- gradient on fill bar tracks shield ratio
	local ShieldAttr = character:GetAttribute("Shield")
	local MaxShieldAttr = character:GetAttribute("MaxShield")
	local ShieldValue = tonumber(ShieldAttr)
	local MaxShieldValue = tonumber(MaxShieldAttr)


	local ShieldRatio = math.clamp(ShieldValue / MaxShieldValue, 0, 1)

	if not UiRefs.Fill or not UiRefs.FillProgress then print("fill missing or fill progress missing") return end 



	local ShieldBarSequence = NumberSequence.new({
		NumberSequenceKeypoint.new(0,0),
		NumberSequenceKeypoint.new(ShieldRatio, 0),
		NumberSequenceKeypoint.new(math.clamp(ShieldRatio + PROGRESS_OFFSET, 0, 1), 1),
		NumberSequenceKeypoint.new(1, 1), 
	})

	local LowShieldThreshold = math.max(MaxShieldValue * LOW_SHIELD_RATIO, 1e-3)
	if ShieldValue > LowShieldThreshold then
		setBarColors(true)
	else
		setBarColors(false)
	end


	UiRefs.FillProgress.Transparency = ShieldBarSequence
	ApplyLowShieldIndicator(ShieldValue, MaxShieldValue)
end

local function CreateShieldHighlight(): Highlight
	local HighlightConfig = ShieldConfig.SHIELD_HIGHLIGHT
	assert(HighlightConfig, "ShieldConfig.SHIELD_HIGHLIGHT is missing — check ShieldConfig module return value")

	local highlight = Instance.new("Highlight")
	highlight.Name = "ShieldHighlight"
	highlight.FillColor = HighlightConfig.FillColor
	highlight.FillTransparency = HighlightConfig.FillTransparency
	highlight.OutlineColor = HighlightConfig.OutlineColor
	highlight.OutlineTransparency = HighlightConfig.OutlineTransparency
	highlight.DepthMode = HighlightConfig.DepthMode
	return highlight
end

local function BindShieldUI() 
    -- cache refs to AJ gui elements
	PlayerGui = Player.PlayerGui
	local UICore = PlayerGui:WaitForChild("AJ", 10)

	UiRefs.TopHealth = UICore:FindFirstChild("TopHealth")
	UiRefs.HealthBack = UiRefs.TopHealth:FindFirstChild("HealthBack")
	UiRefs.Container = UiRefs.HealthBack:FindFirstChild("Container")
	UiRefs.Chip = UiRefs.HealthBack:FindFirstChild("Chip")
	UiRefs.ChipProgress = UiRefs.Chip:FindFirstChild("ChipProgress")
	UiRefs.Fill = UiRefs.Container:FindFirstChild("Fill")
	UiRefs.FillProgress = UiRefs.Fill:FindFirstChild("FillProgress")
	UiRefs.Glow = UiRefs.Container:FindFirstChild("Glow")
	UiRefs.LowHP = UiRefs.TopHealth:FindFirstChild("LowHP")
	UiRefs.LowHpProgress = UiRefs.LowHP:FindFirstChild("LHProgress")

end 

local function OnCharacterAdded(character : Model)
    Character = Player.Character
    WaitForServerSetup(character)
    WaitForViewModel(5)
	BindShieldUI()
	print("passed initial")

    local ShieldAttr = character:GetAttribute("Shield")
	MaxShield = character:GetAttribute("MaxShield")
    local ShieldHighlight = CreateShieldHighlight()
    local ViewModel = ViewController:ReceiveViewModel()
    PrevShield = MaxShield
	
    ShieldHighlight.Parent = ViewModel
	character:GetAttributeChangedSignal("CurrentTool"):Connect(function()
		-- move highlight when viewmodel swaps
		print("attribute changed signal got on shield controller client")	
		ViewModel = ViewController:ReceiveViewModel() 
		print(ViewModel.Name)
		ShieldHighlight.Parent = ViewModel
		if ShieldsDown then
			ApplyShieldBrokenEffect(true)
		end
	end)
	character:GetAttributeChangedSignal("Shield"):Connect(function()
		UpdateShieldHighlight(character, ShieldHighlight)
		UpdateShieldUI(character)
		PlayShieldSound(character)
	end)

end 

Player.CharacterAdded:Connect(function(character)
    OnCharacterAdded(character)
end)

if Character then 
    OnCharacterAdded(Character)
end 



return ShieldController

