-- team definitions + per-team loadouts. tool names must match children of ServerStorage.Tools
-- (and ideally WeaponsConfig keys, so the HUD can read ammo). a loadout has a Primary (slot 1)
-- and a Secondary (slot 2); either may be nil for an empty slot.

local LoadoutConfig = {}

-- the three teams. AutoAssignable teams get balanced players on join; Spectators are opt-in.
LoadoutConfig.Teams = {
	Spectators = {
		TeamColor = BrickColor.new("Medium stone grey"),
		AutoAssignable = false,
		Loadout = {
			Primary = nil,
			Secondary = nil,
		},
	},

	Hostiles = {
		TeamColor = BrickColor.new("Bright red"),
		AutoAssignable = true,
		Loadout = {
			Primary = "Plasma Rifle",
			Secondary = "Energy Sword",
		},
	},

	Covenant = {
		TeamColor = BrickColor.new("Bright blue"),
		AutoAssignable = true,
		Loadout = {
			Primary = "Plasma Rifle",
			Secondary = "Energy Sword",
		},
	},
}

-- handed out when a player isn't on any of the known teams (neutral / unknown team)
LoadoutConfig.EmergencyDefault = {
	Primary = "Energy Sword",
	Secondary = nil,
}

-- resolve the loadout for a team name, falling back to the emergency default
function LoadoutConfig.GetLoadout(teamName : string?)
	local team = teamName and LoadoutConfig.Teams[teamName]
	if team and team.Loadout then
		return team.Loadout
	end
	return LoadoutConfig.EmergencyDefault
end

return LoadoutConfig
