--!nonstrict
-- Circuit geometry. Turns a circuit's handful of control points (Circuits.luau) into an
-- evenly sampled centre line with tangents, curvature, an ideal speed profile, a racing
-- line, timing gates, grid slots and a minimap outline.
--
-- This file is pure maths with no Roblox APIs on purpose: the server validates laps with
-- it, the client builds the circuit from it, and the offline test harness runs it as is.

local Circuits = require(script.Parent.Circuits)

local Track = {}

Track.DS = 8 -- studs between samples
Track.Unit = 50 -- control point units -> studs
Track.GateCount = 24
Track.SectorGates = { 8, 16 } -- gate indexes that end sector 1 and 2

-- Tuning for the ideal speed profile (used by the computer drivers, lap counts and medals)
Track.Profile = {
	TopSpeed = 235,
	LateralAccel = 240,
	Accel = 80,
	Brake = 150,
}
Track.RaceTargetSeconds = 180
Track.RaceLaps = 2 -- laps on normal circuits (Quick / Ranked)
Track.ShortLaps = 3 -- laps on short circuits (ideal lap under ShortLapSeconds)
Track.ShortLapSeconds = 32

-- A circuit sampled every DS studs. Arrays are indexed 1..N along the lap.
--   X, Y, Z     centre line position       TX, TY, TZ  unit tangent (direction of travel)
--   RX, RZ      horizontal unit "right"    K           signed curvature (+ = turning right)
--   V           ideal speed (studs/s)      S           distance from the start line
--   RL          racing-line offset         Over        true where the road passes over itself
--   Gates       sample index of each timing gate (gate 1 is the start/finish line)
export type Sampled = {
	Id: string,
	Def: any,
	N: number,
	Length: number,
	Width: number,
	X: { number },
	Y: { number },
	Z: { number },
	TX: { number },
	TY: { number },
	TZ: { number },
	RX: { number },
	RZ: { number },
	K: { number },
	V: { number },
	S: { number },
	RL: { number },
	Over: { boolean },
	Gates: { number },
	IdealLap: number,
	Laps: number,
	Bounds: { number },
	Minimap: { { number } },
}

-- Control points are written "x,z[,height]; x,z; ..." in Track.Unit units.
local function parsePoints(str: string): { { number } }
	local pts = {}
	for chunk in string.gmatch(str, "[^;]+") do
		local nums = {}
		for n in string.gmatch(chunk, "-?[%d%.]+") do
			table.insert(nums, tonumber(n))
		end
		if #nums >= 2 then
			table.insert(pts, { nums[1] * Track.Unit, nums[3] or 0, nums[2] * Track.Unit })
		end
	end
	return pts
end
Track.ParsePoints = parsePoints

-- Centripetal Catmull-Rom (alpha = 0.5): passes through every control point without the
-- loops and cusps a uniform spline makes on tight corners.
local function catmull(p0, p1, p2, p3, t)
	local function d(a, b)
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		return math.max(math.sqrt(math.sqrt(dx * dx + dy * dy + dz * dz)), 1e-4)
	end
	local t0 = 0
	local t1 = t0 + d(p0, p1)
	local t2 = t1 + d(p1, p2)
	local t3 = t2 + d(p2, p3)
	local tt = t1 + (t2 - t1) * t
	local out = {}
	for k = 1, 3 do
		local a1 = (t1 - tt) / (t1 - t0) * p0[k] + (tt - t0) / (t1 - t0) * p1[k]
		local a2 = (t2 - tt) / (t2 - t1) * p1[k] + (tt - t1) / (t2 - t1) * p2[k]
		local a3 = (t3 - tt) / (t3 - t2) * p2[k] + (tt - t2) / (t3 - t2) * p3[k]
		local b1 = (t2 - tt) / (t2 - t0) * a1 + (tt - t0) / (t2 - t0) * a2
		local b2 = (t3 - tt) / (t3 - t1) * a2 + (tt - t1) / (t3 - t1) * a3
		out[k] = (t2 - tt) / (t2 - t1) * b1 + (tt - t1) / (t2 - t1) * b2
	end
	return out
end

-- Box-blurs a looped array in place (the end wraps round to the start).
local function smoothArray(arr: { number }, n: number, radius: number, passes: number)
	for _ = 1, passes do
		local copy = table.clone(arr)
		for i = 1, n do
			local sum, cnt = 0, 0
			for o = -radius, radius do
				local j = ((i - 1 + o) % n) + 1
				sum += copy[j]
				cnt += 1
			end
			arr[i] = sum / cnt
		end
	end
end

local cache: { [string]: Sampled } = {}

-- Samples a circuit definition. Callers normally want Track.Get, which caches the result.
function Track.Build(def): Sampled
	local ctrl = parsePoints(def.Points)
	local m = #ctrl
	-- dense sampling of the spline
	local dense = {}
	for i = 1, m do
		local p0 = ctrl[((i - 2) % m) + 1]
		local p1 = ctrl[i]
		local p2 = ctrl[(i % m) + 1]
		local p3 = ctrl[((i + 1) % m) + 1]
		local steps = 40
		for s = 0, steps - 1 do
			table.insert(dense, catmull(p0, p1, p2, p3, s / steps))
		end
	end
	-- cumulative length (horizontal + vertical)
	local nd = #dense
	local cum = { 0 }
	for i = 2, nd + 1 do
		local a = dense[i - 1]
		local b = dense[((i - 1) % nd) + 1]
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	local total = cum[nd + 1]
	local n = math.floor(total / Track.DS)
	local ds = total / n
	local X, Y, Z = table.create(n), table.create(n), table.create(n)
	local j = 1
	for i = 1, n do
		local target = (i - 1) * ds
		while cum[j + 1] < target do
			j += 1
		end
		local a = dense[j]
		local b = dense[(j % nd) + 1]
		local seg = cum[j + 1] - cum[j]
		local t = if seg > 0 then (target - cum[j]) / seg else 0
		X[i] = a[1] + (b[1] - a[1]) * t
		Y[i] = a[2] + (b[2] - a[2]) * t
		Z[i] = a[3] + (b[3] - a[3]) * t
	end
	smoothArray(Y, n, 10, 3)

	local TX, TY, TZ, RX, RZ, K = {}, {}, {}, {}, {}, {}
	for i = 1, n do
		local ip = ((i - 2) % n) + 1
		local inx = (i % n) + 1
		local dx, dy, dz = X[inx] - X[ip], Y[inx] - Y[ip], Z[inx] - Z[ip]
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		TX[i], TY[i], TZ[i] = dx / len, dy / len, dz / len
		local hl = math.sqrt(dx * dx + dz * dz)
		RX[i], RZ[i] = -dz / hl, dx / hl
	end
	-- signed horizontal curvature (positive = turning right)
	for i = 1, n do
		local ip = ((i - 3) % n) + 1
		local inx = ((i + 1) % n) + 1
		local ax, az = TX[ip], TZ[ip]
		local bx, bz = TX[inx], TZ[inx]
		local la, lb = math.sqrt(ax * ax + az * az), math.sqrt(bx * bx + bz * bz)
		ax, az, bx, bz = ax / la, az / la, bx / lb, bz / lb
		local cross = ax * bz - az * bx
		local dot = math.clamp(ax * bx + az * bz, -1, 1)
		local ang = math.acos(dot)
		K[i] = (if cross >= 0 then 1 else -1) * ang / (4 * ds)
	end
	smoothArray(K, n, 2, 1)

	-- Ideal speed profile: the corner speed limit from curvature, then a few backward
	-- (braking) and forward (acceleration) passes so the speed changes realistically.
	local P = Track.Profile
	local V = {}
	for i = 1, n do
		local k = math.abs(K[i])
		V[i] = if k > 1e-6 then math.min(P.TopSpeed, math.sqrt(P.LateralAccel / k)) else P.TopSpeed
	end
	for _ = 1, 3 do
		for i = n, 1, -1 do -- braking (backwards)
			local nx = (i % n) + 1
			V[i] = math.min(V[i], math.sqrt(V[nx] * V[nx] + 2 * P.Brake * ds))
		end
		for i = 1, n do -- acceleration (forwards)
			local pv = V[((i - 2) % n) + 1]
			local ratio = pv / P.TopSpeed
			local acc = P.Accel * (1 - ratio * ratio * 0.8)
			V[i] = math.min(V[i], math.sqrt(pv * pv + 2 * acc * ds))
		end
	end
	local lap = 0
	local S = {}
	for i = 1, n do
		S[i] = (i - 1) * ds
		lap += ds / V[i]
	end

	-- overpass detection (road above another piece of road)
	local grid = {}
	local cell = 60
	for i = 1, n do
		local key = math.floor(X[i] / cell) .. ":" .. math.floor(Z[i] / cell)
		grid[key] = grid[key] or {}
		table.insert(grid[key], i)
	end
	local Over = {}
	local width = def.Width or 40 -- ~7 car widths, like a real F1 track
	for i = 1, n do
		Over[i] = false
		local cx, cz = math.floor(X[i] / cell), math.floor(Z[i] / cell)
		for gx = cx - 2, cx + 2 do
			for gz = cz - 2, cz + 2 do
				local list = grid[gx .. ":" .. gz]
				if list then
					for _, o in list do
						local di = math.abs(o - i)
						di = math.min(di, n - di)
						if di > 40 then
							local dx, dz = X[o] - X[i], Z[o] - Z[i]
							if dx * dx + dz * dz < (width + 40) ^ 2 and Y[i] > Y[o] + 8 then
								Over[i] = true
							end
						end
					end
				end
			end
		end
	end

	-- timing gates, evenly spread round the lap
	local gates = {}
	for g = 0, Track.GateCount - 1 do
		gates[g + 1] = math.floor(g * n / Track.GateCount) + 1
	end

	-- bounding box and a coarse outline for the minimap
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, n do
		minX, maxX = math.min(minX, X[i]), math.max(maxX, X[i])
		minZ, maxZ = math.min(minZ, Z[i]), math.max(maxZ, Z[i])
	end
	local mini = {}
	local step = math.max(1, math.floor(n / 90))
	for i = 1, n, step do
		table.insert(mini, { X[i], Z[i] })
	end

	-- racing line: outside -> apex (inside) -> outside, as a lateral offset per sample
	local narrow = table.clone(K)
	smoothArray(narrow, n, 5, 2)
	local wide = table.clone(K)
	smoothArray(wide, n, 16, 2)
	local RL = {}
	local half = width / 2 - 4
	for i = 1, n do
		-- positive curvature = right turn -> inside is +lateral
		local v = (2 * narrow[i] - wide[i]) * 900
		RL[i] = math.clamp(v, -1, 1) * half
	end
	smoothArray(RL, n, 4, 2)

	-- short races for everyone: 2 laps, or 3 on the shortest circuits (private races can pick more)
	local laps = if lap < Track.ShortLapSeconds then Track.ShortLaps else Track.RaceLaps
	return {
		Id = def.Id,
		Def = def,
		N = n,
		Length = total,
		Width = width,
		X = X,
		Y = Y,
		Z = Z,
		TX = TX,
		TY = TY,
		TZ = TZ,
		RX = RX,
		RZ = RZ,
		K = K,
		V = V,
		S = S,
		RL = RL,
		Over = Over,
		Gates = gates,
		IdealLap = lap,
		Laps = laps,
		Bounds = { minX, maxX, minZ, maxZ },
		Minimap = mini,
	}
end

-- The sampled circuit for a circuit id (built once, then cached).
function Track.Get(id: string): Sampled?
	if cache[id] then
		return cache[id]
	end
	local def = Circuits.ById[id]
	if not def then
		return nil
	end
	local t = Track.Build(def)
	cache[id] = t
	return t
end

-- Wraps an index into 1..n
function Track.Wrap(t: Sampled, i: number): number
	return ((i - 1) % t.N) + 1
end

-- Position at a distance `s` along the lap, shifted `lateral` studs to the right.
-- Returns x, y, z and the tangent tx, ty, tz, interpolated between samples.
function Track.PointAt(t: Sampled, s: number, lateral: number?): (number, number, number, number, number, number)
	local fi = (s % t.Length) / t.Length * t.N
	local i0 = math.floor(fi) + 1
	local i1 = Track.Wrap(t, i0 + 1)
	i0 = Track.Wrap(t, i0)
	local a = fi - math.floor(fi)
	local lat = lateral or 0
	local x = t.X[i0] + (t.X[i1] - t.X[i0]) * a + (t.RX[i0] + (t.RX[i1] - t.RX[i0]) * a) * lat
	local y = t.Y[i0] + (t.Y[i1] - t.Y[i0]) * a
	local z = t.Z[i0] + (t.Z[i1] - t.Z[i0]) * a + (t.RZ[i0] + (t.RZ[i1] - t.RZ[i0]) * a) * lat
	local tx = t.TX[i0] + (t.TX[i1] - t.TX[i0]) * a
	local ty = t.TY[i0] + (t.TY[i1] - t.TY[i0]) * a
	local tz = t.TZ[i0] + (t.TZ[i1] - t.TZ[i0]) * a
	return x, y, z, tx, ty, tz
end

-- Ideal speed at distance `s` along the lap.
function Track.SpeedAt(t: Sampled, s: number): number
	local i = Track.Wrap(t, math.floor((s % t.Length) / t.Length * t.N) + 1)
	return t.V[i]
end

-- Nearest sample to a position, plus the lateral and vertical offset from it. Pass the
-- previous result as `hint` to search only nearby (much faster every frame).
function Track.Project(t: Sampled, x: number, y: number, z: number, hint: number?): (number, number, number)
	local best, bestD = 1, math.huge
	if hint then
		for o = -90, 90 do
			local i = Track.Wrap(t, hint + o)
			local dx, dy, dz = t.X[i] - x, (t.Y[i] - y) * 2, t.Z[i] - z
			local d = dx * dx + dy * dy + dz * dz
			if d < bestD then
				best, bestD = i, d
			end
		end
	end
	if not hint or bestD > 200 * 200 then
		for i = 1, t.N, 3 do
			local dx, dy, dz = t.X[i] - x, (t.Y[i] - y) * 2, t.Z[i] - z
			local d = dx * dx + dy * dy + dz * dz
			if d < bestD then
				best, bestD = i, d
			end
		end
		for o = -3, 3 do
			local i = Track.Wrap(t, best + o)
			local dx, dy, dz = t.X[i] - x, (t.Y[i] - y) * 2, t.Z[i] - z
			local d = dx * dx + dy * dy + dz * dz
			if d < bestD then
				best, bestD = i, d
			end
		end
	end
	local lateral = (x - t.X[best]) * t.RX[best] + (z - t.Z[best]) * t.RZ[best]
	local vertical = y - t.Y[best]
	return best, lateral, vertical
end

-- Grid slot (1..10): position behind the start line, staggered left/right
function Track.GridSlot(t: Sampled, slot: number): (number, number)
	local back = 26 + (slot - 1) * 17
	local lateral = if slot % 2 == 1 then -t.Width * 0.2 else t.Width * 0.2
	return t.Length - back, lateral
end

-- Signed forward index difference a->b in the range (-n/2, n/2]
function Track.IndexDelta(t: Sampled, a: number, b: number): number
	local d = (b - a) % t.N
	if d > t.N / 2 then
		d -= t.N
	end
	return d
end

return Track
