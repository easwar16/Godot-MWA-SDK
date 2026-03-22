extends SceneTree
## Unit tests for MWATypes data classes, enums, and serialization.

var _pass_count := 0
var _fail_count := 0
var _test_name := ""


func _init() -> void:
	print("\n=== MWATypes Tests ===\n")

	test_cluster_enum_values()
	test_error_code_enum_values()
	test_connection_state_enum()
	test_cluster_to_chain()
	test_chain_to_cluster()
	test_result_ok()
	test_result_err()
	test_account_to_dict()
	test_account_from_dict()
	test_account_roundtrip()
	test_authorization_result_to_dict()
	test_authorization_result_from_dict()
	test_authorization_result_roundtrip()
	test_dapp_identity_defaults()
	test_dapp_identity_custom()
	test_send_options_defaults()
	test_send_options_to_dict()
	test_send_options_min_context_slot_excluded()
	test_sign_in_payload_empty()
	test_sign_in_payload_populated()
	test_sign_in_payload_partial()
	test_wallet_capabilities_defaults()
	test_account_empty_public_key()
	test_authorization_result_empty_accounts()
	test_cluster_to_chain_unknown_returns_mainnet()

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


# --- Enum Tests ---

func test_cluster_enum_values() -> void:
	_start("Cluster enum values")
	_assert_eq(MWATypes.Cluster.DEVNET, 0, "DEVNET")
	_assert_eq(MWATypes.Cluster.MAINNET, 1, "MAINNET")
	_assert_eq(MWATypes.Cluster.TESTNET, 2, "TESTNET")


func test_error_code_enum_values() -> void:
	_start("ErrorCode enum values")
	_assert_eq(MWATypes.ErrorCode.AUTHORIZATION_FAILED, -1, "AUTHORIZATION_FAILED")
	_assert_eq(MWATypes.ErrorCode.BUSY, -8, "BUSY")
	_assert_eq(MWATypes.ErrorCode.NO_WALLET_FOUND, -10, "NO_WALLET_FOUND")
	_assert_eq(MWATypes.ErrorCode.TIMEOUT, -11, "TIMEOUT")
	_assert_eq(MWATypes.ErrorCode.USER_DECLINED, -12, "USER_DECLINED")
	_assert_eq(MWATypes.ErrorCode.NOT_INITIALIZED, -13, "NOT_INITIALIZED")


func test_connection_state_enum() -> void:
	_start("ConnectionState enum")
	_assert_eq(MWATypes.ConnectionState.DISCONNECTED, 0, "DISCONNECTED")
	_assert_eq(MWATypes.ConnectionState.CONNECTING, 1, "CONNECTING")
	_assert_eq(MWATypes.ConnectionState.CONNECTED, 2, "CONNECTED")
	_assert_eq(MWATypes.ConnectionState.SIGNING, 3, "SIGNING")
	_assert_eq(MWATypes.ConnectionState.DEAUTHORIZING, 4, "DEAUTHORIZING")


# --- Utility Function Tests ---

func test_cluster_to_chain() -> void:
	_start("cluster_to_chain")
	_assert_eq(MWATypes.cluster_to_chain(MWATypes.Cluster.DEVNET), "solana:devnet", "devnet")
	_assert_eq(MWATypes.cluster_to_chain(MWATypes.Cluster.MAINNET), "solana:mainnet", "mainnet")
	_assert_eq(MWATypes.cluster_to_chain(MWATypes.Cluster.TESTNET), "solana:testnet", "testnet")


func test_chain_to_cluster() -> void:
	_start("chain_to_cluster")
	_assert_eq(MWATypes.chain_to_cluster("solana:devnet"), MWATypes.Cluster.DEVNET, "devnet")
	_assert_eq(MWATypes.chain_to_cluster("solana:mainnet"), MWATypes.Cluster.MAINNET, "mainnet")
	_assert_eq(MWATypes.chain_to_cluster("solana:testnet"), MWATypes.Cluster.TESTNET, "testnet")


func test_cluster_to_chain_unknown_returns_mainnet() -> void:
	_start("cluster_to_chain unknown defaults to mainnet")
	_assert_eq(MWATypes.cluster_to_chain(99), "solana:mainnet", "unknown cluster")


# --- Result Tests ---

func test_result_ok() -> void:
	_start("Result.ok()")
	var r := MWATypes.Result.ok("test_data")
	_assert_true(r.success, "success is true")
	_assert_eq(r.data, "test_data", "data matches")
	_assert_eq(r.error_code, 0, "error_code is 0")
	_assert_eq(r.error_message, "", "error_message is empty")


func test_result_err() -> void:
	_start("Result.err()")
	var r := MWATypes.Result.err(-12, "User declined")
	_assert_false(r.success, "success is false")
	_assert_null(r.data, "data is null")
	_assert_eq(r.error_code, -12, "error_code matches")
	_assert_eq(r.error_message, "User declined", "error_message matches")


# --- Account Tests ---

func test_account_to_dict() -> void:
	_start("Account.to_dict()")
	var acc := MWATypes.Account.new(
		"ABC123pubkey",
		PackedByteArray([1, 2, 3, 4]),
		"Test Wallet",
		"icon.png",
		PackedStringArray(["solana:devnet"]),
		PackedStringArray(["sign"])
	)
	var d := acc.to_dict()
	_assert_eq(d["address"], "ABC123pubkey", "address")
	_assert_eq(d["label"], "Test Wallet", "label")
	_assert_eq(d["icon"], "icon.png", "icon")
	_assert_true(d["public_key"] is String, "public_key is base64 string")
	_assert_eq(d["public_key"], Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4])), "public_key base64")


func test_account_from_dict() -> void:
	_start("Account.from_dict()")
	var d := {
		"address": "TestAddr",
		"public_key": Marshalls.raw_to_base64(PackedByteArray([5, 6, 7])),
		"label": "My Account",
		"icon": "wallet.png",
		"chains": PackedStringArray(["solana:mainnet"]),
		"features": PackedStringArray(["sign", "send"]),
	}
	var acc := MWATypes.Account.from_dict(d)
	_assert_eq(acc.address, "TestAddr", "address")
	_assert_eq(acc.public_key, PackedByteArray([5, 6, 7]), "public_key decoded")
	_assert_eq(acc.label, "My Account", "label")
	_assert_eq(acc.icon, "wallet.png", "icon")


func test_account_roundtrip() -> void:
	_start("Account roundtrip")
	var original := MWATypes.Account.new(
		"RoundtripAddr",
		PackedByteArray([10, 20, 30, 40, 50]),
		"Roundtrip",
		"rt.png",
		PackedStringArray(["solana:testnet"]),
		PackedStringArray(["feature1"])
	)
	var restored := MWATypes.Account.from_dict(original.to_dict())
	_assert_eq(restored.address, original.address, "address preserved")
	_assert_eq(restored.public_key, original.public_key, "public_key preserved")
	_assert_eq(restored.label, original.label, "label preserved")


func test_account_empty_public_key() -> void:
	_start("Account with empty public_key")
	var d := {"address": "Addr", "public_key": ""}
	var acc := MWATypes.Account.from_dict(d)
	_assert_eq(acc.address, "Addr", "address set")
	_assert_eq(acc.public_key, PackedByteArray(), "empty public_key")


# --- AuthorizationResult Tests ---

func test_authorization_result_to_dict() -> void:
	_start("AuthorizationResult.to_dict()")
	var auth := MWATypes.AuthorizationResult.new()
	auth.auth_token = "test_token_123"
	auth.wallet_uri_base = "https://phantom.app"
	var acc := MWATypes.Account.new("Addr1", PackedByteArray([1, 2, 3]))
	auth.accounts = [acc]
	var d := auth.to_dict()
	_assert_eq(d["auth_token"], "test_token_123", "auth_token")
	_assert_eq(d["wallet_uri_base"], "https://phantom.app", "wallet_uri_base")
	_assert_eq(d["accounts"].size(), 1, "accounts count")


func test_authorization_result_from_dict() -> void:
	_start("AuthorizationResult.from_dict()")
	var d := {
		"auth_token": "restored_token",
		"wallet_uri_base": "https://solflare.com",
		"accounts": [
			{"address": "Acc1", "public_key": Marshalls.raw_to_base64(PackedByteArray([9, 8, 7]))},
			{"address": "Acc2", "public_key": Marshalls.raw_to_base64(PackedByteArray([6, 5, 4]))},
		],
		"sign_in_result": {"signed": true},
	}
	var auth := MWATypes.AuthorizationResult.from_dict(d)
	_assert_eq(auth.auth_token, "restored_token", "auth_token")
	_assert_eq(auth.wallet_uri_base, "https://solflare.com", "wallet_uri_base")
	_assert_eq(auth.accounts.size(), 2, "accounts count")
	_assert_eq(auth.accounts[0].address, "Acc1", "first account address")
	_assert_eq(auth.accounts[1].public_key, PackedByteArray([6, 5, 4]), "second account pubkey")


func test_authorization_result_roundtrip() -> void:
	_start("AuthorizationResult roundtrip")
	var original := MWATypes.AuthorizationResult.new()
	original.auth_token = "roundtrip_token"
	original.wallet_uri_base = "https://test.wallet"
	original.accounts = [
		MWATypes.Account.new("RT1", PackedByteArray([11, 22, 33]))
	]
	var restored := MWATypes.AuthorizationResult.from_dict(original.to_dict())
	_assert_eq(restored.auth_token, original.auth_token, "auth_token preserved")
	_assert_eq(restored.accounts.size(), 1, "accounts count preserved")
	_assert_eq(restored.accounts[0].address, "RT1", "account address preserved")


func test_authorization_result_empty_accounts() -> void:
	_start("AuthorizationResult with no accounts")
	var d := {"auth_token": "tok", "wallet_uri_base": "", "accounts": []}
	var auth := MWATypes.AuthorizationResult.from_dict(d)
	_assert_eq(auth.accounts.size(), 0, "empty accounts array")
	_assert_eq(auth.auth_token, "tok", "auth_token still set")


# --- DappIdentity Tests ---

func test_dapp_identity_defaults() -> void:
	_start("DappIdentity defaults")
	var id := MWATypes.DappIdentity.new()
	_assert_eq(id.name, "Godot dApp", "default name")
	_assert_eq(id.uri, "https://solana.com", "default uri")
	_assert_eq(id.icon, "icon.png", "default icon")


func test_dapp_identity_custom() -> void:
	_start("DappIdentity custom")
	var id := MWATypes.DappIdentity.new("My Game", "https://mygame.io", "game.png")
	_assert_eq(id.name, "My Game", "custom name")
	_assert_eq(id.uri, "https://mygame.io", "custom uri")
	_assert_eq(id.icon, "game.png", "custom icon")


# --- SendOptions Tests ---

func test_send_options_defaults() -> void:
	_start("SendOptions defaults")
	var opts := MWATypes.SendOptions.new()
	_assert_eq(opts.commitment, "confirmed", "default commitment")
	_assert_false(opts.skip_preflight, "default skip_preflight")
	_assert_eq(opts.min_context_slot, -1, "default min_context_slot")
	_assert_eq(opts.max_retries, -1, "default max_retries")
	_assert_false(opts.wait_for_commitment_to_send_next_transaction, "default wait_for_commitment")


func test_send_options_to_dict() -> void:
	_start("SendOptions.to_dict()")
	var opts := MWATypes.SendOptions.new()
	opts.commitment = "finalized"
	opts.skip_preflight = true
	opts.min_context_slot = 100
	opts.max_retries = 3
	var d := opts.to_dict()
	_assert_eq(d["commitment"], "finalized", "commitment")
	_assert_true(d["skip_preflight"], "skip_preflight")
	_assert_eq(d["min_context_slot"], 100, "min_context_slot included")
	_assert_eq(d["max_retries"], 3, "max_retries included")


func test_send_options_min_context_slot_excluded() -> void:
	_start("SendOptions excludes negative min_context_slot")
	var opts := MWATypes.SendOptions.new()
	var d := opts.to_dict()
	_assert_false(d.has("min_context_slot"), "min_context_slot excluded when -1")
	_assert_false(d.has("max_retries"), "max_retries excluded when -1")


# --- SignInPayload Tests ---

func test_sign_in_payload_empty() -> void:
	_start("SignInPayload empty to_dict")
	var sip := MWATypes.SignInPayload.new()
	var d := sip.to_dict()
	_assert_eq(d.size(), 0, "empty payload produces empty dict")


func test_sign_in_payload_populated() -> void:
	_start("SignInPayload populated")
	var sip := MWATypes.SignInPayload.new()
	sip.domain = "mygame.com"
	sip.statement = "Sign in to My Game"
	sip.uri = "https://mygame.com"
	sip.version = "1"
	sip.nonce = "abc123"
	sip.issued_at = "2025-01-01T00:00:00Z"
	sip.resources = PackedStringArray(["https://mygame.com/tos"])
	var d := sip.to_dict()
	_assert_eq(d["domain"], "mygame.com", "domain")
	_assert_eq(d["statement"], "Sign in to My Game", "statement")
	_assert_eq(d["uri"], "https://mygame.com", "uri")
	_assert_eq(d["version"], "1", "version")
	_assert_eq(d["nonce"], "abc123", "nonce")
	_assert_true(d.has("resources"), "resources present")


func test_sign_in_payload_partial() -> void:
	_start("SignInPayload partial fields")
	var sip := MWATypes.SignInPayload.new()
	sip.domain = "test.com"
	var d := sip.to_dict()
	_assert_eq(d.size(), 1, "only domain present")
	_assert_eq(d["domain"], "test.com", "domain value")
	_assert_false(d.has("statement"), "statement absent")
	_assert_false(d.has("nonce"), "nonce absent")


# --- WalletCapabilities Tests ---

func test_wallet_capabilities_defaults() -> void:
	_start("WalletCapabilities defaults")
	var caps := MWATypes.WalletCapabilities.new()
	_assert_false(caps.supports_clone_authorization, "default clone")
	_assert_false(caps.supports_sign_and_send_transactions, "default sign_and_send")
	_assert_eq(caps.max_transactions_per_request, 0, "default max_tx")
	_assert_eq(caps.max_messages_per_request, 0, "default max_msg")
