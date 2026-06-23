-- dash + grapple hud in WeaponHUD

local InterfaceController = {}
local PlayerService = game:GetService("Players")
local Player = PlayerService.LocalPlayer
local PlayerGui = Player.PlayerGui

local Character = Player.Character

function InterfaceController.UpdateDash(self, character)
    local DashAttribute = character:GetAttribute("Dashes")
    if not DashAttribute then return end 

    local Core : ScreenGui= PlayerGui:FindFirstChild("AJ")
    local WeaponHUD : Frame = Core:FindFirstChild("WeaponHUD")
    local Specials : ImageLabel = WeaponHUD:FindFirstChild("Specials")
    local Grapple : TextButton = Specials:FindFirstChild("Dash") 
    local UseFrame1 : Frame = Grapple:FindFirstChild("UseFrame1")
    local UseFrame2 : Frame = Grapple:FindFirstChild("UseFrame2")
    local Number : TextLabel = Grapple:FindFirstChild("Number")
    local NumberGlow : TextLabel = Grapple:FindFirstChild("NumberGlow")

    local DashNumber = tonumber(DashAttribute)

    -- dim frames when charges spent
    if DashNumber == 1 then
        UseFrame1.BackgroundTransparency = 0.75
        UseFrame2.BackgroundTransparency = 0
        Number.Text = "1"
        NumberGlow.Text = "1"
    elseif DashNumber <= 0 then
        UseFrame1.BackgroundTransparency = 0.75
        UseFrame2.BackgroundTransparency = 0.75
        Number.Text = "0"
        NumberGlow.Text = "0"
    elseif DashNumber == 2 then 
        UseFrame1.BackgroundTransparency = 0
        UseFrame2.BackgroundTransparency = 0
        Number.Text = "2"
        NumberGlow.Text = "2"
    else 
        UseFrame1.BackgroundTransparency = 0
        UseFrame2.BackgroundTransparency = 0
        Number.Text = "2"
        NumberGlow.Text = "2"
    end
end

function InterfaceController.RegenGrapple()
    Player = PlayerService.LocalPlayer
    PlayerGui = Player.PlayerGui

    local Core : ScreenGui= PlayerGui:FindFirstChild("AJ")
    local WeaponHUD : Frame = Core:FindFirstChild("WeaponHUD")
    local Specials : ImageLabel = WeaponHUD:FindFirstChild("Specials")
    local Grapple : TextButton = Specials:FindFirstChild("GrappleHook") 
    local UseFrame : Frame = Grapple:FindFirstChild("UseFrame")

    UseFrame.BackgroundTransparency = 0
end

function InterfaceController.UseGrapple()
    Player = PlayerService.LocalPlayer
    PlayerGui = Player.PlayerGui

    local Core : ScreenGui= PlayerGui:FindFirstChild("AJ")
    local WeaponHUD : Frame = Core:FindFirstChild("WeaponHUD")
    local Specials : ImageLabel = WeaponHUD:FindFirstChild("Specials")
    local Grapple : TextButton = Specials:FindFirstChild("GrappleHook") 
    local UseFrame : Frame = Grapple:FindFirstChild("UseFrame")

    UseFrame.BackgroundTransparency = 0.75 
end

if Character then
    Character:GetAttributeChangedSignal("Dashes"):Connect(function()
        InterfaceController:UpdateDash(Character)
    end)
end

Player.CharacterAdded:Connect(function(character)
    Character = Player.Character
    PlayerGui = Player.PlayerGui
    PlayerGui:WaitForChild("AJ", 10)

    Character:GetAttributeChangedSignal("Dashes"):Connect(function()
        InterfaceController:UpdateDash(Character)
    end)

    -- sync hud to a fresh state each life (changed signals won't fire for spawn defaults)
    InterfaceController:RegenGrapple()
    InterfaceController:UpdateDash(Character)
end)


return InterfaceController 
