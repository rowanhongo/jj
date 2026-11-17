--!strict
-- Draws the bots. The server sends one small packet for all bots ~20 times a second on the
-- BotSnap UnreliableRemoteEvent (server time, then per bot: index, position, yaw); it never moves
-- their parts itself. Every client keeps the recent snapshots per bot and draws each bot a little
-- in the past, blending between the two snapshots around that moment, so movement is smooth at
-- any frame rate. The delay adapts to the connection: it grows when packets arrive unevenly
-- (phones on Wi-Fi) and shrinks back on a steady link. If packets stop for a moment the bot
-- carries on at its last speed instead of freezing.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BotSmooth = {}

local MIN_DELAY, MAX_DELAY = 0.1, 0.35
local MAX_EXTRAPOLATE = 0.3
type Snap = { t: number, cf: CFrame }
-- off: a leftover correction, faded out over a few frames (when a guess-ahead ends, the bot
-- glides onto the real path instead of snapping back to it)
type Track = { root: BasePart, snaps: { Snap }, guessing: boolean, last: Vector3?, off: Vector3 }

local byIdx: { [number]: Track } = {}
local delay = 0.2
local wantDelay = 0.2
-- The drawn moment must never jump backwards: a sudden bigger delay (one late packet) used to
-- pull every bot back a step, the "snap back every few seconds". The delay now drifts toward its
-- target at most DRIFT seconds per second, so the bots' clock only runs a few % slow or fast.
local DRIFT = 0.05
local lastAt = -math.huge
local lastArrive: number? = nil
local gapAvg, gapDev = 0.05, 0.01

local function watch(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local root = m:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local idx = m:GetAttribute("Idx")
	if not root or type(idx) ~= "number" then
		return
	end
	local tr: Track = { root = root, snaps = {}, guessing = false, last = nil, off = Vector3.zero }
	byIdx[idx] = tr
	local function drop()
		if byIdx[idx] == tr then
			byIdx[idx] = nil
		end
	end
	m:GetAttributeChangedSignal("Out"):Connect(drop) -- out: the server places it from here
	m.AncestryChanged:Connect(function()
		if not m.Parent then
			drop()
		end
	end)
end

local function onSnap(buf: buffer)
	-- the delay follows how evenly packets arrive: average gap plus a margin for the jitter
	local now = os.clock()
	if lastArrive then
		local gap = now - (lastArrive :: number)
		if gap < 1 then
			gapAvg += (gap - gapAvg) * 0.1
			gapDev += (math.abs(gap - gapAvg) - gapDev) * 0.1
		end
	end
	lastArrive = now
	wantDelay = math.clamp(gapAvg * 2 + gapDev * 4, MIN_DELAY, MAX_DELAY)

	local t = buffer.readf64(buf, 0)
	local n = (buffer.len(buf) - 8) // 17
	for i = 0, n - 1 do
		local o = 8 + i * 17
		local tr = byIdx[buffer.readu8(buf, o)]
		if tr then
			local pos = Vector3.new(buffer.readf32(buf, o + 1), buffer.readf32(buf, o + 5), buffer.readf32(buf, o + 9))
			local s = tr.snaps
			-- unreliable packets can arrive out of order: keep only newer ones
			if #s == 0 or t > s[#s].t then
				table.insert(s, { t = t, cf = CFrame.new(pos) * CFrame.Angles(0, buffer.readf32(buf, o + 13), 0) })
				if #s > 30 then
					table.remove(s, 1)
				end
			end
		end
	end
end

function BotSmooth.init()
	local function folder(f: Instance)
		if f.Name ~= "Bots" then
			return
		end
		for _, m in f:GetChildren() do
			task.spawn(watch, m)
		end
		f.ChildAdded:Connect(watch)
	end
	for _, c in workspace:GetChildren() do
		folder(c)
	end
	workspace.ChildAdded:Connect(folder)

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local ev = remotes:WaitForChild("BotSnap", 600) :: UnreliableRemoteEvent?
		if ev then
			ev.OnClientEvent:Connect(onSnap)
		end
	end)

	-- before the camera, so a spectating camera follows the drawn bot
	RunService:BindToRenderStep("JJBotSmooth", Enum.RenderPriority.Camera.Value - 1, function(dt)
		delay += math.clamp(wantDelay - delay, -DRIFT * dt, DRIFT * dt)
		local at = math.max(workspace:GetServerTimeNow() - delay, lastAt)
		lastAt = at
		for _, tr in byIdx do
			local s = tr.snaps
			local n = #s
			if n == 0 then
				continue
			end
			while n >= 3 and s[2].t <= at do
				table.remove(s, 1)
				n -= 1
			end
			local cf: CFrame
			local guessing = false
			if n == 1 or at <= s[1].t then
				cf = s[1].cf
			elseif at >= s[n].t then
				guessing = true
				-- ran out of snapshots: carry on at the last speed for a moment instead of freezing
				local a, b = s[n - 1], s[n]
				local over = math.min(at - b.t, MAX_EXTRAPOLATE)
				local v = (b.cf.Position - a.cf.Position) / math.max(b.t - a.t, 1e-3)
				cf = b.cf.Rotation + b.cf.Position + v * over
			else
				local a, b = s[1], s[2]
				local u = (at - a.t) / math.max(b.t - a.t, 1e-3)
				cf = a.cf:Lerp(b.cf, math.clamp(u, 0, 1))
			end
			if tr.guessing and not guessing and tr.last then
				tr.off = (tr.last :: Vector3) - cf.Position
			end
			tr.guessing = guessing
			if tr.off.Magnitude > 20 then
				tr.off = Vector3.zero -- a real jump (respawn, zipline end): don't glide across it
			end
			tr.off *= math.exp(-8 * dt)
			cf += tr.off
			tr.last = cf.Position
			tr.root.CFrame = cf
		end
	end)
end

return BotSmooth
