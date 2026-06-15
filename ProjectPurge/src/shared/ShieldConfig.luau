-- shield + health defaults, highlight colors, sfx ids

return {
	REGEN_DELAY_AFTER_DAMAGE = 10, -- seconds before regen kicks in
	DEFAULT_HEALTH = 25,
	DEFAULT_SHIELD = 100,
	SHIELD_HIGHLIGHT = {
		FillColor = Color3.fromRGB(242, 210, 90),
		FillTransparency = 0.6,
		OutlineColor = Color3.fromRGB(215, 180, 70),
		OutlineTransparency = 0.2,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
	},
	SHIELD_SOUND_IDS = {
        Charge = "rbxassetid://6242368397",
        Deplete = "rbxassetid://137787508848769",
        Break = "rbxassetid://86717349989793"
    }
}
