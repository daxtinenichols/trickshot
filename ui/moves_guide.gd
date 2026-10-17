class_name MovesGuide
extends RefCounted
## Every move, how to do it, and what doing it well gets you. Shown in the
## pause menu. `{action}` is replaced by the player's current binding.

const MOVES := [
	["Run", "Move in any direction. You're always sprinting; let go to stop.", "Keep moving fast to build momentum: your top speed climbs from 7.5 to 11.5 m/s."],
	["Jump / hop", "{jump}.", "Jump right as you land to keep all your speed. Early or late jumps bleed it."],
	["Hurdle / vault", "Press {jump} at a waist-high yellow wall, on the ground or in the air. It's never automatic, so you can always just jump over.", "Take off close to the wall for a faster, cleaner vault."],
	["Mantle", "Jump into a ledge that's too high to vault.", "A clean grab keeps more of your speed."],
	["Slide", "Press {crouch} while sprinting.", "Faster entries slide further. Slopes add speed."],
	["Slide landing", "Hold {crouch} as you land from a jump or fall.", "Turns part of your fall into forward speed."],
	["Roll", "On the ground, flick the view down past your feet.", "A forward roll, like a flip on the ground. Keeps your speed."],
	["Landing roll", "Land looking down (tucked forward, or partway into a front flip), or press {crouch} just before a big landing.", "Rolls out of big drops without losing speed instead of stumbling."],
	["Dolphin dive", "Press {prone} (prone jump).", "Tap it to dive and pop up into a slide. Hold it to stay on your belly under low gaps. You get up by yourself. Dive through low windows."],
	["Wallrun", "Jump into a blue wall at an angle, holding a direction.", "A shallow angle and more speed give a longer, floatier run. Look and aim anywhere while you run."],
	["Wall hop", "Press {jump} while wallrunning or next to a wall in the air.", "You kick off in the direction you're looking. Chain wall to wall."],
	["Wall climb", "Jump at a wall head-on.", "Straighter and faster gets you higher. Press {jump} mid-climb to kick back off."],
	["Ramps and loops", "Run onto a purple ramp or loop.", "Going up slows you. Fast enough and you run up steep ramps and upside down round loops; too slow and you drop off. Launch off a ramp's lip for air tricks. {jump} jumps off."],
	["Quick turn", "{quick_turn}.", "Spins you 180. On a wall it faces you away from it, ready to jump."],
	["Lean", "Hold {lean_left} or {lean_right} on the ground.", "Peek around corners."],
	["Side flip", "Hold {lean_left} or {lean_right} in the air.", "Rolls you sideways. Let go near level to land clean; land on your side and you crash."],
	["Kick", "{kick}.", "Opens doors and breaks windows. In the air, kick off walls and targets. More speed, bigger push."],
	["Window smash", "Run, slide or dive into glass fast.", ""],
	["Backflip", "In the air, keep moving the view up and over until it comes back around.", "Flick hard: past straight up it turns faster. Land level or you crash."],
	["Front flip", "In the air, keep moving the view down and over.", "Same as the backflip, the other way."],
	["360 / 720", "In the air, turn a full circle (or two).", "Quick turn doesn't count. You have to spin it yourself."],
	["Combos", "Chain moves and stylish hits without stopping. Each different trick adds +1 to the multiplier.", "Faster and cleaner moves score more. The combo banks when you stop or go 2 s without a trick; a kill finishes it on the spot (COMBO KILL). Crashing, a hard landing or slamming into a wall loses it. Bigger combos make your shots hit harder (up to 3x)."],
	["Shooting", "{fire} to fire, {aim} to aim, {fire_mode} switches semi/auto, {reload} reloads.", "The first shot always lands on the crosshair, even mid-flip. Headshots do 2.5x."],
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
