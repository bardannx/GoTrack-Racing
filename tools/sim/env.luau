--!nocheck
-- Lune harness: runs the game's client/shared Luau outside Roblox Studio.
-- Real Roblox instances and datatypes come from @lune/roblox; services that need the
-- engine (RunService, Players, TweenService, ...) are small mocks. Modules are loaded
-- straight from src/ with a per-module `script` that mirrors the Rojo tree, so
-- `require(script.Parent.X)` and `game.ReplicatedStorage.Shared` work unchanged.

local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local task = require("@lune/task")

local Env = {}
Env.Patches = {} -- [module path] = fn(module): adjust a module right after it loads

local game = roblox.Instance.new("DataModel")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
Env.Game = game
Env.Workspace = Workspace
Env.Lighting = Lighting
Env.Errors = {}

---------------------------------------------------------------------------
-- Random (not provided by Lune)
---------------------------------------------------------------------------
local Random = {}
Random.__index = Random
function Random.new(seed)
	local s = setmetatable({}, Random)
	local v = math.floor(math.abs(tonumber(seed) or os.clock() * 1e6)) % 2147483646 + 1
	s._s = v
	for _ = 1, 3 do
		s:_next()
	end
	return s
end
function Random:_next()
	self._s = (self._s * 48271) % 2147483647
	return self._s / 2147483647
end
function Random:NextNumber(a, b)
	local r = self:_next()
	if a then
		return a + (b - a) * r
	end
	return r
end
function Random:NextInteger(a, b)
	return math.min(b, math.floor(a + (b - a + 1) * self:_next()))
end

---------------------------------------------------------------------------
-- Signals and service mocks
---------------------------------------------------------------------------
local function Signal()
	local s = { _c = {} }
	function s:Connect(fn)
		local c = { Connected = true }
		table.insert(s._c, c)
		c.Fn = fn
		function c:Disconnect()
			c.Connected = false
		end
		return c
	end
	function s:Once(fn)
		return s:Connect(fn)
	end
	function s:Fire(...)
		for _, c in s._c do
			if c.Connected then
				c.Fn(...)
			end
		end
	end
	function s:Wait()
		return task.wait()
	end
	return s
end
Env.Signal = Signal

local serverTime = 1000
local RunService = {
	RenderStepped = Signal(),
	Heartbeat = Signal(),
	Stepped = Signal(),
	PreRender = Signal(),
}
function RunService:IsStudio()
	return true
end
function RunService:IsClient()
	return true
end
function RunService:IsServer()
	return false
end
local renderSteps = {}
function RunService:BindToRenderStep(name, _priority, fn)
	renderSteps[name] = fn
end
function RunService:UnbindFromRenderStep(name)
	renderSteps[name] = nil
end
-- RenderStepped also runs everything bound with BindToRenderStep (the camera)
RunService.RenderStepped:Connect(function(dt)
	for _, fn in renderSteps do
		fn(dt)
	end
end)
Env.RunService = RunService

local UserInputService = {
	TouchEnabled = false,
	KeyboardEnabled = true,
	GamepadEnabled = false,
	MouseEnabled = true,
	InputBegan = Signal(),
	InputEnded = Signal(),
	InputChanged = Signal(),
	TouchStarted = Signal(),
	TouchEnded = Signal(),
	TouchMoved = Signal(),
	LastInputTypeChanged = Signal(),
}
-- any other event (TouchPinch, WindowFocused, ...) is a do-nothing signal
setmetatable(UserInputService, {
	__index = function(t, k)
		local sig = Signal()
		rawset(t, k, sig)
		return sig
	end,
})
function UserInputService:GetLastInputType()
	return roblox.Enum.UserInputType.Keyboard
end
function UserInputService:IsKeyDown()
	return false
end
function UserInputService:GetGamepadConnected()
	return false
end

local playerGui = roblox.Instance.new("Folder")
playerGui.Name = "PlayerGui"
local LocalPlayer = {
	UserId = 1,
	Name = "SimPlayer",
	DisplayName = "SimPlayer",
	PlayerGui = playerGui,
	CharacterAdded = Signal(),
}
function LocalPlayer:WaitForChild(name)
	if name == "PlayerGui" then
		return playerGui
	end
	return nil
end
function LocalPlayer:FindFirstChild(name)
	return LocalPlayer:WaitForChild(name)
end
function LocalPlayer:GetAttribute()
	return nil
end
function LocalPlayer:SetAttribute() end
function LocalPlayer:GetAttributeChangedSignal()
	return Signal()
end
function LocalPlayer:GetPropertyChangedSignal()
	return Signal()
end
Env.PlayerGui = playerGui

local Players = { LocalPlayer = LocalPlayer, PlayerAdded = Signal(), PlayerRemoving = Signal() }
function Players:GetPlayers()
	return { LocalPlayer }
end
function Players:GetPlayerByUserId()
	return LocalPlayer
end
function Players:GetUserThumbnailAsync()
	return "rbxasset://textures/ui/GuiImagePlaceholder.png", true
end

local TweenService = {}
function TweenService:Create(inst, _info, props)
	local tw = { Completed = Signal() }
	function tw:Play()
		for k, v in props do
			pcall(function()
				inst[k] = v
			end)
		end
		tw.Completed:Fire(roblox.Enum.PlaybackState.Completed)
	end
	function tw:Cancel() end
	function tw:Pause() end
	return tw
end

local GuiService = { TopbarInset = roblox.Rect.new(0, 0, 1280, 58) }
function GuiService:GetPropertyChangedSignal()
	return Signal()
end

local Debris = {}
function Debris:AddItem() end

local SoundService = roblox.Instance.new("Folder")
SoundService.Name = "SoundService"

local services

---------------------------------------------------------------------------
-- Module tree mirroring default.project.json
---------------------------------------------------------------------------
local ROOT = "."
local nodeMeta = {}
local nodes = {}

-- fs calls yield, and metamethods can't, so index the source tree once up front
local FILES, DIRS = {}, {}
local function scan(dir)
	DIRS[dir] = true
	for _, name in fs.readDir(dir) do
		local p = dir .. "/" .. name
		if fs.isDir(p) then
			scan(p)
		else
			FILES[p] = true
		end
	end
end
scan(ROOT .. "/src")
-- Whether a path is a source file (from the scan above).
local function isFile(p)
	return FILES[p] == true
end
-- Whether a path is a folder.
local function isDir(p)
	return DIRS[p] == true
end

-- The fake Instance for a path in the module tree (one per path, created on demand).
local function node(path, name)
	if nodes[path] then
		return nodes[path]
	end
	local n = setmetatable({ __path = path, Name = name }, nodeMeta)
	nodes[path] = n
	return n
end

-- The folder a path is in.
local function parentPath(path)
	return string.match(path, "^(.*)/[^/]+$")
end

-- Path of a child module (a .luau/.lua file or a folder) in `dir`, or nil.
local function childPath(dir, name)
	for _, ext in { ".luau", ".lua" } do
		if isFile(dir .. "/" .. name .. ext) then
			return dir .. "/" .. name
		end
	end
	if isDir(dir .. "/" .. name) then
		return dir .. "/" .. name
	end
	return nil
end

nodeMeta.__index = function(self, key)
	local path = rawget(self, "__path")
	if key == "Parent" then
		local pp = parentPath(path)
		if not pp then
			return nil
		end
		return node(pp, string.match(pp, "([^/]+)$"))
	end
	if key == "WaitForChild" or key == "FindFirstChild" then
		return function(_, name)
			local dir = if isDir(path) then path else parentPath(path) .. "/" .. rawget(self, "Name")
			local cp = childPath(dir, name)
			if not cp then
				if key == "WaitForChild" then
					error("sim: " .. path .. " has no child " .. name)
				end
				return nil
			end
			return node(cp, name)
		end
	end
	if key == "IsA" then
		return function(_, cls)
			return cls == "ModuleScript" or cls == "Instance"
		end
	end
	local dir = path
	if not isDir(dir) then
		-- a module file: children live in a folder with the same name (not used here)
		return nil
	end
	local cp = childPath(dir, key)
	if cp then
		return node(cp, key)
	end
	return nil
end

local ReplicatedStorage = {}
local carMeshes = nil
local worldMeshes = nil
function ReplicatedStorage:WaitForChild(name)
	if name == "Shared" then
		return node(ROOT .. "/src/shared", "Shared")
	end
	if name == "CarMeshes" then
		return carMeshes
	end
	if name == "WorldMeshes" then
		return worldMeshes
	end
	local f = roblox.Instance.new("Folder")
	f.Name = name
	return f
end
ReplicatedStorage.FindFirstChild = ReplicatedStorage.WaitForChild
-- pretend the Blender world meshes are imported: a MeshPart per WorldData object
function Env.FakeWorldMeshes()
	local WorldData = Env.Require("src/shared/WorldData")
	local f = roblox.Instance.new("Folder")
	f.Name = "WorldMeshes"
	local n = 0
	for _, d in WorldData.Designs do
		for _, e in d.Parts do
			local p = roblox.Instance.new("MeshPart")
			p.Name = e[1]
			p.Size = e[4]
			p.Parent = f
			n += 1
		end
	end
	worldMeshes = f
	return f, n
end

-- load the real car meshes (assets/CarMeshes.rbxmx) into ReplicatedStorage.CarMeshes
function Env.LoadCarMeshes()
	local list = roblox.deserializeModel(fs.readFile(ROOT .. "/assets/CarMeshes.rbxmx"))
	carMeshes = list[1]
	return carMeshes
end

services = {
	RunService = RunService,
	UserInputService = UserInputService,
	Players = Players,
	TweenService = TweenService,
	GuiService = GuiService,
	Debris = Debris,
	SoundService = SoundService,
	ReplicatedStorage = ReplicatedStorage,
	Lighting = Lighting,
	Workspace = Workspace,
	ContentProvider = { PreloadAsync = function() end },
	TextChatService = {},
	-- no DataStores outside Roblox: the server falls back to offline profiles
	DataStoreService = {
		GetDataStore = function()
			error("DataStores are not available in the simulator")
		end,
		GetOrderedDataStore = function()
			error("DataStores are not available in the simulator")
		end,
	},
	MarketplaceService = {
		UserOwnsGamePassAsync = function()
			return false
		end,
		PromptGamePassPurchase = function() end,
		PromptProductPurchase = function() end,
		PromptGamePassPurchaseFinished = Signal(),
		PromptProductPurchaseFinished = Signal(),
	},
	StarterGui = { SetCoreGuiEnabled = function() end, SetCore = function() end },
	HttpService = {
		GenerateGUID = function()
			return tostring(math.random(1, 1e9))
		end,
	},
	-- no cross-server services outside Roblox: ranked falls back to the local lobby
	MemoryStoreService = {
		GetSortedMap = function()
			error("MemoryStore is not available in the simulator")
		end,
	},
	TeleportService = {
		TeleportInitFailed = Signal(),
		ReserveServer = function()
			error("Teleports are not available in the simulator")
		end,
		TeleportAsync = function()
			error("Teleports are not available in the simulator")
		end,
	},
}

-- game.* properties a check can change (e.g. pretend to be a reserved match server)
Env.GameProps = { JobId = "sim-job", PlaceId = 0, PrivateServerId = "", PrivateServerOwnerId = 0 }

Env.Services = services

local gameProxy = setmetatable({}, {
	__index = function(_, key)
		if key == "BindToClose" then
			return function() end
		elseif Env.GameProps[key] ~= nil then
			return Env.GameProps[key]
		end
		if key == "GetService" then
			return function(_, name)
				local s = services[name]
				if s == nil then
					error("sim: no mock for service " .. tostring(name))
				end
				return s
			end
		end
		if services[key] then
			return services[key]
		end
		return nil
	end,
})

---------------------------------------------------------------------------
-- Loader
---------------------------------------------------------------------------
local cache = {}
local baseEnv

local instSignals = setmetatable({}, { __mode = "k" })

-- workspace:BulkMoveTo without the engine: just sets each CFrame.
local function bulkMoveTo(parts, cfs)
	for i, p in parts do
		p.CFrame = cfs[i]
	end
end

-- Runs a module file once with its own `script` and returns what it returns (cached).
local function loadModule(n)
	local path = rawget(n, "__path")
	if cache[path] ~= nil then
		return cache[path]
	end
	local file = if isFile(path .. ".luau") then path .. ".luau" else path .. "/init.luau"
	local src = fs.readFile(file)
	-- engine-only calls on workspace are routed to harness functions
	src = string.gsub(src, "workspace:BulkMoveTo%(", "__BulkMoveTo(")
	src = string.gsub(src, "workspace:GetServerTimeNow%(%)", "__ServerTime()")
	src = string.gsub(src, "workspace%.CurrentCamera", "__Camera()")
	-- instance events (MouseEnter, Activated, Changed...) don't exist in Lune: route every
	-- `x.Event:Connect/Once/Wait` and property/attribute signals through harness signals
	for _, m in { "Connect", "Once", "Wait" } do
		src = string.gsub(src, "([%w_%.]+)%.(%u[%w_]*):" .. m .. "%(", '__Ev(%1, "%2"):' .. m .. "(")
	end
	src = string.gsub(src, "([%w_%.]+):GetPropertyChangedSignal%(", "__PropSig(%1, ")
	src = string.gsub(src, "([%w_%.]+):PivotTo%(", "__PivotTo(%1, ")
	src = string.gsub(src, "([%w_%.]+):Emit%(", "__Emit(%1, ")
	src = string.gsub(src, "([%w_%.]+):GetPivot%(%)", "__GetPivot(%1)")
	src = string.gsub(src, "([%w_%.]+):GetBoundingBox%(%)", "__GetBoundingBox(%1)")
	src = string.gsub(src, "([%w_%.]+):GetAttributeChangedSignal%(", "__PropSig(%1, ")
	-- layout-only properties Lune can't compute
	src = string.gsub(src, "([%w_%.]+)%.AbsoluteSize", "__AbsSize(%1)")
	src = string.gsub(src, "([%w_%.]+)%.AbsolutePosition", "__AbsPos(%1)")
	-- Lune replaces the environment's metatable when injecting its globals, so copy
	local env = { script = n }
	for k, v in baseEnv do
		env[k] = v
	end
	-- test hooks: globals a check wants to replace (e.g. a fake os.clock)
	for k, v in Env.Overrides do
		env[k] = v
	end
	local fn = luau.load(src, { debugName = file, environment = env, injectGlobals = true })
	local result = fn()
	if Env.Patches[path] then
		Env.Patches[path](result)
	end
	cache[path] = result
	return result
end

-- the camera is a plain table: Lune can't compute ViewportSize
local camera = {
	CFrame = roblox.CFrame.new(0, 50, 0),
	FieldOfView = 70,
	ViewportSize = roblox.Vector2.new(1280, 720),
	CameraType = roblox.Enum.CameraType.Custom,
	ClassName = "Camera",
}
function camera:GetPropertyChangedSignal()
	return Signal()
end
function camera:IsA(c)
	return c == "Camera"
end

baseEnv = {
	game = gameProxy,
	workspace = Workspace,
	-- BindableEvents need a working .Event / :Fire, which Lune instances don't have
	Instance = {
		new = function(cls, parent)
			if cls == "BindableEvent" then
				local be = { Event = Signal(), Name = "BindableEvent" }
				function be:Fire(...)
					be.Event:Fire(...)
				end
				function be:Destroy() end
				return be
			end
			local inst = roblox.Instance.new(cls)
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
	},
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Rect = roblox.Rect,
	Enum = roblox.Enum,
	BrickColor = roblox.BrickColor,
	Font = roblox.Font,
	PhysicalProperties = roblox.PhysicalProperties,
	Ray = roblox.Ray,
	TweenInfo = {
		new = function(...)
			return { ... }
		end,
	},
	RaycastParams = {
		new = function()
			return {}
		end,
	},
	Random = Random,
	task = task,
	warn = function(...)
		print("[warn]", ...)
	end,
	require = function(m)
		if type(m) == "table" and rawget(m, "__path") then
			return loadModule(m)
		end
		error("sim: require of non-module " .. tostring(m))
	end,
	__BulkMoveTo = bulkMoveTo,
	__ServerTime = function()
		return serverTime
	end,
	__Camera = function()
		return camera
	end,
	__Ev = function(obj, name)
		if type(obj) == "table" then
			local v = obj[name]
			if v == nil then
				v = Signal()
				rawset(obj, name, v)
			end
			return v
		end
		local per = instSignals[obj]
		if not per then
			per = {}
			instSignals[obj] = per
		end
		per[name] = per[name] or Signal()
		return per[name]
	end,
	__GetPivot = function(model)
		if model:IsA("BasePart") then
			return model.CFrame
		end
		local pp = model.PrimaryPart
		if pp then
			return pp.CFrame
		end
		local wp = model:GetAttribute("__pivot")
		if wp then
			return wp
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				return roblox.CFrame.new(d.CFrame.Position)
			end
		end
		return roblox.CFrame.new()
	end,
	__GetBoundingBox = function(model)
		local mn, mx = nil, nil
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local p, h = d.CFrame.Position, d.Size / 2
				local a, b = p - h, p + h
				mn = if mn then roblox.Vector3.new(math.min(mn.X, a.X), math.min(mn.Y, a.Y), math.min(mn.Z, a.Z)) else a
				mx = if mx then roblox.Vector3.new(math.max(mx.X, b.X), math.max(mx.Y, b.Y), math.max(mx.Z, b.Z)) else b
			end
		end
		if not mn then
			return roblox.CFrame.new(), roblox.Vector3.zero
		end
		return roblox.CFrame.new((mn + mx) / 2), mx - mn
	end,
	__Emit = function(pe, n)
		assert(pe and pe.ClassName == "ParticleEmitter", "Emit on a non-emitter")
		assert(type(n) == "number", "Emit needs a count")
	end,
	__PropSig = function(obj, _prop)
		if type(obj) == "table" and obj.GetPropertyChangedSignal then
			return obj:GetPropertyChangedSignal(_prop)
		end
		return Signal()
	end,
	__AbsSize = function(inst)
		local ok, v = pcall(function()
			return inst.AbsoluteSize
		end)
		return if ok and v then v else roblox.Vector2.new(1280, 720)
	end,
	__AbsPos = function(inst)
		local ok, v = pcall(function()
			return inst.AbsolutePosition
		end)
		return if ok and v then v else roblox.Vector2.new(0, 0)
	end,
}

-- Fake server: remotes are local mocks; Env.OnInvoke(name, ...) answers RemoteFunctions
Env.Server = {}
Env.Remotes = {}
-- Answers a RemoteFunction call with the handler in Env.Server, if a check set one.
function Env.OnInvoke(name, ...)
	local h = Env.Server[name]
	if h then
		return h(...)
	end
	return nil
end
Env.Patches[ROOT .. "/src/shared/Net"] = function(Net)
	local function remote(name)
		local r = Env.Remotes[name]
		if not r then
			r = { Name = name, OnClientEvent = Signal(), OnServerEvent = Signal() }
			function r:FireServer() end
			function r:FireClient() end
			function r:FireAllClients() end
			function r:InvokeServer(...)
				return Env.OnInvoke(name, ...)
			end
			Env.Remotes[name] = r
		end
		return r
	end
	Net.Function = remote
	Net.Event = remote
	Net.UEvent = remote
	Net.GetFolder = function()
		return nil
	end
end

baseEnv.__PivotTo = function(model, cf)
	if model:IsA("BasePart") then
		model.CFrame = cf
		return
	end
	local from = baseEnv.__GetPivot(model)
	local delta = cf * from:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	if not model.PrimaryPart then
		model:SetAttribute("__pivot", cf)
	end
end

Env.Overrides = {}

-- Loads a module by its path from the repo root, e.g. Env.Require("src/shared/Track").
function Env.Require(relPath)
	local path = ROOT .. "/" .. relPath
	return loadModule(node(path, string.match(path, "([^/]+)$")))
end

-- Sets what workspace:GetServerTimeNow() returns.
function Env.SetServerTime(t)
	serverTime = t
end

Env.Camera = camera
Env.Roblox = roblox
return Env
