--!strict
-- Shop, inventory and loadout. The server owns every purchase and every roll.
-- Remotes (in ReplicatedStorage.Remotes):
--   Profile   (event, server -> client) full profile snapshot after any change
--   ShopCall  (function) action, args... -> ok, result
--     "Roll", n(1|10)          -> { ids }, each a gadget id, in order
--     "BuyDaily", cosmeticId   -> true
--     "Equip", kind, id        -> true   kind = Title | Emote | Trail
--     "Loadout", { ids }       -> true   up to Items.LoadoutSize owned gadgets
--     "Showcase", modeId       -> true
--     "Daily"                  -> { ids }, endsAt (unix)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared.Items)
local Palette = require(Shared.Palette)
local DataService = require(script.Parent.DataService)

local ShopService = {}

local rng = Random.new()

-- Daily shop: the same 4 cosmetics for everyone, picked from the UTC day number.
function ShopService.daily(): ({ string }, number)
	local day = math.floor(os.time() / 86400)
	local r = Random.new(day * 7919)
	local pool = {}
	for _, c in Items.Cosmetics do
		if c.price > 0 then
			table.insert(pool, c.id)
		end
	end
	local out = {}
	for _ = 1, Items.DailySlots do
		local i = r:NextInteger(1, #pool)
		table.insert(out, table.remove(pool, i) :: string)
	end
	return out, (day + 1) * 86400
end

local order = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Mythic = 5 }

local function rollOne(p: DataService.Profile): string
	-- Pity first: the highest rarity whose counter has run out.
	local forced: string? = nil
	for _, r in { "Mythic", "Epic", "Rare" } do
		if (p.pity[r] or 0) + 1 >= Items.Pity[r] then
			forced = r
			break
		end
	end
	local rarity = forced
	if not rarity then
		local x = rng:NextNumber() * 100
		for _, r in Items.Rarities do
			x -= Items.RarityWeight[r]
			if x <= 0 then
				rarity = r
				break
			end
		end
		rarity = rarity or "Common"
	end
	local pool = {}
	for _, g in Items.Gadgets do
		if g.rarity == rarity then
			table.insert(pool, g.id)
		end
	end
	local id = pool[rng:NextInteger(1, #pool)]
	for _, r in { "Rare", "Epic", "Mythic" } do
		if order[rarity :: string] >= order[r] then
			p.pity[r] = 0
		else
			p.pity[r] = (p.pity[r] or 0) + 1
		end
	end
	p.items[id] = (p.items[id] or 0) + 1
	p.rolls += 1
	return id
end

local function owned(p: DataService.Profile, id: string): boolean
	return (p.items[id] or 0) > 0
end

local handlers: { [string]: (Player, DataService.Profile, ...any) -> any } = {}

handlers.Roll = function(player, p, n)
	local count = n == 10 and 10 or 1
	local price = count == 10 and Items.Roll10Price or Items.RollPrice
	if p.gems < price then
		return nil
	end
	p.gems -= price
	local out = {}
	for _ = 1, count do
		table.insert(out, rollOne(p))
	end
	print(string.format("[JJ.Shop] %s rolled %d: %s", player.Name, count, table.concat(out, ",")))
	return out
end

handlers.BuyDaily = function(_, p, id)
	local today = ShopService.daily()
	local c = Items.get(id)
	if not c or not table.find(today, id) or p.cosmetics[id] or p.gems < c.price then
		return nil
	end
	p.gems -= c.price
	p.cosmetics[id] = true
	return true
end

handlers.Equip = function(_, p, kind, id)
	if kind ~= "Title" and kind ~= "Emote" and kind ~= "Trail" then
		return nil
	end
	if id == "" and kind == "Trail" then
		p.equipped.Trail = nil
		return true
	end
	local c = Items.get(id)
	if not c or c.kind ~= kind or not p.cosmetics[id] then
		return nil
	end
	p.equipped[kind] = id
	return true
end

handlers.Loadout = function(_, p, ids)
	if type(ids) ~= "table" or #ids > Items.LoadoutSize then
		return nil
	end
	local clean = {}
	for _, id in ids do
		if type(id) == "string" and owned(p, id) and not table.find(clean, id) then
			table.insert(clean, id)
		end
	end
	if #clean == 0 then
		return nil
	end
	p.loadout = clean
	return true
end

handlers.Showcase = function(_, p, mode)
	for _, m in Items.Modes do
		if m.id == mode then
			p.showcase = mode
			return true
		end
	end
	return nil
end

handlers.Daily = function()
	local ids, ends = ShopService.daily()
	return { ids = ids, endsAt = ends }
end

-- Trail: a simple Trail between two body attachments, coloured from the palette.
local function applyTrail(player: Player)
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local old = root:FindFirstChild("JJTrail")
	if old then
		old:Destroy()
	end
	local id = player:GetAttribute("Trail")
	local cos = id and id ~= "" and Items.get(id)
	if not cos or not cos.colour then
		return
	end
	local a0 = root:FindFirstChild("JJTrailA0") or Instance.new("Attachment")
	a0.Name = "JJTrailA0"
	a0.Position = Vector3.new(0, 0.8, 0.4)
	a0.Parent = root
	local a1 = root:FindFirstChild("JJTrailA1") or Instance.new("Attachment")
	a1.Name = "JJTrailA1"
	a1.Position = Vector3.new(0, -1.6, 0.4)
	a1.Parent = root
	local t = Instance.new("Trail")
	t.Name = "JJTrail"
	t.Attachment0 = a0 :: Attachment
	t.Attachment1 = a1 :: Attachment
	t.Color = ColorSequence.new((Palette :: any)[cos.colour])
	t.Transparency = NumberSequence.new(0.2, 1)
	t.Lifetime = 0.45
	t.LightEmission = 0.4
	t.Parent = root
end

function ShopService.init(remotes: Folder)
	local profileEv = Instance.new("RemoteEvent")
	profileEv.Name = "Profile"
	profileEv.Parent = remotes
	local call = Instance.new("RemoteFunction")
	call.Name = "ShopCall"
	call.Parent = remotes

	DataService.setPusher(function(player, p)
		profileEv:FireClient(player, p)
	end)

	call.OnServerInvoke = function(player, action, ...)
		local p = DataService.get(player)
		local h = type(action) == "string" and handlers[action]
		if not p or not h then
			return false, nil
		end
		local ok, res = pcall(h, player, p, ...)
		if not ok then
			warn("[JJ.Shop]", action, res)
			return false, nil
		end
		if res ~= nil and action ~= "Daily" then
			DataService.sync(player)
			if action == "Equip" then
				applyTrail(player)
			end
		end
		return res ~= nil, res
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			applyTrail(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, pl in Players:GetPlayers() do
		onPlayer(pl)
	end
end

return ShopService
