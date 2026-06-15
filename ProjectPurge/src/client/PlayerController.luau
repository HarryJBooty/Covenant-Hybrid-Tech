-- helper to read equipped tool type from character

local PlayerService = game:GetService("Players")
local Player = PlayerService.LocalPlayer
local PlayerController = {}

function PlayerController.GetTool()
    local Character = Player.Character
    local Type = nil 
    for _, PotentialTool in Character:GetChildren() do
        if PotentialTool:IsA("Tool") then
            Type = tostring(PotentialTool:GetAttribute("Type"))
        end
    end

    if Type == nil then
        Type = "Empty" 
    end

    return Type

end 

return PlayerController 
