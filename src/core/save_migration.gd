class_name SaveMigration
extends Object
## Upgrades old save payloads to the current format.
##
## Its own file, not a method on [SaveManager], for two reasons: the manager was
## already near the size limit before this phase added to it, and migration is
## pure data in, data out -- no nodes, no tree -- so it can be tested by handing
## it a payload written by hand.
##
## **Never delete a branch below.** Players skip versions: someone returning
## after two updates arrives with a v1 file and has to walk through every step.

## Upgrades [param payload] in place to [constant GameConstants.SAVE_VERSION].
static func migrate(payload: Dictionary) -> Dictionary:
	var version := version_of(payload)
	if version == GameConstants.SAVE_VERSION:
		return payload
	if version > GameConstants.SAVE_VERSION:
		push_warning("SaveMigration: save is from a newer build (v%d > v%d); loading anyway"
			% [version, GameConstants.SAVE_VERSION])
		return payload

	if version < 2:
		payload = _v1_to_v2(payload)
	if version < 3:
		payload = _v2_to_v3(payload)

	var header: Dictionary = payload.get("header", {})
	header["version"] = GameConstants.SAVE_VERSION
	payload["header"] = header
	return payload


static func version_of(payload: Dictionary) -> int:
	return int((payload.get("header", {}) as Dictionary).get("version", 0))


## v1 held one flat block of scene state with nothing saying which map it
## belonged to, because there was only ever one. Everything in such a file was
## on the starting map, so that is where it goes.
## v2 filed the player under whichever map they were standing on, so walking
## back into a map put them where they last stood there instead of at the door.
## Lift any such entry out into its own block.
static func _v2_to_v3(payload: Dictionary) -> Dictionary:
	var traveller: Dictionary = payload.get("traveller", {})
	var scene: Dictionary = payload.get("scene", {})
	for map_id in scene:
		var block: Dictionary = scene[map_id]
		if block.has("player"):
			# The map they were last on holds the position worth keeping.
			if String(map_id) == String(payload.get("header", {}).get("map_id", map_id)) \
					or not traveller.has("player"):
				traveller["player"] = block["player"]
			block.erase("player")
	payload["traveller"] = traveller
	return payload


static func _v1_to_v2(payload: Dictionary) -> Dictionary:
	var scene: Dictionary = payload.get("scene", {})
	if scene.is_empty():
		payload["scene"] = {}
		return payload
	payload["scene"] = {String(GameConstants.STARTING_MAP): scene}
	return payload
