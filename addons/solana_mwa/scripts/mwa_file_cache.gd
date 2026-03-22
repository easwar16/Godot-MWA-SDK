class_name MWAFileCache
extends MWACache
## File-based authorization cache using Godot's user:// directory.
## Persists auth tokens across app restarts.
## Uses atomic writes (temp file + rename) to prevent corruption.

const CACHE_PATH := "user://mwa_auth_cache.json"
const CACHE_TMP := "user://mwa_auth_cache.json.tmp"

func get_authorization() -> Variant:
	if not FileAccess.file_exists(CACHE_PATH):
		return null
	var file := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return null
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
	# Atomic write: write to temp file, then rename.
	var file := FileAccess.open(CACHE_TMP, FileAccess.WRITE)
	if file == null:
		push_warning("MWAFileCache: Failed to open temp cache file")
		return
	file.store_string(JSON.stringify(auth.to_dict()))
	file.close()
	# Rename temp to final (atomic on most filesystems).
	var dir := DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(CACHE_PATH):
			dir.remove(CACHE_PATH.get_file())
		dir.rename(CACHE_TMP.get_file(), CACHE_PATH.get_file())

func clear() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		DirAccess.remove_absolute(CACHE_PATH)
	if FileAccess.file_exists(CACHE_TMP):
		DirAccess.remove_absolute(CACHE_TMP)
