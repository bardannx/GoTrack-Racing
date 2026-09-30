--!nonstrict
-- Small client utilities: signals, remote calls, formatting.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local Util = {}

-- Signal ----------------------------------------------------------------------
export type Signal = {
	Connect: (Signal, (...any) -> ()) -> { Disconnect: () -> () },
	Fire: (Signal, ...any) -> (),
}

function Util.Signal(): Signal
	local listeners = {}
	local sig = {}
	function sig:Connect(fn)
		local entry = { fn = fn }
		table.insert(listeners, entry)
		return {
			Disconnect = function()
				local i = table.find(listeners, entry)
				if i then
					table.remove(listeners, i)
				end
			end,
		}
	end
	function sig:Fire(...)
		for _, l in table.clone(listeners) do
			task.spawn(l.fn, ...)
		end
	end
	return sig :: any
end

-- Remotes ---------------------------------------------------------------------
function Util.Invoke(name: string, ...: any): any
	local rf = Net.Function(name)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return rf:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn("[GoTrack] Remote failed", name, result)
		return nil
	end
	return result
end

-- Formatting --------------------------------------------------------------------
function Util.Comma(n: number): string
	local s = tostring(math.floor(n))
	local formatted, k = s, 0
	repeat
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

function Util.EnvIcon(env: string): string
	if env == "winter" then
		return "❄️"
	elseif env == "desert" then
		return "🏜️"
	end
	return "☀️"
end

function Util.EnvName(env: string): string
	if env == "winter" then
		return "Winter"
	elseif env == "desert" then
		return "Desert"
	end
	return "Summer"
end

function Util.MedalIcon(level: number): string
	if level >= 4 then
		return "💠"
	elseif level == 3 then
		return "🥇"
	elseif level == 2 then
		return "🥈"
	elseif level == 1 then
		return "🥉"
	end
	return "⬜"
end

function Util.Clear(inst: Instance, keepLayouts: boolean?)
	for _, c in inst:GetChildren() do
		if keepLayouts and (c:IsA("UIListLayout") or c:IsA("UIGridLayout") or c:IsA("UIPadding") or c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIGradient") or c:IsA("UIScale") or c:IsA("UIAspectRatioConstraint")) then
			continue
		end
		c:Destroy()
	end
end

function Util.TimeAgo(t: number): string
	local d = os.time() - t
	if d < 60 then
		return "just now"
	elseif d < 3600 then
		return math.floor(d / 60) .. "m ago"
	elseif d < 86400 then
		return math.floor(d / 3600) .. "h ago"
	end
	return math.floor(d / 86400) .. "d ago"
end

return Util
