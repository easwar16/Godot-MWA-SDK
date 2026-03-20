extends Control
## Example app demonstrating all MWA SDK methods and authorization cache.

@onready var status_label: Label = %StatusLabel
@onready var pubkey_label: Label = %PubkeyLabel
@onready var output_log: RichTextLabel = %OutputLog
@onready var cluster_option: OptionButton = %ClusterOption
@onready var connect_btn: Button = %ConnectBtn
@onready var disconnect_btn: Button = %DisconnectBtn
@onready var reconnect_btn: Button = %ReconnectBtn
@onready var capabilities_btn: Button = %CapabilitiesBtn
@onready var sign_tx_btn: Button = %SignTxBtn
@onready var sign_send_btn: Button = %SignSendBtn
@onready var sign_msg_btn: Button = %SignMsgBtn
@onready var clone_auth_btn: Button = %CloneAuthBtn
@onready var clear_cache_btn: Button = %ClearCacheBtn

var adapter: MobileWalletAdapter


func _ready() -> void:
	adapter = MWA.adapter

	# Configure dapp identity.
	adapter.identity = MWATypes.DappIdentity.new(
		"MWA SDK Demo",
		"https://solanamobile.com",
		"icon.png"
	)

	# Enable debug logging.
	adapter.debug_logging = true
	adapter.debug_log.connect(func(msg): _log("[color=gray][DEBUG] %s[/color]" % msg))

	# Connect signals.
	adapter.authorized.connect(_on_authorized)
	adapter.authorization_failed.connect(_on_auth_failed)
	adapter.deauthorized.connect(_on_deauthorized)
	adapter.deauthorization_failed.connect(_on_deauth_failed)
	adapter.capabilities_received.connect(_on_capabilities)
	adapter.capabilities_failed.connect(_on_capabilities_failed)
	adapter.transactions_signed.connect(_on_tx_signed)
	adapter.transactions_sign_failed.connect(_on_tx_sign_failed)
	adapter.transactions_sent.connect(_on_tx_sent)
	adapter.transactions_send_failed.connect(_on_tx_send_failed)
	adapter.messages_signed.connect(_on_msg_signed)
	adapter.messages_sign_failed.connect(_on_msg_sign_failed)
	adapter.authorization_cloned.connect(_on_auth_cloned)
	adapter.clone_failed.connect(_on_clone_failed)
	adapter.state_changed.connect(_on_state_changed)

	# Cluster selector.
	cluster_option.add_item("Devnet", MWATypes.Cluster.DEVNET)
	cluster_option.add_item("Mainnet", MWATypes.Cluster.MAINNET)
	cluster_option.add_item("Testnet", MWATypes.Cluster.TESTNET)
	cluster_option.selected = 0

	# Button connections.
	connect_btn.pressed.connect(_on_connect)
	disconnect_btn.pressed.connect(_on_disconnect)
	reconnect_btn.pressed.connect(_on_reconnect)
	capabilities_btn.pressed.connect(_on_get_capabilities)
	sign_tx_btn.pressed.connect(_on_sign_transaction)
	sign_send_btn.pressed.connect(_on_sign_and_send)
	sign_msg_btn.pressed.connect(_on_sign_message)
	clone_auth_btn.pressed.connect(_on_clone_auth)
	clear_cache_btn.pressed.connect(_on_clear_cache)

	_update_ui()
	_log("MWA SDK Demo ready. Select a cluster and connect.")

	# Show cache status.
	if adapter.auth_cache.has_authorization():
		_log("Found cached authorization. Use 'Reconnect' to restore session.")


func _on_connect() -> void:
	adapter.cluster = cluster_option.get_selected_id() as MWATypes.Cluster
	_log("Authorizing on %s..." % MWATypes.cluster_to_chain(adapter.cluster))
	adapter.authorize()


func _on_disconnect() -> void:
	_log("Deauthorizing...")
	adapter.deauthorize()


func _on_reconnect() -> void:
	adapter.cluster = cluster_option.get_selected_id() as MWATypes.Cluster
	_log("Reconnecting with cached auth...")
	adapter.reconnect()


func _on_get_capabilities() -> void:
	_log("Querying wallet capabilities...")
	adapter.get_capabilities()


func _on_sign_transaction() -> void:
	# NOTE: This sends dummy bytes, NOT a valid Solana transaction.
	# The wallet will reject it. This is expected behavior for the demo.
	# In a real app, build proper Solana transaction bytes.
	var dummy_tx := PackedByteArray()
	dummy_tx.resize(64)
	for i in range(64):
		dummy_tx[i] = randi() % 256
	_log("Signing 1 transaction (dummy bytes - wallet may reject)...")
	adapter.sign_transactions([dummy_tx] as Array)


func _on_sign_and_send() -> void:
	# NOTE: Same as above - dummy bytes will be rejected by the wallet.
	var dummy_tx := PackedByteArray()
	dummy_tx.resize(64)
	for i in range(64):
		dummy_tx[i] = randi() % 256
	var options := MWATypes.SendOptions.new()
	options.commitment = "confirmed"
	_log("Sign & send 1 transaction (dummy bytes - wallet may reject)...")
	adapter.sign_and_send_transactions([dummy_tx] as Array, options)


func _on_sign_message() -> void:
	var msg := "Hello from Godot MWA SDK!".to_utf8_buffer()
	_log("Signing message...")
	adapter.sign_messages([msg] as Array)


func _on_clone_auth() -> void:
	_log("Cloning authorization...")
	adapter.clone_authorization()


func _on_clear_cache() -> void:
	adapter.auth_cache.clear()
	_log("Authorization cache cleared.")


# --- Signal handlers ---

func _on_authorized(result) -> void:
	var acc = result.accounts[0] if result.accounts.size() > 0 else null
	var addr := _shorten(acc.address) if acc != null else "unknown"
	_log("[color=green]Authorized![/color] Account: %s" % addr)
	_log("  Auth token: %s..." % result.auth_token.substr(0, 16))
	_log("  Accounts: %d" % result.accounts.size())
	_log("  Token cached for reconnection.")
	_update_ui()


func _on_auth_failed(error_code: int, error_message: String) -> void:
	_log("[color=red]Authorization failed[/color] (%d): %s" % [error_code, error_message])
	_update_ui()


func _on_deauthorized() -> void:
	_log("[color=yellow]Deauthorized.[/color] Session ended, cache cleared.")
	_update_ui()


func _on_deauth_failed(error_message: String) -> void:
	_log("[color=red]Deauthorization failed:[/color] %s" % error_message)
	_update_ui()


func _on_capabilities(caps) -> void:
	_log("[color=cyan]Wallet Capabilities:[/color]")
	_log("  Clone auth: %s" % str(caps.supports_clone_authorization))
	_log("  Sign & send: %s" % str(caps.supports_sign_and_send_transactions))
	_log("  Max tx/req: %d" % caps.max_transactions_per_request)
	_log("  Max msg/req: %d" % caps.max_messages_per_request)
	_log("  Tx versions: %s" % str(caps.supported_transaction_versions))
	_log("  Features: %s" % str(caps.features))


func _on_capabilities_failed(error_code: int, error_message: String) -> void:
	_log("[color=red]Capabilities failed[/color] (%d): %s" % [error_code, error_message])
	_update_ui()


func _on_tx_signed(signed_payloads: Array) -> void:
	_log("[color=green]Transactions signed![/color] Count: %d" % signed_payloads.size())
	for i in range(signed_payloads.size()):
		var payload: PackedByteArray = signed_payloads[i]
		_log("  [%d] %d bytes" % [i, payload.size()])


func _on_tx_sign_failed(error_code: int, error_message: String) -> void:
	var msg := error_message if error_message != "" and error_message != "null" else "Wallet rejected the transaction (demo sends dummy bytes, not a valid Solana tx)"
	_log("[color=red]Sign failed[/color] (%d): %s" % [error_code, msg])


func _on_tx_sent(signatures: Array) -> void:
	_log("[color=green]Transactions sent![/color] Signatures: %d" % signatures.size())
	for i in range(signatures.size()):
		var sig: PackedByteArray = signatures[i]
		_log("  [%d] %s" % [i, Marshalls.raw_to_base64(sig).substr(0, 32) + "..."])


func _on_tx_send_failed(error_code: int, error_message: String) -> void:
	var msg := error_message if error_message != "" and error_message != "null" else "Wallet rejected the transaction (demo sends dummy bytes, not a valid Solana tx)"
	_log("[color=red]Send failed[/color] (%d): %s" % [error_code, msg])


func _on_msg_signed(signatures: Array) -> void:
	_log("[color=green]Messages signed![/color] Signatures: %d" % signatures.size())
	for i in range(signatures.size()):
		var sig: PackedByteArray = signatures[i]
		_log("  [%d] %s" % [i, Marshalls.raw_to_base64(sig).substr(0, 32) + "..."])


func _on_msg_sign_failed(error_code: int, error_message: String) -> void:
	_log("[color=red]Message sign failed[/color] (%d): %s" % [error_code, error_message])


func _on_auth_cloned(auth_token: String) -> void:
	_log("[color=green]Authorization cloned![/color] Token: %s..." % auth_token.substr(0, 16))


func _on_clone_failed(error_message: String) -> void:
	_log("[color=red]Clone failed:[/color] %s" % error_message)


func _on_state_changed(new_state) -> void:
	_update_ui()


# --- UI helpers ---

func _update_ui() -> void:
	var connected := adapter.is_wallet_connected()
	var has_auth := adapter.is_authorized()
	var busy := adapter.is_busy()

	# Status.
	match adapter.state:
		MWATypes.ConnectionState.DISCONNECTED:
			status_label.text = "Disconnected"
			status_label.modulate = Color.RED
		MWATypes.ConnectionState.CONNECTING:
			status_label.text = "Connecting..."
			status_label.modulate = Color.YELLOW
		MWATypes.ConnectionState.CONNECTED:
			status_label.text = "Connected"
			status_label.modulate = Color.GREEN
		MWATypes.ConnectionState.SIGNING:
			status_label.text = "Signing..."
			status_label.modulate = Color.CYAN
		MWATypes.ConnectionState.DEAUTHORIZING:
			status_label.text = "Deauthorizing..."
			status_label.modulate = Color.YELLOW

	if busy:
		status_label.text += " (working...)"

	# Pubkey.
	var acc = adapter.get_account()
	if acc != null:
		pubkey_label.text = acc.address
	else:
		pubkey_label.text = "Not connected"

	# Button states.
	connect_btn.disabled = busy or adapter.state == MWATypes.ConnectionState.CONNECTING
	disconnect_btn.disabled = busy or not has_auth
	reconnect_btn.disabled = busy or adapter.state == MWATypes.ConnectionState.CONNECTING
	capabilities_btn.disabled = busy or not connected
	sign_tx_btn.disabled = busy or not connected
	sign_send_btn.disabled = busy or not connected
	sign_msg_btn.disabled = busy or not connected
	clone_auth_btn.disabled = busy or not connected


func _log(msg: String) -> void:
	var time_str := Time.get_time_string_from_system()
	output_log.append_text("[%s] %s\n" % [time_str, msg])
	# Auto-scroll to bottom.
	output_log.scroll_to_line(output_log.get_line_count() - 1)


func _shorten(addr: String) -> String:
	if addr.length() > 12:
		return addr.substr(0, 6) + "..." + addr.substr(addr.length() - 4)
	return addr
