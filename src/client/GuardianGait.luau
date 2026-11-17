--!strict
-- The Guardian's run: the server only moves the forest monster along the path (PivotTo), and each
-- client turns its legs over from how far it actually moved, so the stride always matches its
-- speed and it stands still when it stops (countdown, parked under the map).
--
-- Bone axes (measured in Studio): rotating a leg bone about its local +X swings it forward;
-- the face looks down -Z.

local RunService = game:GetService("RunService")

local GuardianGait = {}

local STRIDE = 17 -- studs per full stride (two steps) at 25 studs tall

function GuardianGait.init()
	local model: Model? = nil
	local bones: { [string]: Bone } = {}
	local last: Vector3? = nil
	local phase = 0
	local blend = 0 -- 0 standing, 1 full run
	local smooth = 0 -- speed, smoothed: server moves arrive in network steps, not every frame

	local function bind(m: Model?)
		model = m
		table.clear(bones)
		last = nil
		if not m then
			return
		end
		for _, d in m:GetDescendants() do
			if d:IsA("Bone") then
				bones[d.Name] = d
			end
		end
	end
	local function rot(name: string, x: number, y: number?)
		local b = bones[name]
		if b then
			b.Transform = CFrame.Angles(x, y or 0, 0)
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		if not model or not model.Parent then
			local g = workspace:FindFirstChild("Guardian")
			bind(if g and g:IsA("Model") then g else nil)
			if not model then
				return
			end
		end
		local m = model :: Model
		dt = math.max(dt, 1 / 240)
		local pos = m:GetPivot().Position
		local speed = 0
		if last then
			local d = pos - (last :: Vector3)
			speed = Vector3.new(d.X, 0, d.Z).Magnitude / dt
			if speed > 400 then
				speed = 0 -- a teleport (parked / placed at the start), not running
			end
		end
		last = pos
		smooth += (speed - smooth) * math.min(1, dt * 5)
		blend += ((smooth > 2 and 1 or 0) - blend) * math.min(1, dt * 6)
		phase += (smooth / STRIDE) * 2 * math.pi * dt
		local s, c = math.sin(phase), math.cos(phase)
		local k = blend
		for side, sgn in { L = 1, R = -1 } do
			local ls, lc = s * sgn, c * sgn
			rot("UpperLeg." .. side, k * 0.66 * ls)
			rot("LowerLeg." .. side, -k * (0.25 + 1.15 * math.max(0, lc)))
			rot("Foot." .. side, k * (0.35 * lc - 0.1))
			rot("UpperArm." .. side, -k * 0.5 * ls)
			rot("LowerArm." .. side, k * (0.35 + 0.25 * math.max(0, ls)))
		end
		rot("Spine", 0, k * 0.12 * s)
		rot("Chest", 0, k * 0.1 * s)
		rot("Neck", 0, -k * 0.15 * s)
	end)
end

return GuardianGait
