-- boots all client modules in StarterPlayerScripts.Client

local ClientFolder = game.StarterPlayer.StarterPlayerScripts:WaitForChild("Client")

local function InitScript(Script : ModuleScript)
    local Ran, Result = pcall(require, Script)
    if not Ran then
        warn("Warning, module script failed to load on the client:", Script:GetFullName())
    end
    return Result
end

-- preload anims first so nothing stutters mid-game
local PreloadModule = ClientFolder:FindFirstChild("PreloadAnimations")
if PreloadModule and PreloadModule:IsA("ModuleScript") then
    InitScript(PreloadModule)
end

for _, Script in ClientFolder:GetChildren() do
    if Script:IsA("ModuleScript") and Script ~= PreloadModule then
        InitScript(Script)
    end
end

-- hot-reload if you add modules while playtesting
ClientFolder.ChildAdded:Connect(function(Child)
    if Child:IsA("ModuleScript") and Child.Name ~= "PreloadAnimations" then 
        InitScript(Child)
    end 
end)
