repeat task.wait() until game.Players.LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
local IA = 16807
local IM = 2147483647
local IQ = 127773
local IR = 2836
local NTAB = 32
local NDIV = (1+(IM-1)/NTAB)
local AM = 1 / IM
local RNMX = 1.0 - 1.2E-7
function CUniformRandomStream(seed: number)
	return {
		m_idum = seed < 0 and seed or -seed,
		m_iy = 0,
		m_iv = table.create(32, 0)
	}
end
function CUniformRandomStream_RandomNumber(obj)
	local j, k = 0, 0
	if obj.m_idum <= 0 or obj.m_iy == 0 then
		if (-obj.m_idum < 1) then obj.m_idum = 1 else obj.m_idum = -obj.m_idum end
		for j = 39, 0, -1 do
			k = math.floor(obj.m_idum / IQ)
			obj.m_idum = IA * (obj.m_idum - k * IQ) - k * IR
			if (obj.m_idum < 0) then
				obj.m_idum += IM
			end
			if j < 32 then
				obj.m_iv[j] = obj.m_idum
			end
		end
		obj.m_iy = obj.m_iv[0]
	end
	k = math.floor(obj.m_idum / IQ)
	obj.m_idum = IA * (obj.m_idum - k * IQ) - k * IR
	if (obj.m_idum < 0) then
		obj.m_idum += IM
	end
	j = math.floor(obj.m_iy / NDIV)
	if j >= NTAB or j < 0 then
		j = bit32.band(j, NTAB - 1)
	end
	obj.m_iy = obj.m_iv[j]
	obj.m_iv[j] = obj.m_idum
	return obj.m_iy
end
function CUniformRandomStream_RandomFloat(obj, fMin, fMax)
	local fl = AM * CUniformRandomStream_RandomNumber(obj)
	if fl > RNMX then
		fl = RNMX
	end
	return (fl * (fMax - fMin)) + fMin
end
local recoilRandom = CUniformRandomStream(223) -- ak47
local recoilAngle = 0
local recoilAngleVariance = 70
local recoilMagnitude = 30
local recoilMagnitudeVariance = 0
local recTime = 0.8
local pAmmo = 30
local ammoLeft = pAmmo
local id = "weapon_ak47"

local cycleTimeReset = 0.1 --from item schema

function _G.LoadFromObject(obj)
	recoilRandom = CUniformRandomStream(obj[1])
	recoilAngle = obj[2]
	recoilAngleVariance = obj[3]
	recoilMagnitude = obj[4]
	recoilMagnitudeVariance = obj[5]
	recTime = obj[6]
	pAmmo = obj[7]
	ammoLeft = pAmmo
	cycleTimeReset = obj[8]
	id = obj[9]
	Gen()
end

local cycleTime = cycleTimeReset

local tickrate = 1 / 64 --bad way. sure
local recoilTable = {}

local fAngle, fMagnitude = 0, 0

local weapon_recoil_variance = 0.55 --from a CVar under the same name
local weapon_recoil_suppression_shots = 4
local weapon_recoil_suppression_factor = 0.75
local weapon_recoil_view_punch_extra = 0.3
local weapon_recoil_vel_decay = 4.5
local weapon_recoil_decay2_exp = 8
local weapon_recoil_decay2_lin = 18
local weapon_recoil_scale = .5 --this is 2 in CSGO but i have no idea why it's so strong with it actually set to 2 here

function Gen()
	fAngle = 0
	fMagnitude = 0
for i = 0, 63 do
	local fAngleNew = recoilAngle + CUniformRandomStream_RandomFloat(recoilRandom, -recoilAngleVariance, recoilAngleVariance)
	local fMagnitudeNew = recoilMagnitude + CUniformRandomStream_RandomFloat(recoilRandom, -recoilMagnitudeVariance, recoilMagnitudeVariance)
	if (true --[[bFullAuto]] and i > 0) then
		fAngle = math.lerp(fAngle, fAngleNew, weapon_recoil_variance)
		fMagnitude = math.lerp(fMagnitude, fMagnitudeNew, weapon_recoil_variance)
	else
		fAngle = fAngleNew
		fMagnitude = fMagnitudeNew
	end
	
	if (true and i < weapon_recoil_suppression_shots) then
		local fSuppresionFactor = math.lerp(weapon_recoil_suppression_factor, 1, i / weapon_recoil_suppression_shots)
		fMagnitude *= fSuppresionFactor
	end
	
	recoilTable[i] = {
		fAngle = fAngle,
		fMagnitude = fMagnitude
	}
end
end
Gen()
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local accumTime = 0
local recoilIndex = 0

local aimPunchAngle = Vector3.zero
local aimPunchAngleVel = Vector3.zero
local aimPunchAngleVis = Vector3.zero --this one is applied to the camera

function HybridDecay(v, fExp, fLin, dT)
	fExp *= dT
	fLin *= dT
	v *= math.exp(-fExp)
	
	local mag = v.Magnitude
	if (mag > fLin) then
		v *= (1 - fLin / mag)
	else
		v = Vector3.zero
	end
	return v
end


function Kickback(fAngle, fMagnitude)
	local rad = math.rad(fAngle)
	aimPunchAngleVel = (Vector3.new(0, -math.sin(rad), -math.cos(rad)) * fMagnitude) + aimPunchAngleVel
	
	aimPunchAngleVis = aimPunchAngle
	aimPunchAngleVis -= Vector3.new(0, math.sin(rad), math.cos(rad)) * fMagnitude * weapon_recoil_view_punch_extra
end

function ViewPunchDecay()
	local punchAngle = aimPunchAngle
	local punchVel = aimPunchAngleVel
	
	punchAngle = HybridDecay(punchAngle, weapon_recoil_decay2_exp, weapon_recoil_decay2_lin, tickrate)
	aimPunchAngleVis = HybridDecay(aimPunchAngleVis, weapon_recoil_decay2_exp, weapon_recoil_decay2_lin, tickrate)
	
	punchAngle += punchVel * tickrate * .5
	punchVel *= math.exp(tickrate * -weapon_recoil_vel_decay)
	punchAngle += punchVel * tickrate * .5
	
	aimPunchAngle = punchAngle
	aimPunchAngleVel = punchVel
end

function GetAimPunch()
	return aimPunchAngleVis * weapon_recoil_scale
end
local YAW, PITCH = 0, 0

local default_bulletholes = {
	"4117124202";
	"4117124881";
	"4117125609";
	"4117126706";
	"4117127411";
}

RunService.Stepped:Connect(function(t, dt)
	accumTime += dt
	while (accumTime > tickrate) do
		accumTime -= tickrate
		cycleTime -= tickrate
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			if cycleTime < 0 then
				ammoLeft -= 1
				cycleTime = cycleTimeReset
				if ammoLeft == 0 then
					cycleTime = 0.5
				end
				Kickback(recoilTable[math.floor(recoilIndex) % 64].fAngle, recoilTable[math.floor(recoilIndex) % 64].fMagnitude)
				recoilIndex+=1
				local punch = aimPunchAngle / 20
				local rY, rP = math.rad(YAW) - punch.Y, math.rad(PITCH) - punch.Z
				local cy, sy, cp, sp = math.cos(rY), math.sin(rY), math.cos(rP), math.sin(rP)
				local p1 = game.Players.LocalPlayer.Character:GetPivot().Position + Vector3.new(0, 2)
				local p2 = Vector3.new(cp * cy, sp, cp * sy)
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Include
				rp.FilterDescendantsInstances = {workspace.Hittable}
				local rc = workspace:Raycast(p1, p2 * 512, rp)
				if rc then
					local p = Instance.new("Part")
					p.Size = Vector3.new(0.6, .6, .6)
					p.CFrame = CFrame.lookAt(rc.Position, rc.Position + rc.Normal)
					p.Color	= Color3.new(1, 0.5 - math.min(recoilIndex, 30) / 60, 0)
					p.Transparency = 1
					p.Anchored = true
					p.Shape = Enum.PartType.Block
					p.Parent = workspace
					local dec = Instance.new("Decal")
					dec.Texture = "rbxassetid://" .. default_bulletholes[math.random(#default_bulletholes)]
					dec.Parent = p
					dec.Face = Enum.NormalId.Front

					p:AddTag("ToBeRemoved")
				end
			end
		else
			local k = math.log(pAmmo) / recTime
			recoilIndex = math.max(recoilIndex * math.exp(-k * tickrate), 0) --i'm pretty sure this isn't the actual decay but it seems fine enough
		end
		game.Players.LocalPlayer.PlayerGui.ScreenGui.TextLabel.Text = string.format("Recoil index: %.2f (R to reset)", recoilIndex)
		game.Players.LocalPlayer.PlayerGui.ScreenGui.tl2.Text = string.format("Ammo: %d/%d, weapon: %s", ammoLeft, pAmmo, id)
		ViewPunchDecay()
	end
end)

local locked = true
UserInputService.InputBegan:Connect(function(i, gpe)
	if gpe then return end
	if i.KeyCode == Enum.KeyCode.E then
		locked = not locked
	end
	if i.KeyCode == Enum.KeyCode.R then
		recoilIndex = 0
		ammoLeft = pAmmo
		for i, v in pairs(game:GetService("CollectionService"):GetTagged("ToBeRemoved")) do
			v:Destroy()
		end
	end
	if i.KeyCode == Enum.KeyCode.P then
		game.Players.LocalPlayer.PlayerGui.ScreenGui.TextBox:CaptureFocus()
	end
end)
local weps = require(game.ReplicatedStorage:WaitForChild("weaponList"))
game.Players.LocalPlayer.PlayerGui.ScreenGui:WaitForChild("TextBox").FocusLost:Connect(function()
	local oldText = game.Players.LocalPlayer.PlayerGui.ScreenGui.TextBox.Text
	local ent = weps[oldText]
	if ent then
		_G.LoadFromObject({
			ent.seed,
			ent.recoilAng,
			ent.recoilAngVar,
			ent.recoilMagn,
			ent.recoilMagnVar,
			ent.tIdle,
			ent.primAmmo,
			ent.cycle,
			oldText
		})
	else
		game.Players.LocalPlayer.PlayerGui.ScreenGui.TextBox.PlaceholderText = "(load failed as no such weapon was found)"
	end
	game.Players.LocalPlayer.PlayerGui.ScreenGui.TextBox.Text = ""
end)
RunService.RenderStepped:Connect(function(dt)
	if not game.Players.LocalPlayer.Character then return end
	UserInputService.MouseBehavior = locked and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	local mouseDelta = UserInputService:GetMouseDelta() / 10
	YAW += mouseDelta.X
	PITCH -= mouseDelta.Y
	YAW = YAW % 360
	if PITCH > 89 then PITCH = 89 end
	if PITCH <= -89 then PITCH = -89 end
	local punch = GetAimPunch()
	local rY, rP = math.rad(YAW) - math.rad(punch.Y), math.rad(PITCH) - math.rad(punch.Z)
	local cy, sy, cp, sp = math.cos(rY), math.sin(rY), math.cos(rP), math.sin(rP)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	local p1 = game.Players.LocalPlayer.Character:GetPivot().Position + Vector3.new(0, 2)
	local p2 = Vector3.new(cp * cy, sp, cp * sy)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(
		p1, p1 + p2
	)
end)
