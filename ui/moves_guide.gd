class_name MovesGuide
extends RefCounted
## Every move, how to do it, and what doing it well gets you. Shown in the
## pause menu. `{action}` is replaced by the player's current binding.

const MOVES := [
	["Sprint", "Hold {sprint} while moving (any direction).", "Keep moving fast to build momentum: your top speed climbs from 6 to 9.5 m/s."],
	["Jump / hop", "{jump}.", "Jump right as you land to keep all your speed. Early or late jumps bleed it."],
	["Hurdle / vault", "Run at a waist-high yellow wall and press {jump}.", "Take off close to the wall for a faster, cleaner vault."],
	["Mantle", "Jump into a ledge that's too high to vault.", "A clean grab keeps more of your speed."],
	["Slide", "Press {crouch} while sprinting.", "Faster entries slide further. Slopes add speed."],
	["Slide landing", "Hold {crouch} as you land from a jump or fall.", "Turns part of your fall into forward speed."],
	["Landing roll", "Press {crouch} just before landing from a big drop.", "Good timing keeps your speed instead of stumbling."],
	["Prone", "Hold {prone}. Let go to get up.", "You can also hold {crouch} while standing still."],
	["Dolphin dive", "Press {prone} while running fast.", "Tap it to dive and pop up into a slide. Hold it to stay down. Dive through low windows."],
	["Wallrun", "Jump into a blue wall at an angle, holding a direction.", "A shallow angle and more speed give a longer, floatier run. Look and aim anywhere while you run."],
	["Wall hop", "Press {jump} while wallrunning or next to a wall in the air.", "You kick off in the direction you're looking. Chain wall to wall."],
	["Wall climb", "Jump at a wall head-on.", "Straighter and faster gets you higher. Press {jump} mid-climb to kick back off."],
	["Quick turn", "{quick_turn}.", "Spins you 180. On a wall it faces you away from it, ready to jump."],
	["Kick", "{kick}.", "Opens doors and breaks windows. In the air, kick off walls and targets. More speed, bigger push."],
	["Window smash", "Run, slide or dive into glass fast.", ""],
	["Backflip", "In the air, keep moving the view up and over until it comes back around.", "Flick hard: past straight up it turns faster. Land level or you crash."],
	["Front flip", "In the air, keep moving the view down and over.", "Same as the backflip, the other way."],
	["360 / 720", "In the air, turn a full circle (or two).", "Quick turn doesn't count. You have to spin it yourself."],
	["Combos", "Chain moves and stylish hits without stopping. Each different trick adds +1 to the multiplier.", "Faster and cleaner moves score more. The combo banks when you stop or go 2 s without a trick; crashing, a hard landing or slamming into a wall loses it. Bigger combos make your shots hit harder (up to 3x)."],
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
