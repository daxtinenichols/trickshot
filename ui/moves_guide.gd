class_name MovesGuide
extends RefCounted
## Every move, how to do it, and what doing it well gets you. Shown in the
## pause menu. `{action}` is replaced by the player's current binding.

const MOVES := [
	["Run", "Move in any direction. You're always sprinting; let go to stop.", "Keep moving fast to build momentum: your running speed climbs from 7.5 to 11.5 m/s. There's no top speed: clean vaults, perfect hops and wall jumps stack speed on top while you keep running."],
	["Jump / hop", "{jump}.", "Jump right as you land to keep all your speed and add a little, with no cap: perfect chains keep getting faster. Early or late jumps bleed it."],
	["Hurdle / vault", "Press {jump} at anything waist-high (a concrete barrier, a rail, sandbags, crates), on the ground or in the air. It's never automatic, so you can always just jump over.", "A vault never slows you. Take off close to the wall for a clean vault that adds speed."],
	["Mantle", "Jump into a ledge that's too high to vault.", "You keep your run through it. A clean grab adds a little speed, even off a wall climb."],
	["Slide", "Press {crouch} while sprinting.", "Faster entries slide further. Works on any slope or ramp: down speeds you up, up trades speed for height."],
	["Slide landing", "Press {crouch} just before you land from a jump or fall.", "Turns part of your fall into forward speed."],
	["Roll", "Double-tap {crouch} while running, or flick the view down past your feet.", "A quick forward roll. Keeps your speed."],
	["Landing roll", "Press {crouch} just before (or a split second after) you land, hold it in the air from any angle (even mid-flip), or land looking down.", "You curl into a ball and roll out of big drops without losing speed. Ramps count by how hard you hit them, so a slope running away from you lands soft. Miss the roll on a smaller drop and you stumble, losing a little speed; only a really big drop stuns you."],
	["Wallrun", "Jump into a sheet-metal wall or billboard at an angle, holding a direction.", "You keep the angle you hit the wall at, and gravity slowly bends your path down. A shallow angle and more speed give a longer run. Lean ({lean_left} / {lean_right}) to roll your path round on the wall: toward the wall turns it up, away turns it down. Look and aim anywhere while you run."],
	["Wall hop", "Press {jump} while wallrunning or next to a wall in the air.", "You kick off in the direction you're heading. The steeper you're running up the wall, the harder you kick off. Chain wall to wall."],
	["Wall climb", "Jump at a wall head-on.", "Straighter and faster gets you higher. Press {jump} mid-climb to kick back off."],
	["Ramps and loops", "Run onto a purple ramp or loop.", "Going up slows you. Fast enough and you run up steep ramps and upside down round loops; too slow and you drop off (off a loop upside down, you keep turning, so come round and land it). Launch off a ramp's lip for air tricks. {jump} jumps off."],
	["Sideways ramps", "Run onto a purple bank at an angle, or across any steep ramp.", "Run along it tilted, like a wallrun. Steer or look up the slope to climb it; let go to drift down."],
	["Lean / quick turn", "Hold {lean_left} or {lean_right}.", "Leans you to peek around corners. While held, turning toward that side swings your run round with it without losing speed. The view turns at your normal speed."],
	["Side flip", "Hold {lean_left} or {lean_right} in the air.", "Rolls you sideways, the way you first pressed. Hold it (or {crouch}) to tuck and spin faster, let go to open up and slow down. Near level it settles; land on your side and you shoulder-roll, losing a little speed. Coming off a wallrun, let go of the lean and press it again to flip."],
	["Mouse lean and roll (testing)", "Hold {steer} and move the mouse left or right.", "On your feet you lean into the turn: the faster you turn, the more you lean and the harder you turn, keeping your speed. In the air or on a wall the mouse rolls you instead of turning, by as much as you move it, either way: a side flip in the air, or rolling your wallrun's path up or down the wall. Roll fast and let go and it carries on like an opened-up side flip. Up and down still aim."],
	["Kick", "{kick}.", "Opens doors and breaks windows. Hurts enemies and knocks them flat (more with a bigger combo). In the air, kick off walls, targets and enemies. More speed, bigger push."],
	["Body check", "Run into an enemy at speed.", "Knocks it flat and you carry on through, a bit slower. Heavies, brutes and drones only stagger: you shoulder past, slower still."],
	["Reading the city", "Obstacles look like part of the city.", "Concrete, brick, crates, rails and sandbags are for vaulting, mantling and climbing. Corrugated sheet metal and billboards are for wallruns. Pipes and girders at head height are for sliding under, bent sheet metal for sliding down, and purple ramps and loops for running. Press F9 for the plain color-coded graybox."],
	["Window smash", "Run or slide into glass fast.", "Low windows are too low to run through: slide under and smash them."],
	["Backflip", "In the air, keep moving the view up and over until it comes back around.", "Flick hard: past straight up it turns faster. Flick past halfway and let go, and momentum carries you round. Land level or you crash."],
	["Front flip", "In the air, keep moving the view down and over.", "Same as the backflip, the other way."],
	["360 / 720", "In the air, turn a full circle (or two).", "A fast spin carries on by itself once you're past halfway. Holding {lean_left} or {lean_right} spins you faster."],
	["Combos", "Chain moves and stylish hits without stopping. Each different trick adds +1 to the multiplier.", "Faster and cleaner moves score more. The combo banks when you stop or go 2 s without a trick; a kill finishes it on the spot (COMBO KILL). Crashing, a hard landing or slamming into a wall loses it. Bigger combos make your shots hit harder (up to 3x)."],
	["Shooting", "{fire} to fire, {aim} to aim, {fire_mode} switches semi/auto, {reload} reloads.", "The first shot always lands on the crosshair, even mid-flip. Headshots do 2.5x. Aim help in Settings bends near misses onto heads."],
]


## Fills in `{action}` placeholders with the current bindings (keyboard and
## controller when both exist, e.g. "Space / A").
static func describe(text: String) -> String:
	var out := text
	for pair: Array in GameSettings.REBINDABLE:
		var action: String = pair[0]
		var tag := "{%s}" % action
		if not out.contains(tag):
			continue
		var kbm := GameSettings.slot_event(action, false)
		var pad := GameSettings.slot_event(action, true)
		var label := GameSettings.event_label(kbm)
		if pad != null:
			label += " / " + GameSettings.event_label(pad)
		out = out.replace(tag, label)
	return out
