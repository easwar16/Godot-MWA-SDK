extends SceneTree
## Unit tests for MWACache abstract class and MWAFileCache implementation.

var _pass_count := 0
var _fail_count := 0
var _test_name := ""


func _init() -> void:
	print("\n=== MWACache Tests ===\n")

	test_abstract_cache_returns_null()
	test_abstract_cache_has_authorization_false()
	test_file_cache_empty_returns_null()
	test_file_cache_write_and_read()
	test_file_cache_has_authorization()
	test_file_cache_clear()
	test_file_cache_clear_nonexistent()
	test_file_cache_overwrite()
	test_file_cache_set_null_clears()
	test_custom_cache_implementation()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	if _fail_count > 0:
		quit(1)
	else:
		quit(0)


func _start(name: String) -> void:
	_test_name = name


func _assert_eq(actual, expected, msg: String = "") -> void:
	var label := "%s: %s" % [_test_name, msg] if msg != "" else _test_name
	if actual == expected:
		_pass_count += 1
		print("  PASS  %s" % label)
	else:
		_fail_count += 1
		print("  FAIL  %s — expected '%s', got '%s'" % [label, str(expected), str(actual)])


func _assert_true(value: bool, msg: String = "") -> void:
	_assert_eq(value, true, msg)


func _assert_false(value: bool, msg: String = "") -> void:
	_assert_eq(value, false, msg)


func _assert_null(value, msg: String = "") -> void:
	var label := "%s: %s" % [_test_name, msg] if msg != "" else _test_name
	if value == null:
		_pass_count += 1
		print("  PASS  %s" % label)
	else:
		_fail_count += 1
		print("  FAIL  %s — expected null, got '%s'" % [label, str(value)])


func _assert_not_null(value, msg: String = "") -> void:
	var label := "%s: %s" % [_test_name, msg] if msg != "" else _test_name
	if value != null:
		_pass_count += 1
		print("  PASS  %s" % label)
	else:
		_fail_count += 1
		print("  FAIL  %s — expected non-null" % label)


func _cleanup_cache() -> void:
	var path := "user://mwa_auth_cache.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _make_test_auth(token: String = "test_token") -> MWATypes.AuthorizationResult:
	var auth := MWATypes.AuthorizationResult.new()
	auth.auth_token = token
	auth.wallet_uri_base = "https://test.wallet"
	auth.accounts = [
		MWATypes.Account.new("TestAddr123", PackedByteArray([1, 2, 3, 4, 5]))
	]
	return auth


# --- Abstract Cache Tests ---

func test_abstract_cache_returns_null() -> void:
	_start("Abstract MWACache.get_authorization() returns null")
	var cache := MWACache.new()
	_assert_null(cache.get_authorization(), "returns null")


func test_abstract_cache_has_authorization_false() -> void:
	_start("Abstract MWACache.has_authorization() returns false")
	var cache := MWACache.new()
	_assert_false(cache.has_authorization(), "no authorization")


# --- File Cache Tests ---

func test_file_cache_empty_returns_null() -> void:
	_start("MWAFileCache empty returns null")
	_cleanup_cache()
	var cache := MWAFileCache.new()
	_assert_null(cache.get_authorization(), "no cached auth")
	_assert_false(cache.has_authorization(), "has_authorization false")


func test_file_cache_write_and_read() -> void:
	_start("MWAFileCache write then read")
	_cleanup_cache()
	var cache := MWAFileCache.new()

	var auth := _make_test_auth("write_read_token")
	cache.set_authorization(auth)

	var restored := cache.get_authorization()
	_assert_not_null(restored, "restored is not null")
	_assert_eq(restored.auth_token, "write_read_token", "token matches")
	_assert_eq(restored.wallet_uri_base, "https://test.wallet", "wallet_uri_base matches")
	_assert_eq(restored.accounts.size(), 1, "account count matches")
	_assert_eq(restored.accounts[0].address, "TestAddr123", "account address matches")
	_assert_eq(restored.accounts[0].public_key, PackedByteArray([1, 2, 3, 4, 5]), "public_key matches")
	_cleanup_cache()


func test_file_cache_has_authorization() -> void:
	_start("MWAFileCache.has_authorization() after write")
	_cleanup_cache()
	var cache := MWAFileCache.new()
	cache.set_authorization(_make_test_auth())
	_assert_true(cache.has_authorization(), "has_authorization true after write")
	_cleanup_cache()


func test_file_cache_clear() -> void:
	_start("MWAFileCache.clear()")
	_cleanup_cache()
	var cache := MWAFileCache.new()
	cache.set_authorization(_make_test_auth())
	_assert_true(cache.has_authorization(), "auth exists before clear")
	cache.clear()
	_assert_false(cache.has_authorization(), "auth gone after clear")
	_assert_null(cache.get_authorization(), "get returns null after clear")


func test_file_cache_clear_nonexistent() -> void:
	_start("MWAFileCache.clear() when no cache file")
	_cleanup_cache()
	var cache := MWAFileCache.new()
	# Should not throw
	cache.clear()
	_assert_false(cache.has_authorization(), "still no auth")


func test_file_cache_overwrite() -> void:
	_start("MWAFileCache overwrite existing cache")
	_cleanup_cache()
	var cache := MWAFileCache.new()
	cache.set_authorization(_make_test_auth("first_token"))
	cache.set_authorization(_make_test_auth("second_token"))
	var restored := cache.get_authorization()
	_assert_eq(restored.auth_token, "second_token", "overwritten token")
	_cleanup_cache()


func test_file_cache_set_null_clears() -> void:
	_start("MWAFileCache.set_authorization(null) clears")
	_cleanup_cache()
	var cache := MWAFileCache.new()
	cache.set_authorization(_make_test_auth())
	_assert_true(cache.has_authorization(), "auth exists")
	cache.set_authorization(null)
	_assert_false(cache.has_authorization(), "cleared by null")
	_cleanup_cache()


# --- Custom Cache Implementation Test ---

func test_custom_cache_implementation() -> void:
	_start("Custom cache implementation (in-memory)")
	var cache := InMemoryCache.new()
	_assert_false(cache.has_authorization(), "empty initially")

	var auth := _make_test_auth("memory_token")
	cache.set_authorization(auth)
	_assert_true(cache.has_authorization(), "has auth after set")
	_assert_eq(cache.get_authorization().auth_token, "memory_token", "token matches")

	cache.clear()
	_assert_false(cache.has_authorization(), "cleared")


## In-memory cache for testing extensibility.
class InMemoryCache extends MWACache:
	var _stored = null

	func get_authorization() -> Variant:
		return _stored

	func set_authorization(auth) -> void:
		_stored = auth

	func clear() -> void:
		_stored = null
