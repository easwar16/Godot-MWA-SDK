extends SceneTree
## Unit tests for MobileWalletAdapter state management and guard logic.
## These tests run without the Android plugin (desktop environment).

var _pass_count := 0
var _fail_count := 0
var _test_name := ""


func _init() -> void:
	print("\n=== Adapter State Tests ===\n")

	test_initial_state()
	test_is_authorized_false_initially()
	test_is_wallet_connected_false_initially()
	test_is_busy_false_initially()
	test_authorize_without_plugin_emits_error()
	test_deauthorize_without_auth_emits_success()
	test_sign_transactions_without_auth_emits_error()
	test_sign_and_send_without_auth_emits_error()
	test_sign_messages_without_auth_emits_error()
	test_clone_authorization_emits_deprecated()
	test_set_identity()
	test_set_cluster()
	test_get_account_null_initially()
	test_get_accounts_empty_initially()
	test_get_public_key_empty_initially()
	test_reconnect_without_cache_calls_authorize()
	test_disconnect_wallet_alias()
	test_cache_swap_at_runtime()
	test_state_change_signal()

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


func _make_adapter() -> MobileWalletAdapter:
	var adapter := MobileWalletAdapter.new()
	# Don't add to tree — we're testing logic only, not _ready()/_process().
	return adapter


# --- Initial State Tests ---

func test_initial_state() -> void:
	_start("Initial state is DISCONNECTED")
	var adapter := _make_adapter()
	_assert_eq(adapter.state, MWATypes.ConnectionState.DISCONNECTED, "state")


func test_is_authorized_false_initially() -> void:
	_start("is_authorized() false initially")
	var adapter := _make_adapter()
	_assert_false(adapter.is_authorized(), "not authorized")


func test_is_wallet_connected_false_initially() -> void:
	_start("is_wallet_connected() false initially")
	var adapter := _make_adapter()
	_assert_false(adapter.is_wallet_connected(), "not connected")


func test_is_busy_false_initially() -> void:
	_start("is_busy() false initially")
	var adapter := _make_adapter()
	_assert_false(adapter.is_busy(), "not busy")


# --- Error Guard Tests (no Android plugin) ---

func test_authorize_without_plugin_emits_error() -> void:
	_start("authorize() without plugin emits error")
	var adapter := _make_adapter()
	var received_error := false
	var received_code := 0
	adapter.authorization_failed.connect(func(code, msg):
		received_error = true
		received_code = code
	)
	adapter.authorize()
	_assert_true(received_error, "error emitted")
	_assert_eq(received_code, MWATypes.ErrorCode.AUTHORIZATION_FAILED, "correct error code")


func test_deauthorize_without_auth_emits_success() -> void:
	_start("deauthorize() without prior auth emits deauthorized")
	var adapter := _make_adapter()
	var received := false
	adapter.deauthorized.connect(func(): received = true)
	adapter.deauthorize()
	_assert_true(received, "deauthorized emitted")
	_assert_eq(adapter.state, MWATypes.ConnectionState.DISCONNECTED, "state is disconnected")


func test_sign_transactions_without_auth_emits_error() -> void:
	_start("sign_transactions() without auth emits error")
	var adapter := _make_adapter()
	var received_code := 0
	adapter.transactions_sign_failed.connect(func(code, msg): received_code = code)
	adapter.sign_transactions([PackedByteArray([1, 2, 3])])
	_assert_eq(received_code, MWATypes.ErrorCode.AUTHORIZATION_FAILED, "auth required error")


func test_sign_and_send_without_auth_emits_error() -> void:
	_start("sign_and_send_transactions() without auth emits error")
	var adapter := _make_adapter()
	var received_code := 0
	adapter.transactions_send_failed.connect(func(code, msg): received_code = code)
	adapter.sign_and_send_transactions([PackedByteArray([1, 2, 3])])
	_assert_eq(received_code, MWATypes.ErrorCode.AUTHORIZATION_FAILED, "auth required error")


func test_sign_messages_without_auth_emits_error() -> void:
	_start("sign_messages() without auth emits error")
	var adapter := _make_adapter()
	var received_code := 0
	adapter.messages_sign_failed.connect(func(code, msg): received_code = code)
	adapter.sign_messages([PackedByteArray([1, 2, 3])])
	_assert_eq(received_code, MWATypes.ErrorCode.AUTHORIZATION_FAILED, "auth required error")


func test_clone_authorization_emits_deprecated() -> void:
	_start("clone_authorization() emits deprecated error")
	var adapter := _make_adapter()
	var received_msg := ""
	adapter.clone_failed.connect(func(msg): received_msg = msg)
	adapter.clone_authorization()
	_assert_true(received_msg.contains("not supported"), "deprecated message")


# --- Property Tests ---

func test_set_identity() -> void:
	_start("Set dapp identity")
	var adapter := _make_adapter()
	adapter.identity = MWATypes.DappIdentity.new("Test Game", "https://test.game", "test.png")
	_assert_eq(adapter.identity.name, "Test Game", "name set")
	_assert_eq(adapter.identity.uri, "https://test.game", "uri set")
	_assert_eq(adapter.identity.icon, "test.png", "icon set")


func test_set_cluster() -> void:
	_start("Set cluster")
	var adapter := _make_adapter()
	adapter.cluster = MWATypes.Cluster.MAINNET
	_assert_eq(adapter.cluster, MWATypes.Cluster.MAINNET, "cluster set")


func test_get_account_null_initially() -> void:
	_start("get_account() null initially")
	var adapter := _make_adapter()
	_assert_null(adapter.get_account(), "no account")


func test_get_accounts_empty_initially() -> void:
	_start("get_accounts() empty initially")
	var adapter := _make_adapter()
	_assert_eq(adapter.get_accounts().size(), 0, "no accounts")


func test_get_public_key_empty_initially() -> void:
	_start("get_public_key() empty initially")
	var adapter := _make_adapter()
	_assert_eq(adapter.get_public_key(), PackedByteArray(), "empty key")


# --- Reconnect / Disconnect Tests ---

func test_reconnect_without_cache_calls_authorize() -> void:
	_start("reconnect() without cache falls through to authorize()")
	var adapter := _make_adapter()
	adapter.auth_cache = MWACache.new()  # Empty abstract cache
	var error_received := false
	adapter.authorization_failed.connect(func(code, msg): error_received = true)
	adapter.reconnect()
	# Without Android plugin, authorize() will emit error
	_assert_true(error_received, "authorize() was called")


func test_disconnect_wallet_alias() -> void:
	_start("disconnect_wallet() is alias for deauthorize()")
	var adapter := _make_adapter()
	var deauth_received := false
	adapter.deauthorized.connect(func(): deauth_received = true)
	adapter.disconnect_wallet()
	_assert_true(deauth_received, "deauthorize called via alias")


# --- Cache Swap Tests ---

func test_cache_swap_at_runtime() -> void:
	_start("set_cache() swaps cache at runtime")
	var adapter := _make_adapter()

	# Set up in-memory cache with auth.
	var cache := TestMemoryCache.new()
	var auth := MWATypes.AuthorizationResult.new()
	auth.auth_token = "cached_tok"
	auth.accounts = [MWATypes.Account.new("CacheAddr")]
	cache._data = auth

	adapter.set_cache(cache)
	_assert_true(adapter.is_authorized(), "authorized from swapped cache")
	_assert_eq(adapter.current_auth.auth_token, "cached_tok", "token loaded from cache")


# --- State Change Signal ---

func test_state_change_signal() -> void:
	_start("state_changed signal fires on state change")
	var adapter := _make_adapter()
	var received_states := []
	adapter.state_changed.connect(func(s): received_states.append(s))

	adapter.state = MWATypes.ConnectionState.CONNECTING
	adapter.state = MWATypes.ConnectionState.CONNECTED

	_assert_eq(received_states.size(), 2, "two state changes")
	_assert_eq(received_states[0], MWATypes.ConnectionState.CONNECTING, "first state")
	_assert_eq(received_states[1], MWATypes.ConnectionState.CONNECTED, "second state")


## Test helper: in-memory cache.
class TestMemoryCache extends MWACache:
	var _data = null
	func get_authorization() -> Variant:
		return _data
	func set_authorization(auth) -> void:
		_data = auth
	func clear() -> void:
		_data = null
