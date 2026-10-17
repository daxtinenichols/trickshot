extends RefCounted
## What enemy_shots.gd renders: lineups of enemies with state set by hand.
## items: [script path, {property: value, "_call": Callable(enemy)}].

const R := "res://enemies/raider.gd"
const M := "res://enemies/mutant.gd"
const S := "res://enemies/trooper.gd"
const H := "res://enemies/shield.gd"
const D := "res://enemies/drone.gd"
const E := "res://enemies/"


static func lineups() -> Array:
	var front := [Vector3(0, 1.4, -7.5), Vector3(0, 1.0, 0), "front"]
	var three := [Vector3(5.5, 2.2, -5.5), Vector3(0, 0.9, 0), "three_quarter"]
	return [
		{"name": "raider", "views": [front, three], "items": [
			[R, {}],
			[R, {"state": 1, "velocity": Vector3(0, 0, -3)}],
			[R, {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
			[R, {"duck": 1.0}],
			[R, {"state": 4}],
		]},
		{"name": "mutant", "views": [front, three], "items": [
			[M, {}],
			[M, {"velocity": Vector3(0, 0, -8)}],
			[M, {"state": 1, "telegraph": 1.0}],
			[M, {"state": 3}],
			[M, {"state": 4, "telegraph": 1.0}],
		]},
		{"name": "soldier", "views": [front, three], "items": [
			[S, {}],
			[S, {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
			[S, {"duck": 1.0}],
			[H, {}],
			[H, {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
		]},
		{"name": "static", "views": [front, three], "items": [
			[E + "hunter.gd", {}],
			[E + "hunter.gd", {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
			[E + "bruiser.gd", {}],
			[E + "juno.gd", {}],
			[E + "juno.gd", {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
		]},
		{"name": "ward", "views": [front, three], "items": [
			[E + "marksman.gd", {}],
			[E + "marksman.gd", {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
			[E + "trooper.gd", {"helmet": false, "_call": func(e: Node) -> void: e.body.show_part("Helmet", false)}],
			[E + "heavy.gd", {}],
			[E + "heavy.gd", {"state": 2, "aim_dir": Vector3(0, 0, -1)}],
		]},
		{"name": "hollows", "views": [front, three], "items": [
			[E + "leaper.gd", {}],
			[E + "crawler.gd", {}],
			[E + "brute.gd", {}],
			[E + "brute.gd", {"state": 7, "telegraph": 0.8}],
			[E + "leaper.gd", {"state": 1, "telegraph": 1.0}],
		]},
		{"name": "drone", "views": [[Vector3(0, 2.4, -4.5), Vector3(0, 1.4, 0), "front"], [Vector3(3.5, 3.0, -3.0), Vector3(0, 1.2, 0), "three_quarter"]], "items": [
			[D, {"position": Vector3(-1.1, 1.0, 0)}],
			[D, {"position": Vector3(1.1, 1.0, 0), "state": 1, "telegraph": 1.0, "aim_dir": Vector3(0, -0.2, -1).normalized()}],
			[E + "camera_drone.gd", {"position": Vector3(-1.1, 2.2, 1.5)}],
			[E + "spotter_drone.gd", {"position": Vector3(1.1, 2.2, 1.5)}],
		]},
	]
