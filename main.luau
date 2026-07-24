--Connected Discord-GitHub
--don't error if the ui didn't load yet
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local weaponList = require(game.ReplicatedStorage:WaitForChild("weaponList"))
local GUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("ScreenGui")
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
function CUniformRandomStream_RandomFloat(obj, min, max)
	local float = AM * CUniformRandomStream_RandomNumber(obj)
	if float > RNMX then
		float = RNMX
	end
	return (float * (max - min)) + min
end
--default loaded attributes of weapon_ak47
local recoilRandom = CUniformRandomStream(223)
local recoilAngle = 0
local recoilAngleVariance = 70
local recoilMagnitude = 30
local recoilMagnitudeVariance = 0
--recoil recovery time
local recoveryTime = 0.8
--primary ammo
local primaryAmmo = 30
local ammoLeft = primaryAmmo
local id = "weapon_ak47"
--delay between shots
local cycleTimeReset = 0.1
local cycleTime = cycleTimeReset


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
function LoadFromObject(object, weaponId)
	recoilRandom = CUniformRandomStream(object.seed)
	recoilAngle = object.recoilAng
	recoilAngleVariance = object.recoilAngVar
	recoilMagnitude = object.recoilMagn
	recoilMagnitudeVariance = object.recoilMagnVar
	recoveryTime = object.tIdle --time to idle
	primaryAmmo = object.primAmmo
	ammoLeft = primaryAmmo
	cycleTimeReset = object.cycle
	id = weaponId
	Generate()
end

local tickrate = 1 / 64 --bad way. sure (limit shots to every 1/64 of a second)
local recoilTable = {}

local floatAngle, floatMagnitude = 0, 0

--CVars with the same name from CSGO
local weapon_recoil_variance = 0.55 --how much of the generated angle and magnitude is taken into account while generating the recoil table (for full auto weapons)
local weapon_recoil_suppression_shots = 4 --below
local weapon_recoil_suppression_factor = 0.75 --shots after suppression_shots will have this many times less magnitude
local weapon_recoil_view_punch_extra = 0.3 --extra punch to add ONLY to the camera (shots excluded)
local weapon_recoil_vel_decay = 4.5 --recoil velocity decay speed
local weapon_recoil_decay2_exp = 8 --exponential recoil decay speed
local weapon_recoil_decay2_lin = 18 --linear recoil decay speed
local weapon_recoil_scale = .5 --this is 2 in CSGO but i have no idea why it's so strong with it actually set to 2 here

function Generate()
	--start with 0
	floatAngle = 0
	floatMagnitude = 0
	for index = 0, 63 do
		local floatAngleNew = recoilAngle + CUniformRandomStream_RandomFloat(recoilRandom, -recoilAngleVariance, recoilAngleVariance) --base weapon recoil angle + generated recoil angle from seed
		local floatMagnitudeNew = recoilMagnitude + CUniformRandomStream_RandomFloat(recoilRandom, -recoilMagnitudeVariance, recoilMagnitudeVariance) --base weapon magnitude + generated recoil magnitude from seed
		if (true --[[bFullAuto, but every gun in weaponList is already full auto]] and index > 0) then
			floatAngle = math.lerp(floatAngle, floatAngleNew, weapon_recoil_variance)
			floatMagnitude = math.lerp(floatMagnitude, floatMagnitudeNew, weapon_recoil_variance)
		else
			floatAngle = floatAngleNew
			floatMagnitude = floatMagnitudeNew
		end

		if (true --[[same full auto check]] and index < weapon_recoil_suppression_shots) then
			local suppresionFactor = math.lerp(weapon_recoil_suppression_factor, 1, index / weapon_recoil_suppression_shots)
			floatMagnitude *= suppresionFactor
		end
		--save into entry
		recoilTable[index] = {
			angle = floatAngle,
			magnitude = floatMagnitude
		}
	end
end
Generate()
--accumulated time spent without performing a shoot action (to lock it into tickrate)
local accumulatedTime = 0
--current index into the recoil table
local recoilIndex = 0

local aimPunchAngle = Vector3.zero
local aimPunchAngleVel = Vector3.zero
local aimPunchAngleVis = Vector3.zero --this one is applied to the camera, the others are applied to the shooting direction

function HybridDecay(velocity, fExponential, fLinear, deltatime)
	--decrease exponential and linear decay by deltaTime
	fExponential *= deltatime
	fLinear *= deltatime

	--decay exponentially
	velocity *= math.exp(-fExponential)


	local magnitude = velocity.Magnitude
	if (magnitude > fLinear) then
		--decay linearly (if vector length is higher than the decay value)
		velocity *= (1 - fLinear / magnitude)
	else
		velocity = Vector3.zero
	end
	return velocity
end

--apply the values from the recoil table @ the current recoil index to the punch angle
function Kickback(angle, magnitude)
	local radianAngle = math.rad(angle)
	--affect velocity
	aimPunchAngleVel = (Vector3.new(0, -math.sin(radianAngle), -math.cos(radianAngle)) * magnitude) + aimPunchAngleVel

	aimPunchAngleVis = aimPunchAngle
	--affect camera punch
	aimPunchAngleVis -= Vector3.new(0, math.sin(radianAngle), math.cos(radianAngle)) * magnitude * weapon_recoil_view_punch_extra
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

RunService.Stepped:Connect(function(_, deltatime)
	accumulatedTime += deltatime
	while (accumulatedTime > tickrate) do
		--take 1 step off. if the dt made accumTime be atleast 2x higher than tickrate, this loop will run (atleast) twice in this step to not drop shots
		accumulatedTime -= tickrate
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
				Kickback(recoilTable[math.floor(recoilIndex) % 64].angle, recoilTable[math.floor(recoilIndex) % 64].magnitude)
				recoilIndex += 1
				--scaled by 0.05 to not feel extreme
				local punch = aimPunchAngle / 20
				local radianYaw, radianPitch = math.rad(YAW) - punch.Y, math.rad(PITCH) - punch.Z
				local cosYaw, sinYaw, cosPitch, sinPitch = math.cos(radianYaw), math.sin(radianYaw), math.cos(radianPitch), math.sin(radianPitch)
				local eyePosition = game.Players.LocalPlayer.Character:GetPivot().Position + Vector3.new(0, 2, 0)
				--construct forward vector (lookVector) using the current look yaw and pitch and the current shot (not camera) punch angle
				local forward = Vector3.new(cosPitch * cosYaw, sinPitch, cosPitch * sinYaw)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = {workspace.Hittable}
				--check if the new forward vector hits anything
				local result = workspace:Raycast(eyePosition, forward * 512, params)
				if result then
					--if so generate a debug part at the impact
					local part  = Instance.new("Part")
					part.Size   = Vector3.new(0.6, .6, .6)
					part.CFrame = CFrame.lookAt(result.Position, result.Position + result.Normal)
					part.Color	= Color3.new(1, 0.5 - math.min(recoilIndex, 30) / 60, 0)
					part.Transparency = 1
					part.Anchored = true
					part.Shape = Enum.PartType.Block
					part.Parent = workspace
					local decal = Instance.new("Decal")
					decal.Texture = "rbxassetid://" .. default_bulletholes[math.random(#default_bulletholes)]
					decal.Parent = part
					decal.Face = Enum.NormalId.Front

					part:AddTag("ToBeRemoved")
				end
			end
		else
			--decay the recoilIndex since the player isn't shooting
			local rate = math.log(primaryAmmo) / recoveryTime
			recoilIndex = math.max(recoilIndex * math.exp(-rate * tickrate), 0) --i'm pretty sure this isn't the actual decay but it seems fine enough
		end
		--debug info
		GUI.RecoilIndex.Text = string.format("Recoil index: %.2f (R to reset)", recoilIndex)
		GUI.Ammo.Text = string.format("Ammo: %d/%d, weapon: %s", ammoLeft, primaryAmmo, id)
		ViewPunchDecay()
	end
end)

local locked = true
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	--lock/unlock mouse (the actual unlock is done in RenderStepped below)
	if input.KeyCode == Enum.KeyCode.E then
		locked = not locked
	end
	--clear all bulletholes and other debug parts, reset ammo and recoilIndex
	if input.KeyCode == Enum.KeyCode.R then
		recoilIndex = 0
		ammoLeft = primaryAmmo
		for i, v in pairs(CollectionService:GetTagged("ToBeRemoved")) do
			v:Destroy()
		end
	end
	--allow typing into the textbox without having to unlock the mouse and clicking it manually
	if input.KeyCode == Enum.KeyCode.P then
		GUI.Input:CaptureFocus()
	end
end)
GUI:WaitForChild("Input").FocusLost:Connect(function()
	local oldText = GUI.Input.Text
	--try to find the weapon by text
	--example: weapon_ak47, weapon_famas
	local weapon = weaponList[oldText]
	if weapon then
		LoadFromObject(weapon, oldText)
	else
		GUI.Input.PlaceholderText = "(load failed as no such weapon was found)"
	end
	GUI.Input.Text = ""
end)
RunService.RenderStepped:Connect(function(deltatime)
	local character = game.Players.LocalPlayer.Character
	if not character then return end
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
	local radianYaw, radianPitch = math.rad(YAW) - math.rad(punch.Y), math.rad(PITCH) - math.rad(punch.Z)
	local cosYaw, sinYaw, cosPitch, sinPitch = math.cos(radianYaw), math.sin(radianYaw), math.cos(radianPitch), math.sin(radianPitch)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	local eyePosition = character:GetPivot().Position + Vector3.new(0, 2, 0)
	--construct another forward vector
	local forward = Vector3.new(cosPitch * cosYaw, sinPitch, cosPitch * sinYaw)
	--i generally find lookAt to be more stable than any other kind of way i could do this and it's a pretty simple method too
	workspace.CurrentCamera.CFrame = CFrame.lookAt(
		eyePosition, eyePosition + forward
	)
end)
