class_name MWAFileCache
extends MWACache
## File-based authorization cache using Godot's user:// directory.
## Persists auth tokens across app restarts.

const CACHE_PATH := "user://mwa_auth_cache.json"

func get_authorization() -> Variant:
	if not FileAccess.file_exists(CACHE_PATH):
		return null
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var data: Dictionary = json.data
	if not data.has("auth_token") or data["auth_token"] == "":
		return null
	return MWATypes.AuthorizationResult.from_dict(data)

func set_authorization(auth) -> void:
	if auth == null:
		clear()
		return
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("MWAFileCache: Failed to open cache file for writing")
		return
	file.store_string(JSON.stringify(auth.to_dict()))
	file.close()

func clear() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(CACHE_PATH)
