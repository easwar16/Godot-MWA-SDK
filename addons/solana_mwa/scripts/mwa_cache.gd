class_name MWACache
## Abstract base class for MWA authorization cache.
## Extend this class to implement custom cache backends (file, database, etc).

## Called to retrieve the cached authorization. Return null if no cache exists.
func get_authorization() -> Variant:
	return null

## Called to store an authorization result.
func set_authorization(_auth) -> void:
	pass

## Called to clear the cached authorization (on deauthorize/disconnect).
func clear() -> void:
	pass

## Called to check if a cached authorization exists.
func has_authorization() -> bool:
	var auth := get_authorization()
	return auth != null and auth.auth_token != ""
