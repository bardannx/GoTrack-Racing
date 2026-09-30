--!nocheck
-- Builds the circuit intro screen for every circuit outside Studio (catches runtime errors
-- such as bad property names), including the reveal/flyover shots.
--   lune run tools/sim/ui.luau [id ...]
local process = require("@lune/process")
local task = require("@lune/task")
local fs = require("@lune/fs")
local Env = require("./env")
local Dump = require("./dumpui")

local Circuits = Env.Require("src/shared/Circuits")
local CircuitBuilder = Env.Require("src/client/CircuitBuilder")
local Intro = Env.Require("src/client/UI/CircuitIntro")
local State = Env.Require("src/client/State")
State.Profile = State.Profile or { bests = { lakeside = 83456 }, medals = { lakeside = 3 }, car = {} }

local ids = {}
local dump = false
for _, a in process.args do
	if a == "--dump" then
		dump = true
	else
		table.insert(ids, a)
	end
end
if dump then
	fs.writeDir("tools/sim/out")
end
if #ids == 0 then
	for _, c in Circuits.List do
		table.insert(ids, c.Id)
	end
end
local fails = 0
for i, id in ids do
	local ok, err = pcall(function()
		Intro.Begin(id, { Mode = if i % 3 == 0 then "tt" elseif i % 2 == 0 then "ranked" else "quick", Laps = 2, Slot = 4, Racers = 10 })
		for _ = 1, 30 do
			Env.RunService.RenderStepped:Fire(1 / 20)
		end
		local world
		if dump then
			-- let the map draw itself and the numbers count up, halfway through the build
			task.wait(1.8)
			Env.RunService.RenderStepped:Fire(1 / 20)
			Intro.Progress("Raising the landmarks", 0.52)
			Dump.Save(Env.PlayerGui:FindFirstChild("GoTrackIntro"), "tools/sim/out/intro_" .. id .. ".json")
		end
		world = CircuitBuilder.Build(id, 2, Intro.Progress)
		local done = false
		Intro.Reveal(world, { Duration = 6, OnDone = function()
			done = true
		end })
		if dump then
			task.wait(0.8)
			for _ = 1, 20 do
				Env.RunService.RenderStepped:Fire(1 / 20)
				Env.RunService.Heartbeat:Fire(1 / 20)
			end
			Dump.Save(Env.PlayerGui:FindFirstChild("GoTrackIntro"), "tools/sim/out/intro_" .. id .. "_reveal.json")
		end
		-- play the whole flyover (6 s) - it must hand over by itself
		for _ = 1, 150 do
			Env.RunService.RenderStepped:Fire(1 / 20)
			Env.RunService.Heartbeat:Fire(1 / 20)
		end
		require("@lune/task").wait(0.05)
		if not done then
			error("intro never finished")
		end
		Intro.Stop()
		CircuitBuilder.Clear()
	end)
	if not ok then
		fails += 1
		print(id, "FAILED:", err)
	else
		print(id, "ok")
	end
end
if fails > 0 then
	process.exit(1)
end
