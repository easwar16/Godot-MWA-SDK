class_name MobileWalletAdapter
extends Node
## Main Mobile Wallet Adapter class.
## Provides full MWA 2.0 API parity with the React Native SDK.
##
## Usage:
##   var mwa = MobileWalletAdapter.new()
##   mwa.identity = MWATypes.DappIdentity.new("My App", "https://myapp.com", "icon.png")
##   mwa.cluster = MWATypes.Cluster.DEVNET
##   add_child(mwa)
##   mwa.authorize()

# --- Signals (match React Native SDK events) ---

signal authorized(result)
signal authorization_failed(error_code: int, error_message: String)
signal deauthorized()
signal deauthorization_failed(error_message: String)
signal capabilities_received(capabilities)
signal capabilities_failed(error_code: int, error_message: String)
signal transactions_signed(signed_payloads: Array)
signal transactions_sign_failed(error_code: int, error_message: String)
signal transactions_sent(signatures: Array)
signal transactions_send_failed(error_code: int, error_message: String)
signal messages_signed(signatures: Array)
signal messages_sign_failed(error_code: int, error_message: String)
signal authorization_cloned(auth_token: String)
signal clone_failed(error_message: String)
signal state_changed(new_state: int)
signal debug_log(message: String)

# --- Properties ---

## Dapp identity presented to wallet during authorization.
var identity = MWATypes.DappIdentity.new()

## Blockchain cluster to connect to.
var cluster: int = MWATypes.Cluster.DEVNET

## Authorization cache implementation. Defaults to MWAFileCache.
var auth_cache: MWACache = MWAFileCache.new()

## Current connection state.
var state: int = MWATypes.ConnectionState.DISCONNECTED:
	set(value):
		if state != value:
			state = value
			state_changed.emit(state)

## Current authorization result (populated after authorize/reauthorize).
var current_auth = null

## Last queried wallet capabilities.
var capabilities = null

## Timeout in seconds for wallet operations.
var timeout_seconds: float = 30.0:
	set(value):
		timeout_seconds = value
		if _android_plugin != null:
			_android_plugin.call("setTimeoutMs", int(value * 1000))

## Enable verbose debug logging.
var debug_logging: bool = false

# --- Private ---

var _android_plugin: Object = null
var _poll_action: String = ""  # What we're currently polling for
var _busy: bool = false
var _poll_start_time: float = 0.0


# --- Helper Methods ---

## Returns true if an operation is currently in progress.
func is_busy() -> bool:
	return _busy

func _log_debug(msg: String) -> void:
	if debug_logging:
		print("[MWA] ", msg)
		debug_log.emit(msg)

func _start_operation(action: String) -> void:
	_busy = true
	_poll_action = action
	_poll_start_time = Time.get_ticks_msec() / 1000.0
	_log_debug("%s started" % action)

func _end_operation() -> void:
	_busy = false
	_poll_action = ""
	_log_debug("operation completed")
	# Re-emit state so UI can refresh button states after busy clears.
	state_changed.emit(state)


func _ready() -> void:
	if Engine.has_singleton("SolanaMWA"):
		_android_plugin = Engine.get_singleton("SolanaMWA")
	elif OS.get_name() == "Android":
		push_warning("MobileWalletAdapter: SolanaMWA Android plugin not found. Did you include the .aar?")

	if _android_plugin != null:
		_android_plugin.call("setTimeoutMs", int(timeout_seconds * 1000))

	# Try to restore cached authorization.
	if auth_cache != null:
		var cached := auth_cache.get_authorization()
		if cached != null and cached.auth_token != "":
			current_auth = cached


func _process(delta: float) -> void:
	if _poll_action == "" or _android_plugin == null:
		return
	_poll_android_status()

	# Safety timeout — if Kotlin side didn't respond
	if _busy and (Time.get_ticks_msec() / 1000.0 - _poll_start_time) > timeout_seconds + 5.0:
		_log_debug("GDScript-side safety timeout triggered")
		_force_timeout()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_log_debug("App paused")
		NOTIFICATION_APPLICATION_RESUMED:
			_log_debug("App resumed")


func _force_timeout() -> void:
	var action := _poll_action
	_end_operation()
	if _android_plugin != null:
		_android_plugin.call("clearState")
	match action:
		"authorize":
			authorization_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"deauthorize":
			deauthorization_failed.emit("Operation timed out")
		"get_capabilities":
			capabilities_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"sign_transactions":
			transactions_sign_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"sign_and_send_transactions":
			transactions_send_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"sign_messages":
			messages_sign_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"authorize_and_sign_transactions":
			authorization_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
			transactions_sign_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"authorize_and_sign_and_send_transactions":
			authorization_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
			transactions_send_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
		"authorize_and_sign_messages":
			authorization_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")
			messages_sign_failed.emit(MWATypes.ErrorCode.TIMEOUT, "Operation timed out")


# ===================================================================
# PUBLIC API — Full MWA 2.0 parity with React Native SDK
# ===================================================================

## Authorize this dapp with a wallet. If a cached auth_token exists, attempts
## reauthorization first. Equivalent to React Native's transact → authorize().
func authorize(sign_in_payload = null) -> void:
	if _android_plugin == null:
		authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Android plugin not available")
		return

	if _busy:
		authorization_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	state = MWATypes.ConnectionState.CONNECTING

	var cached_token := ""
	if current_auth != null and current_auth.auth_token != "":
		cached_token = current_auth.auth_token

	var sign_in_json := ""
	if sign_in_payload != null:
		sign_in_json = JSON.stringify(sign_in_payload.to_dict())

	_android_plugin.call(
		"authorize",
		identity.uri,
		identity.icon,
		identity.name,
		MWATypes.cluster_to_chain(cluster),
		cached_token,
		sign_in_json,
	)
	_start_operation("authorize")


## Deauthorize and disconnect from the wallet. Invalidates the auth token.
## Equivalent to React Native's transact → deauthorize().
func deauthorize() -> void:
	if _android_plugin == null:
		deauthorization_failed.emit("Android plugin not available")
		return

	if _busy:
		deauthorization_failed.emit("Another operation is in progress")
		return

	if current_auth == null or current_auth.auth_token == "":
		# Nothing to deauthorize, just clean up.
		_clear_auth()
		deauthorized.emit()
		return

	state = MWATypes.ConnectionState.DEAUTHORIZING
	_android_plugin.call("deauthorize", identity.uri, identity.icon, identity.name, MWATypes.cluster_to_chain(cluster), current_auth.auth_token)
	_start_operation("deauthorize")


## Disconnect from wallet. Alias for deauthorize() that also clears local state.
func disconnect_wallet() -> void:
	deauthorize()


## Reconnect to wallet using cached authorization. If cache is empty, performs
## full authorize.
func reconnect() -> void:
	if auth_cache != null:
		var cached := auth_cache.get_authorization()
		if cached != null and cached.auth_token != "":
			current_auth = cached
	authorize()


## Query wallet capabilities. Returns supported features and limits.
## Equivalent to React Native's transact → getCapabilities().
func get_capabilities() -> void:
	if _android_plugin == null:
		capabilities_failed.emit(MWATypes.ErrorCode.BUSY, "Android plugin not available")
		return

	if _busy:
		capabilities_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	var auth_token := ""
	if current_auth != null and current_auth.auth_token != "":
		auth_token = current_auth.auth_token

	_android_plugin.call("getCapabilities", identity.uri, identity.icon, identity.name, MWATypes.cluster_to_chain(cluster), auth_token)
	_start_operation("get_capabilities")


## Sign one or more transactions. Wallet signs but does NOT submit to network.
## Equivalent to React Native's transact → signTransactions().
func sign_transactions(payloads: Array) -> void:
	if _android_plugin == null:
		transactions_sign_failed.emit(MWATypes.ErrorCode.NOT_SIGNED, "Android plugin not available")
		return

	if _busy:
		transactions_sign_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	if current_auth == null or current_auth.auth_token == "":
		transactions_sign_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Not authorized. Call authorize() first.")
		return

	state = MWATypes.ConnectionState.SIGNING

	var encoded: PackedStringArray = []
	for payload in payloads:
		encoded.append(Marshalls.raw_to_base64(payload))

	_android_plugin.call("signTransactions", identity.uri, identity.icon, identity.name, MWATypes.cluster_to_chain(cluster), current_auth.auth_token, encoded)
	_start_operation("sign_transactions")


## Sign and send one or more transactions. Wallet signs AND submits to network.
## Equivalent to React Native's transact → signAndSendTransactions().
func sign_and_send_transactions(payloads: Array, options = null) -> void:
	if _android_plugin == null:
		transactions_send_failed.emit(MWATypes.ErrorCode.NOT_SUBMITTED, "Android plugin not available")
		return

	if _busy:
		transactions_send_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	if current_auth == null or current_auth.auth_token == "":
		transactions_send_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Not authorized. Call authorize() first.")
		return

	state = MWATypes.ConnectionState.SIGNING

	var encoded: PackedStringArray = []
	for payload in payloads:
		encoded.append(Marshalls.raw_to_base64(payload))

	var options_json := ""
	if options != null:
		options_json = JSON.stringify(options.to_dict())

	_android_plugin.call("signAndSendTransactions", identity.uri, identity.icon, identity.name, MWATypes.cluster_to_chain(cluster), current_auth.auth_token, encoded, options_json)
	_start_operation("sign_and_send_transactions")


## Sign one or more arbitrary messages.
## Equivalent to React Native's transact → signMessages().
func sign_messages(messages: Array, addresses: PackedStringArray = []) -> void:
	if _android_plugin == null:
		messages_sign_failed.emit(MWATypes.ErrorCode.NOT_SIGNED, "Android plugin not available")
		return

	if _busy:
		messages_sign_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	if current_auth == null or current_auth.auth_token == "":
		messages_sign_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Not authorized. Call authorize() first.")
		return

	state = MWATypes.ConnectionState.SIGNING

	var encoded: PackedStringArray = []
	for msg in messages:
		encoded.append(Marshalls.raw_to_base64(msg))

	# Default to first authorized account address if none specified.
	if addresses.is_empty() and current_auth.accounts.size() > 0:
		addresses.append(current_auth.accounts[0].address)

	_android_plugin.call("signMessages", identity.uri, identity.icon, identity.name, MWATypes.cluster_to_chain(cluster), current_auth.auth_token, encoded, addresses)
	_start_operation("sign_messages")


## Clone the current authorization for use in another session.
## Note: cloneAuthorization is deprecated in MWA 2.0 client library.
func clone_authorization() -> void:
	clone_failed.emit("cloneAuthorization is not supported in MWA 2.0")


## Check if we have a valid (cached or active) authorization.
func is_authorized() -> bool:
	return current_auth != null and current_auth.auth_token != ""


## Check if currently connected (authorized with active session).
func is_wallet_connected() -> bool:
	return state == MWATypes.ConnectionState.CONNECTED and is_authorized()


## Get the primary authorized account, or null.
func get_account():
	if current_auth != null and current_auth.accounts.size() > 0:
		return current_auth.accounts[0]
	return null


## Get all authorized accounts.
func get_accounts() -> Array:
	if current_auth != null:
		return current_auth.accounts
	return []


## Get the public key of the primary authorized account.
func get_public_key() -> PackedByteArray:
	var acc = get_account()
	if acc != null:
		return acc.public_key
	return PackedByteArray()


## Replace the cache implementation at runtime.
func set_cache(cache: MWACache) -> void:
	auth_cache = cache
	# Reload from new cache.
	if auth_cache != null:
		var cached := auth_cache.get_authorization()
		if cached != null and cached.auth_token != "":
			current_auth = cached


# ===================================================================
# COMBINED AUTHORIZE + OPERATION METHODS
# ===================================================================

## Authorize and sign transactions in a single wallet session.
## Emits authorized() then transactions_signed() on success.
func authorize_and_sign_transactions(payloads: Array, sign_in_payload = null) -> void:
	if _android_plugin == null:
		authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Android plugin not available")
		return
	if _busy:
		authorization_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	state = MWATypes.ConnectionState.CONNECTING

	var cached_token := ""
	if current_auth != null and current_auth.auth_token != "":
		cached_token = current_auth.auth_token

	var sign_in_json := ""
	if sign_in_payload != null:
		sign_in_json = JSON.stringify(sign_in_payload.to_dict())

	var encoded: PackedStringArray = []
	for payload in payloads:
		encoded.append(Marshalls.raw_to_base64(payload))

	_android_plugin.call("authorizeAndSignTransactions",
		identity.uri, identity.icon, identity.name,
		MWATypes.cluster_to_chain(cluster), cached_token, sign_in_json, encoded)
	_start_operation("authorize_and_sign_transactions")


## Authorize and sign+send transactions in a single wallet session.
## Emits authorized() then transactions_sent() on success.
func authorize_and_sign_and_send_transactions(payloads: Array, sign_in_payload = null, options = null) -> void:
	if _android_plugin == null:
		authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Android plugin not available")
		return
	if _busy:
		authorization_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	state = MWATypes.ConnectionState.CONNECTING

	var cached_token := ""
	if current_auth != null and current_auth.auth_token != "":
		cached_token = current_auth.auth_token

	var sign_in_json := ""
	if sign_in_payload != null:
		sign_in_json = JSON.stringify(sign_in_payload.to_dict())

	var encoded: PackedStringArray = []
	for payload in payloads:
		encoded.append(Marshalls.raw_to_base64(payload))

	var options_json := ""
	if options != null:
		options_json = JSON.stringify(options.to_dict())

	_android_plugin.call("authorizeAndSignAndSendTransactions",
		identity.uri, identity.icon, identity.name,
		MWATypes.cluster_to_chain(cluster), cached_token, sign_in_json, encoded, options_json)
	_start_operation("authorize_and_sign_and_send_transactions")


## Authorize and sign messages in a single wallet session.
## Emits authorized() then messages_signed() on success.
func authorize_and_sign_messages(messages_to_sign: Array, addresses: PackedStringArray = [], sign_in_payload = null) -> void:
	if _android_plugin == null:
		authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Android plugin not available")
		return
	if _busy:
		authorization_failed.emit(MWATypes.ErrorCode.BUSY, "Another operation is in progress")
		return

	state = MWATypes.ConnectionState.CONNECTING

	var cached_token := ""
	if current_auth != null and current_auth.auth_token != "":
		cached_token = current_auth.auth_token

	var sign_in_json := ""
	if sign_in_payload != null:
		sign_in_json = JSON.stringify(sign_in_payload.to_dict())

	var encoded: PackedStringArray = []
	for msg in messages_to_sign:
		encoded.append(Marshalls.raw_to_base64(msg))

	_android_plugin.call("authorizeAndSignMessages",
		identity.uri, identity.icon, identity.name,
		MWATypes.cluster_to_chain(cluster), cached_token, sign_in_json, encoded, addresses)
	_start_operation("authorize_and_sign_messages")


# ===================================================================
# ASYNC WRAPPERS — for GDScript 4 await usage
# ===================================================================

func _race_signals(success_signal: Signal, fail_signal: Signal) -> Array:
	var result := []
	var done := false
	var on_success := func(arg1 = null, arg2 = null):
		if not done:
			done = true
			result = [true, arg1, arg2]
	var on_fail := func(arg1 = null, arg2 = null):
		if not done:
			done = true
			result = [false, arg1, arg2]
	success_signal.connect(on_success, CONNECT_ONE_SHOT)
	fail_signal.connect(on_fail, CONNECT_ONE_SHOT)
	while not done:
		await get_tree().process_frame
	return result

## Authorize and await the result.
func authorize_async(sign_in_payload = null) -> MWATypes.Result:
	authorize(sign_in_payload)
	var r = await _race_signals(authorized, authorization_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])

## Deauthorize and await the result.
func deauthorize_async() -> MWATypes.Result:
	deauthorize()
	var r = await _race_signals(deauthorized, deauthorization_failed)
	if r[0]:
		return MWATypes.Result.ok(null)
	else:
		return MWATypes.Result.err(0, r[1])

## Sign transactions and await the result.
func sign_transactions_async(payloads: Array) -> MWATypes.Result:
	sign_transactions(payloads)
	var r = await _race_signals(transactions_signed, transactions_sign_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])

## Sign and send transactions and await the result.
func sign_and_send_transactions_async(payloads: Array, options = null) -> MWATypes.Result:
	sign_and_send_transactions(payloads, options)
	var r = await _race_signals(transactions_sent, transactions_send_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])

## Sign messages and await the result.
func sign_messages_async(messages: Array, addresses: PackedStringArray = []) -> MWATypes.Result:
	sign_messages(messages, addresses)
	var r = await _race_signals(messages_signed, messages_sign_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])

## Get capabilities and await the result.
func get_capabilities_async() -> MWATypes.Result:
	get_capabilities()
	var r = await _race_signals(capabilities_received, capabilities_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])


## Authorize and sign transactions in a single session, await the result.
func authorize_and_sign_transactions_async(payloads: Array, sign_in_payload = null) -> MWATypes.Result:
	authorize_and_sign_transactions(payloads, sign_in_payload)
	var r = await _race_signals(transactions_signed, authorization_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])


## Authorize and sign+send transactions in a single session, await the result.
func authorize_and_sign_and_send_transactions_async(payloads: Array, options = null, sign_in_payload = null) -> MWATypes.Result:
	authorize_and_sign_and_send_transactions(payloads, options, sign_in_payload)
	var r = await _race_signals(transactions_sent, authorization_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])


## Authorize and sign messages in a single session, await the result.
func authorize_and_sign_messages_async(messages: Array, addresses: PackedStringArray = [], sign_in_payload = null) -> MWATypes.Result:
	authorize_and_sign_messages(messages, addresses, sign_in_payload)
	var r = await _race_signals(messages_signed, authorization_failed)
	if r[0]:
		return MWATypes.Result.ok(r[1])
	else:
		return MWATypes.Result.err(r[1], r[2])


# ===================================================================
# ANDROID POLLING
# ===================================================================

func _poll_android_status() -> void:
	var status: int = _android_plugin.call("getStatus")

	# 0 = pending, skip
	if status == 0:
		return

	var action := _poll_action
	_poll_action = ""

	match action:
		"authorize":
			_handle_authorize_result(status)
		"deauthorize":
			_handle_deauthorize_result(status)
		"get_capabilities":
			_handle_capabilities_result(status)
		"sign_transactions":
			_handle_sign_transactions_result(status)
		"sign_and_send_transactions":
			_handle_sign_and_send_result(status)
		"sign_messages":
			_handle_sign_messages_result(status)
		"clone_authorization":
			_handle_clone_result(status)
		"authorize_and_sign_transactions":
			_handle_authorize_and_sign_transactions_result(status)
		"authorize_and_sign_and_send_transactions":
			_handle_authorize_and_sign_and_send_result(status)
		"authorize_and_sign_messages":
			_handle_authorize_and_sign_messages_result(status)


func _handle_authorize_result(status: int) -> void:
	if status == 1:  # Success
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			current_auth = MWATypes.AuthorizationResult.from_dict(data)
			if auth_cache != null:
				auth_cache.set_authorization(current_auth)
			state = MWATypes.ConnectionState.CONNECTED
			authorized.emit(current_auth)
		else:
			state = MWATypes.ConnectionState.DISCONNECTED
			authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Failed to parse auth result")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		state = MWATypes.ConnectionState.DISCONNECTED
		authorization_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_deauthorize_result(status: int) -> void:
	_clear_auth()
	if status == 1:
		deauthorized.emit()
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		deauthorization_failed.emit(error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_capabilities_result(status: int) -> void:
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			capabilities = MWATypes.WalletCapabilities.new()
			capabilities.supports_clone_authorization = data.get("supports_clone_authorization", false)
			capabilities.supports_sign_and_send_transactions = data.get("supports_sign_and_send_transactions", false)
			capabilities.max_transactions_per_request = data.get("max_transactions_per_request", 0)
			capabilities.max_messages_per_request = data.get("max_messages_per_request", 0)
			capabilities.supported_transaction_versions = data.get("supported_transaction_versions", PackedStringArray())
			capabilities.features = data.get("features", PackedStringArray())
			capabilities_received.emit(capabilities)
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		capabilities_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_sign_transactions_result(status: int) -> void:
	state = MWATypes.ConnectionState.CONNECTED
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			var signed_b64: Array = data.get("signed_payloads", [])
			var signed: Array = []
			for b64 in signed_b64:
				signed.append(Marshalls.base64_to_raw(b64))
			transactions_signed.emit(signed)
		else:
			transactions_sign_failed.emit(MWATypes.ErrorCode.NOT_SIGNED, "Failed to parse signed transactions")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		transactions_sign_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_sign_and_send_result(status: int) -> void:
	state = MWATypes.ConnectionState.CONNECTED
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			var sig_b64: Array = data.get("signatures", [])
			var sigs: Array = []
			for b64 in sig_b64:
				sigs.append(Marshalls.base64_to_raw(b64))
			transactions_sent.emit(sigs)
		else:
			transactions_send_failed.emit(MWATypes.ErrorCode.NOT_SUBMITTED, "Failed to parse send result")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		transactions_send_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_sign_messages_result(status: int) -> void:
	state = MWATypes.ConnectionState.CONNECTED
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			var sig_b64: Array = data.get("signatures", [])
			var sigs: Array = []
			for b64 in sig_b64:
				sigs.append(Marshalls.base64_to_raw(b64))
			messages_signed.emit(sigs)
		else:
			messages_sign_failed.emit(MWATypes.ErrorCode.NOT_SIGNED, "Failed to parse message signatures")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		messages_sign_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_clone_result(status: int) -> void:
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			authorization_cloned.emit(data.get("auth_token", ""))
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		clone_failed.emit(error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_authorize_and_sign_transactions_result(status: int) -> void:
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			current_auth = MWATypes.AuthorizationResult.from_dict(data)
			if auth_cache != null:
				auth_cache.set_authorization(current_auth)
			state = MWATypes.ConnectionState.CONNECTED
			authorized.emit(current_auth)
			# Also emit signed payloads
			var signed_b64: Array = data.get("signed_payloads", [])
			var signed: Array = []
			for b64 in signed_b64:
				signed.append(Marshalls.base64_to_raw(b64))
			transactions_signed.emit(signed)
		else:
			state = MWATypes.ConnectionState.DISCONNECTED
			authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Failed to parse result")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		state = MWATypes.ConnectionState.DISCONNECTED
		authorization_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_authorize_and_sign_and_send_result(status: int) -> void:
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			current_auth = MWATypes.AuthorizationResult.from_dict(data)
			if auth_cache != null:
				auth_cache.set_authorization(current_auth)
			state = MWATypes.ConnectionState.CONNECTED
			authorized.emit(current_auth)
			# Also emit signatures
			var sig_b64: Array = data.get("signatures", [])
			var sigs: Array = []
			for b64 in sig_b64:
				sigs.append(Marshalls.base64_to_raw(b64))
			transactions_sent.emit(sigs)
		else:
			state = MWATypes.ConnectionState.DISCONNECTED
			authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Failed to parse result")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		state = MWATypes.ConnectionState.DISCONNECTED
		authorization_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _handle_authorize_and_sign_messages_result(status: int) -> void:
	if status == 1:
		var result_json: String = _android_plugin.call("getResultJson")
		var json := JSON.new()
		if json.parse(result_json) == OK:
			var data: Dictionary = json.data
			current_auth = MWATypes.AuthorizationResult.from_dict(data)
			if auth_cache != null:
				auth_cache.set_authorization(current_auth)
			state = MWATypes.ConnectionState.CONNECTED
			authorized.emit(current_auth)
			# Also emit signatures
			var sig_b64: Array = data.get("signatures", [])
			var sigs: Array = []
			for b64 in sig_b64:
				sigs.append(Marshalls.base64_to_raw(b64))
			messages_signed.emit(sigs)
		else:
			state = MWATypes.ConnectionState.DISCONNECTED
			authorization_failed.emit(MWATypes.ErrorCode.AUTHORIZATION_FAILED, "Failed to parse result")
	else:
		var error_msg: String = _android_plugin.call("getErrorMessage")
		var error_code: int = _android_plugin.call("getErrorCode")
		state = MWATypes.ConnectionState.DISCONNECTED
		authorization_failed.emit(error_code, error_msg)
	_android_plugin.call("clearState")
	_end_operation()


func _clear_auth() -> void:
	current_auth = null
	if auth_cache != null:
		auth_cache.clear()
	state = MWATypes.ConnectionState.DISCONNECTED
