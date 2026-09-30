--!nonstrict
-- Wheel spin that reads well on screen.
-- A real race tyre turns ~30 times a second at top speed, far faster than the screen
-- refreshes, so turning the rim by the true angle each frame strobes (spokes look frozen
-- or spin backwards). Instead the visible spin is capped just under the strobe limit and
-- a translucent blur disc fades in over the rim, while the sidewall lettering fades out.

local WheelFx = {}

local TAU = math.pi * 2
local MAX_STEP = 0.3 -- radians per frame; above ~pi/spokes the rim appears to stop/reverse
local BLUR_START = 35 -- studs/s where the blur disc starts to appear
local BLUR_FULL = 140 -- studs/s where it is fully in
local MARK_FADE = 60 -- studs/s above which the sidewall letters have faded out

-- speed: forward speed in studs/s (negative = reversing). Returns the new spin angle.
function WheelFx.Step(angle: number, speed: number, dt: number, wheels): number
	local radius = 1.2
	local first = wheels and wheels[1]
	if first and first.Radius and first.Radius > 0.3 then
		radius = first.Radius
	end
	local step = math.clamp(-speed / radius * dt, -MAX_STEP, MAX_STEP)
	angle = (angle + step) % TAU
	if wheels then
		local v = math.abs(speed)
		local blurT = math.clamp((v - BLUR_START) / (BLUR_FULL - BLUR_START), 0, 1)
		local markT = math.clamp(v / MARK_FADE, 0, 1)
		local key = math.floor(blurT * 20) * 32 + math.floor(markT * 20)
		for _, w in wheels do
			if w.FxKey == key then
				continue -- nothing visible changed since last frame
			end
			w.FxKey = key
			if w.Blur then
				w.Blur.Transparency = 1 - blurT * 0.72
			end
			if w.Marks then
				for _, m in w.Marks do
					m.Transparency = markT
				end
			end
		end
	end
	return angle
end

return WheelFx
