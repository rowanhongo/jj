--!strict
-- Phone vibration through Roblox's HapticEffect (UIClick / UINotification presets; does nothing
-- on devices without haptics). Every touch on any button gets a very light tick; picking up a
-- ? box gets a stronger double buzz.
--
--   Haptics.tap()    light tick
--   Haptics.big()    stronger, for exciting moments
--   Haptics.hookButtons(playerGui)   light tick on touching any GuiButton

local UserInputService = game:GetService("UserInputService")
local HapticService = game:GetService("HapticService")

-- the older route (phones report as Gamepad1); used as well, as some phones only answer this one
local function motor(strength: number, seconds: number)
	pcall(function()
		local g = Enum.UserInputType.Gamepad1
		-- the first connected gamepad (a console controller), else Gamepad1 (phones report as it)
		for _, pad in UserInputService:GetConnectedGamepads() do
			g = pad
			break
		end
		if HapticService:IsVibrationSupported(g) then
			local m = Enum.VibrationMotor.Large
			if HapticService:IsMotorSupported(g, m) then
				HapticService:SetMotor(g, m, strength)
				task.delay(seconds, function()
					HapticService:SetMotor(g, m, 0)
				end)
			end
		end
	end)
end

local Haptics = {}

local cache: { [string]: HapticEffect } = {}
local function play(typeName: string)
	if not UserInputService.TouchEnabled then
		return
	end
	local e = cache[typeName]
	if not e then
		local ok, made = pcall(function()
			local h = Instance.new("HapticEffect")
			h.Type = (Enum.HapticEffectType :: any)[typeName]
			h.Parent = workspace
			return h
		end)
		if not ok then
			return
		end
		e = made
		cache[typeName] = e
	end
	pcall(e.Play, e)
end

local lastTap = 0
function Haptics.tap()
	local t = os.clock()
	if t - lastTap < 0.05 then
		return
	end
	lastTap = t
	play("UIClick")
	motor(0.35, 0.03)
end

function Haptics.big()
	play("GameplayExplosion")
	motor(1, 0.12)
	task.delay(0.18, function()
		play("GameplayCollision")
		motor(0.8, 0.08)
	end)
end

function Haptics.hookButtons(root: Instance)
	local function hook(d: Instance)
		if d:IsA("GuiButton") then
			d.InputBegan:Connect(function(io)
				-- touch (phones, tablets) or pressing A on a selected button with a controller
				if io.UserInputType == Enum.UserInputType.Touch or io.KeyCode == Enum.KeyCode.ButtonA then
					Haptics.tap()
				end
			end)
		end
	end
	for _, d in root:GetDescendants() do
		hook(d)
	end
	root.DescendantAdded:Connect(hook)
end

return Haptics
