--!nonstrict
-- Remote names shared by client and server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Functions = {
	"GetProfile",
	"BuyItem",
	"Equip",
	"SetNumber",
	"ClaimDaily",
	"SaveSettings",
	"GetLobbies",
	"QuickRace",
	"RankedQueue",
	"JoinLobby",
	"LeaveLobby",
	"StartNow",
	"TTStart",
	"TTSubmitLap",
	"GetLeaderboard",
	"GetGhost",
	"VoteMap",
	"ClaimChallenge",
	"SetFlag",
}

Net.Events = {
	"ProfileUpdated",
	"Notify",
	"LobbyUpdate",
	"RaceStart",
	"RaceGate",
	"RaceStandings",
	"RaceResults",
	"RaceLeave",
	"RaceReset",
}

Net.Unreliable = {
	"CarState",
	"CarStates",
	"Bump",
}

local folder: Folder? = nil

function Net.GetFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
		if not f then
			local nf = Instance.new("Folder")
			nf.Name = "Remotes"
			for _, name in Net.Functions do
				local rf = Instance.new("RemoteFunction")
				rf.Name = name
				rf.Parent = nf
			end
			for _, name in Net.Events do
				local re = Instance.new("RemoteEvent")
				re.Name = name
				re.Parent = nf
			end
			for _, name in Net.Unreliable do
				local ure = Instance.new("UnreliableRemoteEvent")
				ure.Name = name
				ure.Parent = nf
			end
			nf.Parent = ReplicatedStorage
			f = nf
		end
		folder = f
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder :: any
end

function Net.Function(name: string): RemoteFunction
	return Net.GetFolder():WaitForChild(name) :: RemoteFunction
end

function Net.Event(name: string): RemoteEvent
	return Net.GetFolder():WaitForChild(name) :: RemoteEvent
end

function Net.UEvent(name: string): UnreliableRemoteEvent
	return Net.GetFolder():WaitForChild(name) :: any
end

-- Car state packing (29 bytes):
--  t f32 (seconds since the lights went out) | x,y,z f32 | yaw,pitch,roll i16 |
--  vx,vy,vz i16 (x20) | flags u8 (bit0 front wing off, bit1 rear wing off, bit2 smoking,
--  bit3 ghost / no contact, bit4 braking, bit5 active-aero flap open)
Net.StateSize = 29
Net.Flags = { FrontWing = 1, RearWing = 2, Smoke = 4, Ghost = 8, Brake = 16, Aero = 32 }
local ANG = 32767 / math.pi
local VEL = 20

local function i16(x: number): number
	return math.clamp(math.floor(x + 0.5), -32767, 32767)
end

function Net.WriteState(b: buffer, offset: number, t: number, x: number, y: number, z: number, yaw: number, pitch: number, roll: number, vx: number, vy: number, vz: number, flags: number)
	buffer.writef32(b, offset, t)
	buffer.writef32(b, offset + 4, x)
	buffer.writef32(b, offset + 8, y)
	buffer.writef32(b, offset + 12, z)
	buffer.writei16(b, offset + 16, i16(yaw * ANG))
	buffer.writei16(b, offset + 18, i16(pitch * ANG))
	buffer.writei16(b, offset + 20, i16(roll * ANG))
	buffer.writei16(b, offset + 22, i16(vx * VEL))
	buffer.writei16(b, offset + 24, i16(vy * VEL))
	buffer.writei16(b, offset + 26, i16(vz * VEL))
	buffer.writeu8(b, offset + 28, math.clamp(flags or 0, 0, 255))
end

-- returns t, x, y, z, yaw, pitch, roll, vx, vy, vz, flags
function Net.ReadState(b: buffer, offset: number)
	return buffer.readf32(b, offset),
		buffer.readf32(b, offset + 4),
		buffer.readf32(b, offset + 8),
		buffer.readf32(b, offset + 12),
		buffer.readi16(b, offset + 16) / ANG,
		buffer.readi16(b, offset + 18) / ANG,
		buffer.readi16(b, offset + 20) / ANG,
		buffer.readi16(b, offset + 22) / VEL,
		buffer.readi16(b, offset + 24) / VEL,
		buffer.readi16(b, offset + 26) / VEL,
		buffer.readu8(b, offset + 28)
end

return Net
