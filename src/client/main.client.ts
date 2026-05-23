import { Players, RunService, UserInputService, Workspace, ReplicatedStorage, CollectionService } from "@rbxts/services";
Players.LocalPlayer.WaitForChild("PlayerGui").WaitForChild("ScreenGui");
const IA = 16807;
const IM = 2147483647;
const IQ = 127773;
const IR = 2836;
const NTAB = 32;
const NDIV = 1 + ((IM - 1) / NTAB);
const AM = 1 / IM;
const RNMX = 1.0 - 1.2e-7;

interface UniformRandomStream {
	m_idum: number;
	m_iy: number;
	m_iv: number[];
}

function CUniformRandomStream(seed: number): UniformRandomStream {
	return {
		m_idum: seed < 0 ? seed : -seed,
		m_iy: 0,
		m_iv: table.create(32, 0),
	};
}

function CUniformRandomStream_RandomNumber(obj: UniformRandomStream): number {
	let j = 0, k = 0;
	if (obj.m_idum <= 0 || obj.m_iy === 0) {
		if (-obj.m_idum < 1) obj.m_idum = 1; else obj.m_idum = -obj.m_idum;
		for (j = 39; j >= 0; j--) {
			k = math.floor(obj.m_idum / IQ);
			obj.m_idum = IA * (obj.m_idum - k * IQ) - k * IR;
			if (obj.m_idum < 0) obj.m_idum += IM;
			if (j < 32) obj.m_iv[j] = obj.m_idum;
		}
		obj.m_iy = obj.m_iv[0];
	}
	k = math.floor(obj.m_idum / IQ);
	obj.m_idum = IA * (obj.m_idum - k * IQ) - k * IR;
	if (obj.m_idum < 0) obj.m_idum += IM;
	j = math.floor(obj.m_iy / NDIV);
	if (j >= NTAB || j < 0) j = bit32.band(j, NTAB - 1);
	obj.m_iy = obj.m_iv[j];
	obj.m_iv[j] = obj.m_idum;
	return obj.m_iy;
}

function CUniformRandomStream_RandomFloat(obj: UniformRandomStream, fMin: number, fMax: number): number {
	let fl = AM * CUniformRandomStream_RandomNumber(obj);
	if (fl > RNMX) fl = RNMX;
	return (fl * (fMax - fMin)) + fMin;
}

let recoilRandom = CUniformRandomStream(223); // ak47
let recoilAngle = 0;
let recoilAngleVariance = 70;
let recoilMagnitude = 30;
let recoilMagnitudeVariance = 0;
let recTime = 0.8;
let pAmmo = 30;
let ammoLeft = pAmmo;
let id = "weapon_ak47";

let cycleTimeReset = 0.1; //from item schema

function _G_LoadFromObject(obj: [number, number, number, number, number, number, number, number, string]) {
	recoilRandom = CUniformRandomStream(obj[0]);
	recoilAngle = obj[1];
	recoilAngleVariance = obj[2];
	recoilMagnitude = obj[3];
	recoilMagnitudeVariance = obj[4];
	recTime = obj[5];
	pAmmo = obj[6];
	ammoLeft = pAmmo;
	cycleTimeReset = obj[7];
	id = obj[8];
	Gen();
}

let cycleTime = cycleTimeReset;
const tickrate = 1 / 64;
const recoilTable: { fAngle: number; fMagnitude: number }[] = [];
let fAngle = 0, fMagnitude = 0;

const weapon_recoil_variance = 0.55;
const weapon_recoil_suppression_shots = 4;
const weapon_recoil_suppression_factor = 0.75;
const weapon_recoil_view_punch_extra = 0.3;
const weapon_recoil_vel_decay = 4.5;
const weapon_recoil_decay2_exp = 8;
const weapon_recoil_decay2_lin = 18;
const weapon_recoil_scale = 0.5;

function Gen() {
	fAngle = 0;
	fMagnitude = 0;
	for (let i = 0; i < 64; i++) {
		const fAngleNew = recoilAngle + CUniformRandomStream_RandomFloat(recoilRandom, -recoilAngleVariance, recoilAngleVariance);
		const fMagnitudeNew = recoilMagnitude + CUniformRandomStream_RandomFloat(recoilRandom, -recoilMagnitudeVariance, recoilMagnitudeVariance);
		if (true && i > 0) {
			fAngle = math.lerp(fAngle, fAngleNew, weapon_recoil_variance);
			fMagnitude = math.lerp(fMagnitude, fMagnitudeNew, weapon_recoil_variance);
		} else {
			fAngle = fAngleNew;
			fMagnitude = fMagnitudeNew;
		}
		if (true && i < weapon_recoil_suppression_shots) {
			const fSuppresionFactor = math.lerp(weapon_recoil_suppression_factor, 1, i / weapon_recoil_suppression_shots);
			fMagnitude *= fSuppresionFactor;
		}
		recoilTable[i] = { fAngle, fMagnitude };
	}
}
Gen();

let accumTime = 0;
let recoilIndex = 0;

let aimPunchAngle = new Vector3(0, 0, 0);
let aimPunchAngleVel = new Vector3(0, 0, 0);
let aimPunchAngleVis = new Vector3(0, 0, 0);

function HybridDecay(v: Vector3, fExp: number, fLin: number, dT: number): Vector3 {
	fExp *= dT;
	fLin *= dT;
	v = v.mul(math.exp(-fExp));
	const mag = v.Magnitude;
	if (mag > fLin) {
		v = v.mul(1 - fLin / mag);
	} else {
		v = new Vector3(0, 0, 0);
	}
	return v;
}

function Kickback(fAngle: number, fMagnitude: number) {
	const rad = math.rad(fAngle);
	aimPunchAngleVel = new Vector3(0, -math.sin(rad), -math.cos(rad)).mul(fMagnitude).add(aimPunchAngleVel);
	aimPunchAngleVis = aimPunchAngle;
	aimPunchAngleVis = aimPunchAngleVis.sub(new Vector3(0, math.sin(rad), math.cos(rad)).mul(fMagnitude * weapon_recoil_view_punch_extra));
}

function ViewPunchDecay() {
	let punchAngle = aimPunchAngle;
	let punchVel = aimPunchAngleVel;
	punchAngle = HybridDecay(punchAngle, weapon_recoil_decay2_exp, weapon_recoil_decay2_lin, tickrate);
	aimPunchAngleVis = HybridDecay(aimPunchAngleVis, weapon_recoil_decay2_exp, weapon_recoil_decay2_lin, tickrate);
	punchAngle = punchAngle.add(punchVel.mul(tickrate * 0.5));
	punchVel = punchVel.mul(math.exp(tickrate * -weapon_recoil_vel_decay));
	punchAngle = punchAngle.add(punchVel.mul(tickrate * 0.5));
	aimPunchAngle = punchAngle;
	aimPunchAngleVel = punchVel;
}

function GetAimPunch() {
	return aimPunchAngleVis.mul(weapon_recoil_scale);
}

let YAW = 0, PITCH = 0;

const pgui = Players.LocalPlayer.WaitForChild("PlayerGui") as PlayerGui & {
	ScreenGui: ScreenGui & {
		TextLabel: TextLabel;
		tl2: TextLabel;
		TextBox: TextBox;
	};
};


const default_bulletholes = [
	"4117124202",
	"4117124881",
	"4117125609",
	"4117126706",
	"4117127411",
]

RunService.Stepped.Connect((t, dt) => {
	accumTime += dt;
	while (accumTime > tickrate) {
		accumTime -= tickrate;
		cycleTime -= tickrate;
		if (UserInputService.IsMouseButtonPressed(Enum.UserInputType.MouseButton1)) {
			if (cycleTime < 0) {
				ammoLeft -= 1;
				cycleTime = cycleTimeReset;
				if (ammoLeft === 0) cycleTime = 0.5
				const idx = math.floor(recoilIndex) % 64;
				Kickback(recoilTable[idx].fAngle, recoilTable[idx].fMagnitude);
				recoilIndex++;
				const punch = aimPunchAngle.div(20);
				const rY = math.rad(YAW) - punch.Y;
				const rP = math.rad(PITCH) - punch.Z;
				const cy = math.cos(rY), sy = math.sin(rY), cp = math.cos(rP), sp = math.sin(rP);
				const p1 = Players.LocalPlayer!.Character!.GetPivot().Position.add(new Vector3(0, 2, 0));
				const p2 = new Vector3(cp * cy, sp, cp * sy);
				const rp = new RaycastParams();
				rp.FilterType = Enum.RaycastFilterType.Include;
				rp.FilterDescendantsInstances = [Workspace.FindFirstChild("Hittable")!];
				const rc = Workspace.Raycast(p1, p2.mul(512), rp);
				if (rc) {
					const p = new Instance("Part");
					p.Size = new Vector3(0.6, 0.6, 0.6);
					p.CFrame = CFrame.lookAt(rc.Position, rc.Position.add(rc.Normal));
					p.Color = new Color3(1, 0.5 - math.min(recoilIndex, 30) / 60, 0);
					p.Transparency = 1;
					p.Anchored = true;
					p.Shape = Enum.PartType.Block;
					p.Parent = Workspace;

					const dec = new Instance("Decal")
					dec.Texture = "rbxassetid://" + default_bulletholes[math.random(default_bulletholes.size()) - 1]
					dec.Parent = p
					dec.Face = Enum.NormalId.Front

					CollectionService.AddTag(p, "ToBeRemoved");
				}
			}
		} else {
			const k = math.log(pAmmo) / recTime;
			recoilIndex = math.max(recoilIndex * math.exp(-k * tickrate), 0);
		}
		pgui.ScreenGui.TextLabel.Text = string.format("Recoil index: %.2f (R to reset)", recoilIndex);
		pgui.ScreenGui.tl2.Text = string.format(`Ammo: ${ammoLeft}/${pAmmo}, weapon: ${id}`);
		ViewPunchDecay();
	}
});

let locked = true;
UserInputService.InputBegan.Connect((i, gpe) => {
	if (gpe) return;
	if (i.KeyCode === Enum.KeyCode.E) locked = !locked;
	if (i.KeyCode === Enum.KeyCode.R) {
		recoilIndex = 0;
		ammoLeft = pAmmo;
		for (const v of CollectionService.GetTagged("ToBeRemoved")) v.Destroy();
	}
	if (i.KeyCode === Enum.KeyCode.P) {
		pgui.ScreenGui.TextBox.CaptureFocus();
	}
});

const weps = require(ReplicatedStorage.WaitForChild("weaponList") as ModuleScript) as Record<string, {
	seed: number;
	recoilAng: number;
	recoilAngVar: number;
	recoilMagn: number;
	recoilMagnVar: number;
	tIdle: number;
	primAmmo: number;
	cycle: number;
}>;
pgui.ScreenGui.TextBox.FocusLost.Connect(() => {
	const oldText = pgui.ScreenGui.TextBox.Text;
	const ent = weps[oldText];
	if (ent) {
		_G_LoadFromObject([
			ent.seed,
			ent.recoilAng,
			ent.recoilAngVar,
			ent.recoilMagn,
			ent.recoilMagnVar,
			ent.tIdle,
			ent.primAmmo,
			ent.cycle,
			oldText,
		]);
	} else {
		pgui.ScreenGui.TextBox.PlaceholderText = "(load failed as no such weapon was found)";
	}
	pgui.ScreenGui.TextBox.Text = "";
});

RunService.RenderStepped.Connect((dt) => {
	if (!Players.LocalPlayer!.Character) return;
	UserInputService.MouseBehavior = locked ? Enum.MouseBehavior.LockCenter : Enum.MouseBehavior.Default;
	const mouseDelta = UserInputService.GetMouseDelta().div(10);
	YAW += mouseDelta.X;
	PITCH -= mouseDelta.Y;
	YAW = YAW % 360;
	if (PITCH > 89) PITCH = 89;
	if (PITCH <= -89) PITCH = -89;
	const punch = GetAimPunch();
	const rY = math.rad(YAW) - math.rad(punch.Y);
	const rP = math.rad(PITCH) - math.rad(punch.Z);
	const cy = math.cos(rY), sy = math.sin(rY), cp = math.cos(rP), sp = math.sin(rP);
	const p1 = Players.LocalPlayer!.Character!.GetPivot().Position.add(new Vector3(0, 2, 0));
	const p2 = new Vector3(cp * cy, sp, cp * sy);
	Workspace.CurrentCamera!.CameraType = Enum.CameraType.Scriptable;
	Workspace.CurrentCamera!.CFrame = CFrame.lookAt(p1, p1.add(p2));
});
