-- preload movement anims at join so first dash/grapple doesnt hitch

local ContentProvider = game:GetService("ContentProvider")
local MovementConfig = require(game.ReplicatedStorage.Shared.MovementConfig)

local PreloadAnimations = {}

local function addId(seen: { [string]: boolean }, ids: { string }, id: any)
	if typeof(id) ~= "string" or id == "" then
		return
	end
	if not string.match(id, "^rbxassetid://") then
		return
	end
	if seen[id] then
		return
	end
	seen[id] = true
	table.insert(ids, id)
end

local function gatherAnimationAssetIds(): { string }
	local seen: { [string]: boolean } = {}
	local ids: { string } = {}

	addId(seen, ids, MovementConfig.Walk.DefaultAnimation)
	addId(seen, ids, MovementConfig.Walk.LocalAnimation)

	local sprint = MovementConfig.Sprint
	if sprint then
		addId(seen, ids, sprint.DefaultAnimation)
	end

	local dashLocals = MovementConfig.Dash and MovementConfig.Dash.LocalAnimations
	if dashLocals then
		for _, animId in pairs(dashLocals) do
			addId(seen, ids, animId)
		end
	end

	local dashSword = MovementConfig.Dash and MovementConfig.Dash.SwordAnimations
	if dashSword then
		for _, animId in pairs(dashSword) do
			addId(seen, ids, animId)
		end
	end

	addId(seen, ids, MovementConfig.Grapple.LocalAnimation)
	addId(seen, ids, MovementConfig.Grapple.SwordAnimation)

	return ids
end

function PreloadAnimations.Preload()
	local ids = gatherAnimationAssetIds()
	if #ids == 0 then
		return
	end

	local instances: { Instance } = {}
	for _, id in ipairs(ids) do
		local anim = Instance.new("Animation")
		anim.Name = "Preload_" .. (id:match("%d+$") or id)
		anim.AnimationId = id
		table.insert(instances, anim)
	end

	ContentProvider:PreloadAsync(instances)

	for _, inst in ipairs(instances) do
		inst:Destroy()
	end
end

PreloadAnimations.Preload()

return PreloadAnimations 
