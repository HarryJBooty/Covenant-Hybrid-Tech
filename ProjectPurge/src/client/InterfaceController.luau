-- dash + grapple hud in WeaponHUD

local InterfaceController = {}
local PlayerService = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local WeaponsConfig = require(game.ReplicatedStorage.Shared.WeaponsConfig)
local Player = PlayerService.LocalPlayer
local PlayerGui = Player.PlayerGui

local Character = Player.Character
local Backpack = Player.Backpack
local ACTIVE_SLOT_COLOR = Color3.fromRGB(39, 255, 237)
local INACTIVE_SLOT_COLOR = Color3.fromRGB(255, 255, 255)
local LAST_EQUIPPED_SLOT_COLOR = Color3.fromRGB(255, 235, 0)

local ToolSlots = {}
local AmmoConnections = {}
local CharacterConnections = {}
local BackpackConnection : RBXScriptConnection? = nil
local LastEquippedTool : Tool? = nil

local function HideRobloxToolbar()
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)
end

local function IsWeaponTool(tool)
    if not tool or not tool:IsA("Tool") then
        return false
    end

    -- a server-granted loadout tool is tagged with its slot, so trust that first
    if tool:GetAttribute("Slot") ~= nil then
        return true
    end

    local config = WeaponsConfig[tool.Name]
    return config ~= nil and config.Ammo ~= nil
end

local function GetWeaponConfig(tool : Tool?)
    if not tool then
        return nil
    end
    return WeaponsConfig[tool.Name]
end

local function GetToolAmmo(tool : Tool?)
    if not tool then
        return 0, 0
    end

    local config = GetWeaponConfig(tool)
    local maxAmmo = tonumber(tool:GetAttribute("MaxAmmo")) or (config and config.Ammo) or 0
    local ammo = tonumber(tool:GetAttribute("Ammo")) or maxAmmo

    return ammo, maxAmmo
end

local function GetWeaponHUD()
    PlayerGui = Player.PlayerGui
    local Core : ScreenGui = PlayerGui:FindFirstChild("AJ")
    if not Core then return nil end
    return Core:FindFirstChild("WeaponHUD")
end

local function GetSlotFrame(slotName : string)
    local WeaponHUD = GetWeaponHUD()
    if not WeaponHUD then return nil end
    return WeaponHUD:FindFirstChild(slotName)
end

local function GetSlotIcon(slotFrame, slot : number): ImageLabel?
    if not slotFrame then return nil end

    if slot == 2 then
        return slotFrame
    end

    return slotFrame:FindFirstChild("Icon") :: ImageLabel?
end

local function ApplySlotHighlight(
    slotFrame,
    slot : number,
    slotTool : Tool?,
    equipped : Tool?,
    lastEquippedSlot : number?
)
    if not slotFrame then return end

    local slotColor = INACTIVE_SLOT_COLOR
    local iconColor = INACTIVE_SLOT_COLOR

    if equipped then
        if equipped == slotTool then
            slotColor = ACTIVE_SLOT_COLOR
            iconColor = ACTIVE_SLOT_COLOR
        end
    elseif lastEquippedSlot == slot then
        iconColor = LAST_EQUIPPED_SLOT_COLOR
    end

    local icon = GetSlotIcon(slotFrame, slot)

    if slot == 2 then
        if icon then
            icon.ImageColor3 = iconColor
        end
        return
    end

    slotFrame.ImageColor3 = slotColor

    if icon then
        icon.ImageColor3 = iconColor
    end
end

-- there's a single shared ammo readout in the whole HUD, so write the equipped tool's ammo into
-- every Current/Stock label we find. blank when nothing is held.
local function SetAmmoText(tool : Tool?)
    local WeaponHUD = GetWeaponHUD()
    if not WeaponHUD then return end

    local currentText, stockText = "", ""
    if tool then
        local Ammo, MaxAmmo = GetToolAmmo(tool)
        currentText = tostring(Ammo)
        stockText = tostring(MaxAmmo)
    end

    for _, label in WeaponHUD:GetDescendants() do
        if label:IsA("TextLabel") then
            if label.Name == "Current" or label.Name == "CurrentGlow" then
                label.Text = currentText
            elseif label.Name == "Stock" or label.Name == "StockGlow" then
                label.Text = stockText
            end
        end
    end
end

local function GetKnownTools()
    local tools = {}
    local seen = {}

    local function addTools(parent)
        if not parent then return end
        for _, child in parent:GetChildren() do
            if IsWeaponTool(child) and not seen[child] then
                seen[child] = true
                table.insert(tools, child)
            end
        end
    end

    addTools(Backpack)
    addTools(Character)

    return tools
end

local function GetAssignedSlot(tool : Tool)
    local slot = tonumber(tool:GetAttribute("Slot") or tool:GetAttribute("HotbarSlot"))
    if slot == 1 or slot == 2 then
        ToolSlots[tool] = slot
        return slot
    end

    if ToolSlots[tool] then
        return ToolSlots[tool]
    end

    local used = {}
    for existingTool, existingSlot in ToolSlots do
        if existingTool.Parent and (existingSlot == 1 or existingSlot == 2) then
            used[existingSlot] = true
        end
    end

    for nextSlot = 1, 2 do
        if not used[nextSlot] then
            ToolSlots[tool] = nextSlot
            return nextSlot
        end
    end
end

local function GetSlotTools()
    local slotTools = {}
    for _, tool in GetKnownTools() do
        local slot = GetAssignedSlot(tool)
        if slot and not slotTools[slot] then
            slotTools[slot] = tool
        end
    end
    return slotTools
end

local function RefreshWeaponUI()
    local slotTools = GetSlotTools()
    local Primary = GetSlotFrame("Primary")
    local Secondary = GetSlotFrame("Secondary")
    local equipped = Character and Character:FindFirstChildOfClass("Tool")

    -- one shared ammo readout follows the equipped weapon; fall back to the most recently equipped
    -- (or the primary) so it isn't blank before the first equip
    SetAmmoText(equipped or LastEquippedTool or slotTools[1])

    -- active slot = cyan on frame + icon; when nothing is held, last-equipped icon = yellow
    local lastEquippedSlot = if not equipped and LastEquippedTool then GetAssignedSlot(LastEquippedTool) else nil
    ApplySlotHighlight(Primary, 1, slotTools[1], equipped, lastEquippedSlot)
    ApplySlotHighlight(Secondary, 2, slotTools[2], equipped, lastEquippedSlot)
end

local function TrackToolAmmo(tool : Tool)
    if AmmoConnections[tool] then
        return
    end

    AmmoConnections[tool] = {
        tool:GetAttributeChangedSignal("Ammo"):Connect(RefreshWeaponUI),
        tool:GetAttributeChangedSignal("MaxAmmo"):Connect(RefreshWeaponUI),
        tool.AncestryChanged:Connect(RefreshWeaponUI),
    }
end

local function RefreshToolTracking()
    for _, tool in GetKnownTools() do
        TrackToolAmmo(tool)
        GetAssignedSlot(tool)
    end
    RefreshWeaponUI()
end

-- equip the tool assigned to a slot (1 = primary, 2 = secondary). pressing the slot that's already
-- equipped puts it away. we drive this ourselves since the default backpack hotkeys are disabled.
local function EquipSlot(slot : number)
    local character = Player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local tool = GetSlotTools()[slot]
    if not tool then return end

    if tool.Parent == character then
        humanoid:UnequipTools() -- already out, so toggle it away
    else
        humanoid:EquipTool(tool)
    end
end

local SLOT_KEYS = {
    [Enum.KeyCode.One] = 1,
    [Enum.KeyCode.Two] = 2,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local slot = SLOT_KEYS[input.KeyCode]
    if slot then
        EquipSlot(slot)
    end
end)

function InterfaceController.EquipPrimary(self, Tool)
    if not IsWeaponTool(Tool) then return end

    LastEquippedTool = Tool
    TrackToolAmmo(Tool)
    GetAssignedSlot(Tool)
    RefreshWeaponUI()
end 

function InterfaceController.SetAmmo(self)
    RefreshWeaponUI()
end 

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



local function OnCharacterReady(character)
    Character = character
    PlayerGui = Player.PlayerGui
    Backpack = Player.Backpack
    PlayerGui:WaitForChild("AJ", 10)
    HideRobloxToolbar()

    for _, connection in CharacterConnections do
        connection:Disconnect()
    end
    table.clear(CharacterConnections)

    if BackpackConnection then
        BackpackConnection:Disconnect()
        BackpackConnection = nil
    end

    table.insert(CharacterConnections, Character:GetAttributeChangedSignal("Dashes"):Connect(function()
        InterfaceController:UpdateDash(Character)
    end))

    table.insert(CharacterConnections, Character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            LastEquippedTool = child
            RefreshToolTracking()
        end
    end))

    table.insert(CharacterConnections, Character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            RefreshWeaponUI()
        end
    end))

    BackpackConnection = Backpack.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            RefreshToolTracking()
        end
    end)

    for _, child in GetKnownTools() do
        if child:IsA("Tool") then
            TrackToolAmmo(child)
            GetAssignedSlot(child)
            InterfaceController:SetAmmo()
        end
    end

    -- sync hud to a fresh state each life (changed signals won't fire for spawn defaults)
    InterfaceController:RegenGrapple()
    InterfaceController:UpdateDash(Character)
    RefreshToolTracking()
end

Player.CharacterAdded:Connect(OnCharacterReady)

if Player.Character then
    OnCharacterReady(Player.Character)
end


return InterfaceController 
