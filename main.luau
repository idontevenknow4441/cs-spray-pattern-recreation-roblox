--Connected Discord-GitHub
--don't error if the ui didn't load yet
repeat task.wait() until game.Players.LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
--random constants from ran1 for 1:1 recoil seed usage from CS
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
		--initialize generator and next numbers table
		for j = NTAB+7, 0, -1 do
			k = math.floor(obj.m_idum / IQ)
			obj.m_idum = IA * (obj.m_idum - k * IQ) - k * IR
			if (obj.m_idum < 0) then
				obj.m_idum += IM
			end
			if j < NTAB then
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
	if j >= NTAB or j < 0 then --don't overflow
		j = bit32.band(j, NTAB - 1)
	end
	--get current number and select next
	obj.m_iy = obj.m_iv[j]
	obj.m_iv[j] = obj.m_idum
	return obj.m_iy
end
--generate a random float from min to max using ([0..1) * (max - min)) + max
function CUniformRandomStream_RandomFloat(obj, fMin, fMax)
	local fl = AM * CUniformRandomStream_RandomNumber(obj)
	if fl > RNMX then
		fl = RNMX
	end
	return (fl * (fMax - fMin)) + fMin
end
--default loaded attributes of weapon_ak47
local recoilRandom = CUniformRandomStream(223)
local recoilAngle = 0
local recoilAngleVariance = 70
local recoilMagnitude = 30
local recoilMagnitudeVariance = 0
--recoil recovery time
local recTime = 0.8
--primary ammo
local pAmmo = 30
local ammoLeft = pAmmo
local id = "weapon_ak47"
--delay between shots
local cycleTimeReset = 0.1

--load above variables from an entry from weaponList.luau in order:
--[[
1: recoil seed
2: recoil angle
3: recoil angle variance
4: recoil magnitude
5: recoil magnitude variance
6: recovery time
7: primary ammo
8: cycletime
9: weapon name
]]
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

local tickrate = 1 / 64 --bad way. sure (limit shots to every 1/64 of a second)
local recoilTable = {}

local fAngle, fMagnitude = 0, 0

--CVars with the same name from CSGO
local weapon_recoil_variance = 0.55 --how much of the generated angle and magnitude is taken into account while generating the recoil table (for full auto weapons)
local weapon_recoil_suppression_shots = 4 --below
local weapon_recoil_suppression_factor = 0.75 --shots after suppression_shots will have this many times less magnitude
local weapon_recoil_view_punch_extra = 0.3 --extra punch to add ONLY to the camera (shots excluded)
local weapon_recoil_vel_decay = 4.5 --recoil velocity decay speed
local weapon_recoil_decay2_exp = 8 --exponential recoil decay speed
local weapon_recoil_decay2_lin = 18 --linear recoil decay speed
local weapon_recoil_scale = .5 --this is 2 in CSGO but i have no idea why it's so strong with it actually set to 2 here

function Gen()
	--start with 0
	fAngle = 0
	fMagnitude = 0
for i = 0, 63 do
	local fAngleNew = recoilAngle + CUniformRandomStream_RandomFloat(recoilRandom, -recoilAngleVariance, recoilAngleVariance) --base weapon recoil angle + generated recoil angle from seed
	local fMagnitudeNew = recoilMagnitude + CUniformRandomStream_RandomFloat(recoilRandom, -recoilMagnitudeVariance, recoilMagnitudeVariance) --base weapon magnitude + generated recoil magnitude from seed
	if (true --[[bFullAuto, but every gun in weaponList is already full auto]] and i > 0) then
		fAngle = math.lerp(fAngle, fAngleNew, weapon_recoil_variance)
		fMagnitude = math.lerp(fMagnitude, fMagnitudeNew, weapon_recoil_variance)
	else
		fAngle = fAngleNew
		fMagnitude = fMagnitudeNew
	end
	
	if (true --[[same full auto check]] and i < weapon_recoil_suppression_shots) then
		local fSuppresionFactor = math.lerp(weapon_recoil_suppression_factor, 1, i / weapon_recoil_suppression_shots)
		fMagnitude *= fSuppresionFactor
	end
	--save into entry
	recoilTable[i] = {
		fAngle = fAngle,
		fMagnitude = fMagnitude
	}
end
end
Gen()
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
--accumulated time spent without performing a shoot action (to lock it into tickrate)
local accumTime = 0
--current index into the recoil table
local recoilIndex = 0

local aimPunchAngle = Vector3.zero
local aimPunchAngleVel = Vector3.zero
local aimPunchAngleVis = Vector3.zero --this one is applied to the camera, the others are applied to the shooting direction

function HybridDecay(v, fExp, fLin, dT)
	--decrease exponential and linear decay by deltaTime
	fExp *= dT
	fLin *= dT

	--decay exponentially
	v *= math.exp(-fExp)

	
	local mag = v.Magnitude
	if (mag > fLin) then
		--decay linearly (if vector length is higher than the decay value)
		v *= (1 - fLin / mag)
	else
		v = Vector3.zero
	end
	return v
end

--apply the values from the recoil table @ the current recoil index to the punch angle
function Kickback(fAngle, fMagnitude)
	local rad = math.rad(fAngle)
	--affect velocity
	aimPunchAngleVel = (Vector3.new(0, -math.sin(rad), -math.cos(rad)) * fMagnitude) + aimPunchAngleVel
	
	aimPunchAngleVis = aimPunchAngle
	--affect camera punch
	aimPunchAngleVis -= Vector3.new(0, math.sin(rad), math.cos(rad)) * fMagnitude * weapon_recoil_view_punch_extra
end

function ViewPunchDecay()
	local punchAngle = aimPunchAngle
	local punchVel = aimPunchAngleVel

	--decay the aim punch and camera punch
	punchAngle = HybridDecay(punchAngle, weapon_recoil_decay2_exp, weapon_recoil_decay2_lin, tickrate)
	aimPunchAngleVis = HybridDecay(aimPunchAngleVis, weapon_recoil_decay2_exp, weapon_recoil_decay2_lin, tickrate)

	--apply the recoil velocity to the aim punch
	punchAngle += punchVel * tickrate * .5
	--decay velocity
	punchVel *= math.exp(tickrate * -weapon_recoil_vel_decay)
	--apply round 2 of velocity
	punchAngle += punchVel * tickrate * .5
	
	aimPunchAngle = punchAngle
	aimPunchAngleVel = punchVel
end

--return current camera view punch scaled with the weapon_recoil_scale CVar
function GetAimPunch()
	return aimPunchAngleVis * weapon_recoil_scale
end
--horizontal and vertical look axis since this was easier than working around the camera system
local YAW, PITCH = 0, 0

--just a list of bullethole decals to use
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
		--take 1 step off. if the dt made accumTime be atleast 2x higher than tickrate, this loop will run (atleast) twice in this step to not drop shots
		accumTime -= tickrate
		cycleTime -= tickrate
		--wants to shoot?
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			--if we can shoot: that is if we shot atleast cycleTimeReset seconds ago
			if cycleTime < 0 then
				ammoLeft -= 1
				cycleTime = cycleTimeReset
				if ammoLeft == 0 then
					--impose a delay so you can fire a full mag without stopping holding mouse and not shooting past the primary ammo at the same time
					--shooting more bullets than the ammo is allowed for showcasing what would happen with something like sv_infinite_ammo 1
					cycleTime = 0.5
				end
				--add the current recoil variables to the punch & go to the next recoil index
				Kickback(recoilTable[math.floor(recoilIndex) % 64].fAngle, recoilTable[math.floor(recoilIndex) % 64].fMagnitude)
				recoilIndex+=1
				--scaled by 0.05 to not feel extreme
				local punch = aimPunchAngle / 20
				local rY, rP = math.rad(YAW) - punch.Y, math.rad(PITCH) - punch.Z
				local cy, sy, cp, sp = math.cos(rY), math.sin(rY), math.cos(rP), math.sin(rP)
				local p1 = game.Players.LocalPlayer.Character:GetPivot().Position + Vector3.new(0, 2)
				--construct forward vector (lookVector) using the current look yaw and pitch and the current shot (not camera) punch angle
				local p2 = Vector3.new(cp * cy, sp, cp * sy)
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Include
				rp.FilterDescendantsInstances = {workspace.Hittable}
				--check if the new forward vector hits anything
				local rc = workspace:Raycast(p1, p2 * 512, rp)
				if rc then
					--if so generate a debug part at the impact
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
			--decay the recoilIndex since the player isn't shooting
			local k = math.log(pAmmo) / recTime
			recoilIndex = math.max(recoilIndex * math.exp(-k * tickrate), 0) --i'm pretty sure this isn't the actual decay but it seems fine enough
		end
		--debug info
		game.Players.LocalPlayer.PlayerGui.ScreenGui.TextLabel.Text = string.format("Recoil index: %.2f (R to reset)", recoilIndex)
		game.Players.LocalPlayer.PlayerGui.ScreenGui.tl2.Text = string.format("Ammo: %d/%d, weapon: %s", ammoLeft, pAmmo, id)
		ViewPunchDecay()
	end
end)

local locked = true
UserInputService.InputBegan:Connect(function(i, gpe)
	if gpe then return end
	--lock/unlock mouse (the actual unlock is done in RenderStepped below)
	if i.KeyCode == Enum.KeyCode.E then
		locked = not locked
	end
	--clear all bulletholes and other debug parts, reset ammo and recoilIndex
	if i.KeyCode == Enum.KeyCode.R then
		recoilIndex = 0
		ammoLeft = pAmmo
		for i, v in pairs(game:GetService("CollectionService"):GetTagged("ToBeRemoved")) do
			v:Destroy()
		end
	end
	--allow typing into the textbox without having to unlock the mouse and clicking it manually
	if i.KeyCode == Enum.KeyCode.P then
		game.Players.LocalPlayer.PlayerGui.ScreenGui.TextBox:CaptureFocus()
	end
end)
local weps = require(game.ReplicatedStorage:WaitForChild("weaponList"))
game.Players.LocalPlayer.PlayerGui.ScreenGui:WaitForChild("TextBox").FocusLost:Connect(function()
	local oldText = game.Players.LocalPlayer.PlayerGui.ScreenGui.TextBox.Text
	--try to find the weapon by text
	--example: weapon_ak47, weapon_famas
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
	--lock/unlock mouse depending on the variable mentioned above
	UserInputService.MouseBehavior = locked and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	local mouseDelta = UserInputService:GetMouseDelta() / 10
	--move the camera around based on mouse input
	YAW += mouseDelta.X
	PITCH -= mouseDelta.Y
	--...and clamp it
	YAW = YAW % 360
	if PITCH > 89 then PITCH = 89 end
	if PITCH <= -89 then PITCH = -89 end
	--get the punch that's supposed to actually affect the camera and apply it
	local punch = GetAimPunch()
	local rY, rP = math.rad(YAW) - math.rad(punch.Y), math.rad(PITCH) - math.rad(punch.Z)
	local cy, sy, cp, sp = math.cos(rY), math.sin(rY), math.cos(rP), math.sin(rP)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	local p1 = game.Players.LocalPlayer.Character:GetPivot().Position + Vector3.new(0, 2)
	--construct another forward vector
	local p2 = Vector3.new(cp * cy, sp, cp * sy)
	--i generally find lookAt to be more stable than any other kind of way i could do this and it's a pretty simple method too
	workspace.CurrentCamera.CFrame = CFrame.lookAt(
		p1, p1 + p2
	)
end)
