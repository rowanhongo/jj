--!strict
-- Player settings: what each one is, its choices and default. The server checks every change
-- against this list before saving it; the client draws the Settings panel from it.
-- Only things Roblox's own menu can't do (it already has master volume, graphics quality,
-- camera sensitivity and fullscreen).

export type Def = {
	id: string,
	name: string,
	hint: string,
	steps: { string }?, -- a stepper: the value is the index into steps
	slider: boolean?, -- a 0-100 slider in steps of 10 (the value is the percent)
	default: number | boolean,
	touchOnly: boolean?,
}

local defs: { Def } = {
	{ id = "Music", name = "Music", hint = "Lobby and run music", slider = true, default = 100 },
	{ id = "Sfx", name = "Sound effects", hint = "Pickups, footsteps, the Guardian", slider = true, default = 100 },
	{
		id = "Steer",
		name = "Steering",
		hint = "How far one tap of an arrow moves you",
		steps = { "Very low", "Low", "Normal", "High", "Very high" },
		default = 3,
		touchOnly = true,
	},
	{ id = "SpeedZoom", name = "Speed zoom", hint = "Camera widens as you run faster", default = true },
	{ id = "LowFx", name = "Low effects", hint = "Fewer effects for smoother play", default = false },
}

local byId: { [string]: Def } = {}
for _, d in defs do
	byId[d.id] = d
end

local SettingsDefs = {}
SettingsDefs.list = defs
SettingsDefs.byId = byId
SettingsDefs.STEP = 10 -- slider step, percent
-- volumes saved before the sliders (a 1-5 step index): the nearest slider value
local LEGACY_VOLUME = { 0, 30, 50, 80, 100 }

-- true when v is an allowed value for setting id
function SettingsDefs.valid(id: any, v: any): boolean
	local d = type(id) == "string" and byId[id]
	if not d then
		return false
	end
	if d.slider then
		return type(v) == "number" and v % SettingsDefs.STEP == 0 and v >= 0 and v <= 100
	end
	if d.steps then
		return type(v) == "number" and v % 1 == 0 and v >= 1 and v <= #d.steps
	end
	return type(v) == "boolean"
end

function SettingsDefs.read(saved: { [string]: any }?, id: string): any
	local v = saved and saved[id]
	local d = byId[id]
	if d and d.slider and type(v) == "number" and v >= 1 and v <= 5 and v % 1 == 0 then
		v = LEGACY_VOLUME[v]
	end
	if v ~= nil and SettingsDefs.valid(id, v) then
		return v
	end
	return byId[id].default
end

return table.freeze(SettingsDefs)
