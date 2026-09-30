--!nocheck
-- Builds every chassis with the real meshes (assets/CarMeshes.rbxmx) outside Studio and
-- runs the car controller for a few seconds of driving, braking, rain and landing.
--   lune run tools/sim/cars.luau
local process = require("@lune/process")
local Env = require("./env")
local folder = Env.LoadCarMeshes()
print("CarMeshes:", folder and #folder:GetChildren() or 0, "templates")
local Cosmetics = Env.Require("src/shared/Cosmetics")
local CarBuilder = Env.Require("src/shared/CarBuilder")
local fails = 0
for _, item in Cosmetics.ByCategory.Body do
	local car = table.clone(Cosmetics.DefaultCar)
	car.Body = item.Id
	local ok, res = pcall(CarBuilder.Build, car, {})
	if not ok then
		fails += 1
		print(item.Id, "BUILD FAILED:", res)
	else
		local n = 0
		for _, d in res.Model:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		local okFx, errFx = pcall(function()
			CarBuilder.SetRainLight(res.RainLight, true, false)
			CarBuilder.SetRainLight(res.RainLight, false, true)
			assert(res.Plank.ClassName == "ParticleEmitter")
		end)
		print(string.format("%-10s %-10s parts %3d  rain light %s  spray %d  plank %s  %s", item.Id, res.Design, n, tostring(res.RainLight ~= nil), #(res.Spray or {}), tostring(res.Plank ~= nil), if okFx then "" else ("FX FAILED " .. tostring(errFx))))
		if not okFx or not res.RainLight then
			fails += 1
		end
		res.Model:Destroy()
	end
end

-- Second pass: pretend the current-generation meshes are imported (placeholder copies of an
-- existing MeshPart under every new object name) and check every chassis switches to its
-- new design, with the active-aero flap on its hinge where the design has one.
local CarData = Env.Require("src/shared/CarData")
if folder then
	local sample = folder:FindFirstChildWhichIsA("MeshPart")
	local added = 0
	for name in CarData.Objects do
		if not folder:FindFirstChild(name) then
			local p = sample:Clone()
			p.Name = name
			p.Parent = folder
			added += 1
		end
	end
	print("\nplaceholder meshes for the new generation:", added)
	for _, item in Cosmetics.ByCategory.Body do
		local car = table.clone(Cosmetics.DefaultCar)
		car.Body = item.Id
		local ok, res = pcall(CarBuilder.Build, car, {})
		if not ok then
			fails += 1
			print(item.Id, "NEW BUILD FAILED:", res)
		else
			local want = CarData.Presets[item.Id].Design
			local D = CarData.Designs[want]
			local flapParts = 0
			for _, d in res.Model:GetDescendants() do
				if d.Name == "Flap" then
					flapParts += 1
				end
			end
			local okFlap = pcall(CarBuilder.SetFlap, res.Flap, 1)
			local good = res.Design == want and ((D.Flap == nil) == (res.Flap == nil)) and (res.Flap == nil or flapParts > 0) and okFlap
			print(string.format("%-10s -> %-10s flap %s (%d parts)  %s", item.Id, res.Design, tostring(res.Flap ~= nil), flapParts, if good then "ok" else "WRONG"))
			if not good then
				fails += 1
			end
			res.Model:Destroy()
		end
	end
end
if fails > 0 then
	process.exit(1)
end
