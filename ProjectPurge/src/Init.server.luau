-- boots all server modules in ServerScriptService.Server

local ServerFolder = game.ServerScriptService.Server

local function InitScript(Script : ModuleScript)
    local Ran, Result = pcall(require, Script)
    if not Ran then
        warn("Warning, module script failed to load on the client:", Script:GetFullName())
    end
    return Result
end

for _, Script in ServerFolder:GetChildren() do
    if Script:IsA("ModuleScript") then
        local Run = InitScript(Script)
    end
end

ServerFolder.ChildAdded:Connect(function(Child)
    if Child:IsA("ModuleScript") then 
        local Run = InitScript(Child)
    end 
end)
