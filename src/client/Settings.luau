--!strict
-- This player's settings on this client. Values come from the saved profile (SettingsDefs says
-- what each is); set() changes it here at once and asks the server to save it.
-- Sounds join the Music or Sfx SoundGroup, whose volume follows the two volume settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local SettingsDefs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SettingsDefs"))

local Settings = {}

local saved: { [string]: any } = {}
local listeners: { [string]: { (any) -> () } } = {}

local function group(name: string): SoundGroup
	local g = SoundService:FindFirstChild("JJ_" .. name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = "JJ_" .. name
		g.Parent = SoundService
	end
	return g :: SoundGroup
end
Settings.music = group("Music")
Settings.sfx = group("Sfx")

function Settings.get(id: string): any
	return SettingsDefs.read(saved, id)
end

-- fn(value) now and on every change
function Settings.watch(id: string, fn: (any) -> ())
	listeners[id] = listeners[id] or {}
	table.insert(listeners[id], fn)
	task.spawn(fn, Settings.get(id))
end

local function fire(id: string)
	for _, fn in listeners[id] or {} do
		task.spawn(fn, Settings.get(id))
	end
end

-- change it here only (a slider while it is dragged); set() or commit() saves it
function Settings.preview(id: string, v: any)
	if not SettingsDefs.valid(id, v) or Settings.get(id) == v then
		return
	end
	saved[id] = v
	fire(id)
end

local function save(id: string, v: any)
	task.spawn(function()
		local call = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShopCall") :: RemoteFunction
		pcall(call.InvokeServer, call, "Setting", id, v)
	end)
end

function Settings.set(id: string, v: any)
	if not SettingsDefs.valid(id, v) or Settings.get(id) == v then
		return
	end
	saved[id] = v
	fire(id)
	save(id, v)
end

-- save what preview() set (on slider release)
function Settings.commit(id: string)
	save(id, Settings.get(id))
end

-- a sound plays through the music or effects volume
function Settings.asMusic(s: Sound)
	s.SoundGroup = Settings.music
end
function Settings.asSfx(s: Sound)
	s.SoundGroup = Settings.sfx
end

function Settings.init()
	Settings.watch("Music", function(v)
		Settings.music.Volume = v / 100
	end)
	Settings.watch("Sfx", function(v)
		Settings.sfx.Volume = v / 100
	end)
	local shadows = Lighting.GlobalShadows
	Settings.watch("LowFx", function(low)
		Lighting.GlobalShadows = shadows and not low
	end)
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Profile").OnClientEvent:Connect(function(p)
		local s = type(p) == "table" and p.settings
		if type(s) ~= "table" then
			return
		end
		local before = {}
		for _, d in SettingsDefs.list do
			before[d.id] = Settings.get(d.id)
		end
		saved = s
		for _, d in SettingsDefs.list do
			if Settings.get(d.id) ~= before[d.id] then
				fire(d.id)
			end
		end
	end)
end

return Settings
