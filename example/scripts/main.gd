extends Control
## Guided SDK Playground — step-based MWA demo with progressive unlocking.

# --- Step Cards ---
@onready var step1_card: PanelContainer = %Step1Card
@onready var step2_card: PanelContainer = %Step2Card
@onready var step3_card: PanelContainer = %Step3Card
@onready var step4_card: PanelContainer = %Step4Card

# --- Step Content (locked/unlocked toggling) ---
@onready var step2_content: VBoxContainer = %Step2Content
@onready var step3_content: VBoxContainer = %Step3Content
@onready var step4_content: VBoxContainer = %Step4Content
@onready var step2_hint: Label = %Step2Hint
@onready var step3_hint: Label = %Step3Hint
@onready var step4_hint: Label = %Step4Hint

# --- Header ---
@onready var cluster_option: OptionButton = %ClusterOption

# --- Step 1: Connect ---
@onready var connect_btn: Button = %ConnectBtn
@onready var status_dot: Label = %StatusDot
@onready var status_label: Label = %StatusLabel

# --- Step 2: Authorize ---
@onready var siws_btn: Button = %SIWSBtn
@onready var wallet_addr: Label = %WalletAddr

# --- Step 3: Actions ---
@onready var sign_tx_btn: Button = %SignTxBtn
@onready var sign_send_btn: Button = %SignSendBtn
@onready var sign_msg_btn: Button = %SignMsgBtn
@onready var features_btn: Button = %FeaturesBtn

# --- Step 4: Session ---
@onready var disconnect_btn: Button = %DisconnectBtn
@onready var reconnect_btn: Button = %ReconnectBtn
@onready var deauth_btn: Button = %DeauthBtn
@onready var reset_btn: Button = %ResetBtn

# --- Log ---
@onready var log_toggle_btn: Button = %LogToggleBtn
@onready var log_panel: PanelContainer = %LogPanel
@onready var output_log: RichTextLabel = %OutputLog

# --- Toast ---
@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %ToastLabel

# --- State ---
var adapter: MobileWalletAdapter
var _log_visible := false
var _button_labels := {}  # Stores original text for loading states
var _toast_tween: Tween

# --- Colors ---
const C_GREEN := Color(0.0, 0.83, 0.67)
const C_PURPLE := Color(0.6, 0.27, 1.0)
const C_BLUE := Color(0.29, 0.62, 1.0)
const C_RED := Color(1.0, 0.42, 0.42)
const C_AMBER := Color(0.91, 0.66, 0.22)
const C_TEXT := Color(0.91, 0.91, 0.94)
const C_MUTED := Color(0.45, 0.45, 0.56)


func _ready() -> void:
	adapter = MWA.adapter

	adapter.identity = MWATypes.DappIdentity.new(
		"MWA SDK Demo",
		"https://solanamobile.com",
		"icon.png"
	)
	adapter.debug_logging = true
	adapter.debug_log.connect(func(msg): _log("[color=#555570][DEBUG] %s[/color]" % msg))

	_connect_adapter_signals()
	_wire_buttons()
	_setup_cluster_selector()
	_setup_toast()
	_setup_log()
	_update_steps()

	if adapter.auth_cache.has_authorization():
		_log("Cached session found. Tap [b]Reconnect[/b] to restore.")


func _connect_adapter_signals() -> void:
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
	adapter.state_changed.connect(_on_state_changed)


func _wire_buttons() -> void:
	connect_btn.pressed.connect(_on_connect)
	siws_btn.pressed.connect(_on_sign_in_with_solana)
	sign_tx_btn.pressed.connect(_on_sign_transaction)
	sign_send_btn.pressed.connect(_on_sign_and_send)
	sign_msg_btn.pressed.connect(_on_sign_message)
	features_btn.pressed.connect(_on_get_capabilities)
	disconnect_btn.pressed.connect(_on_disconnect)
	reconnect_btn.pressed.connect(_on_reconnect)
	deauth_btn.pressed.connect(_on_deauthorize)
	reset_btn.pressed.connect(_on_reset_session)
	log_toggle_btn.pressed.connect(_on_toggle_log)


func _setup_cluster_selector() -> void:
	cluster_option.add_item("Devnet", MWATypes.Cluster.DEVNET)
	cluster_option.add_item("Mainnet", MWATypes.Cluster.MAINNET)
	cluster_option.add_item("Testnet", MWATypes.Cluster.TESTNET)
	cluster_option.selected = 0


func _setup_toast() -> void:
	toast_panel.visible = false
	toast_panel.modulate.a = 0.0


func _setup_log() -> void:
	log_panel.visible = false
	_log_visible = false
	log_toggle_btn.text = "Show Output Log"


# ===================================================================
# STEP STATE MANAGEMENT
# ===================================================================

func _update_steps() -> void:
	var authorized := adapter.is_authorized()
	var busy := adapter.is_busy()

	# Step 1: Always enabled.
	_update_status_indicator()
	connect_btn.disabled = busy

	# Step 2: Unlock after connected.
	_set_step_locked(step2_content, step2_hint, !authorized)

	# Step 3: Unlock after authorized.
	_set_step_locked(step3_content, step3_hint, !authorized)

	# Step 4: Unlock after connected (need something to manage).
	var has_session := authorized or adapter.auth_cache.has_authorization()
	_set_step_locked(step4_content, step4_hint, !has_session)

	# Wallet address.
	var acc = adapter.get_account()
	if acc != null:
		wallet_addr.text = acc.address
		wallet_addr.add_theme_color_override("font_color", C_TEXT)
	else:
		wallet_addr.text = "No wallet connected yet"
		wallet_addr.add_theme_color_override("font_color", C_MUTED)

	# Restore any loading button states.
	_restore_all_buttons()


func _set_step_locked(content: VBoxContainer, hint: Label, locked: bool) -> void:
	hint.visible = locked
	content.modulate.a = 1.0 if not locked else 0.35
	for child in content.get_children():
		if child is Button:
			child.disabled = locked
		elif child is HBoxContainer or child is GridContainer:
			for btn in child.get_children():
				if btn is Button:
					btn.disabled = locked


func _update_status_indicator() -> void:
	match adapter.state:
		MWATypes.ConnectionState.DISCONNECTED:
			status_dot.text = "\u25CF"
			status_dot.add_theme_color_override("font_color", C_RED)
			status_label.text = "Disconnected"
			status_label.add_theme_color_override("font_color", C_RED)
		MWATypes.ConnectionState.CONNECTING:
			status_dot.text = "\u25CF"
			status_dot.add_theme_color_override("font_color", C_AMBER)
			status_label.text = "Connecting..."
			status_label.add_theme_color_override("font_color", C_AMBER)
		MWATypes.ConnectionState.CONNECTED:
			status_dot.text = "\u25CF"
			status_dot.add_theme_color_override("font_color", C_GREEN)
			status_label.text = "Connected"
			status_label.add_theme_color_override("font_color", C_GREEN)
		MWATypes.ConnectionState.SIGNING:
			status_dot.text = "\u25CF"
			status_dot.add_theme_color_override("font_color", C_PURPLE)
			status_label.text = "Signing..."
			status_label.add_theme_color_override("font_color", C_PURPLE)
		MWATypes.ConnectionState.DEAUTHORIZING:
			status_dot.text = "\u25CF"
			status_dot.add_theme_color_override("font_color", C_AMBER)
			status_label.text = "Deauthorizing..."
			status_label.add_theme_color_override("font_color", C_AMBER)


# ===================================================================
# BUTTON LOADING STATES
# ===================================================================

func _set_loading(btn: Button, loading_text: String) -> void:
	if not _button_labels.has(btn):
		_button_labels[btn] = btn.text
	btn.text = loading_text
	btn.disabled = true


func _restore_button(btn: Button) -> void:
	if _button_labels.has(btn):
		btn.text = _button_labels[btn]
		_button_labels.erase(btn)


func _restore_all_buttons() -> void:
	for btn in _button_labels.keys():
		if is_instance_valid(btn):
			btn.text = _button_labels[btn]
	_button_labels.clear()


# ===================================================================
# TOAST NOTIFICATIONS
# ===================================================================

func _show_toast(text: String, is_error: bool = false) -> void:
	toast_label.text = text

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.08, 0.08, 0.95) if is_error else Color(0.05, 0.15, 0.1, 0.95)
	style.border_width_left = 4
	style.border_color = C_RED if is_error else C_GREEN
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 16
	style.content_margin_top = 12
	style.content_margin_right = 16
	style.content_margin_bottom = 12
	toast_panel.add_theme_stylebox_override("panel", style)

	toast_label.add_theme_color_override("font_color", C_RED if is_error else C_GREEN)
	toast_panel.visible = true

	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()

	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func(): toast_panel.visible = false)


# ===================================================================
# LOG PANEL
# ===================================================================

func _on_toggle_log() -> void:
	_log_visible = not _log_visible
	log_panel.visible = _log_visible
	log_toggle_btn.text = "Hide Output Log" if _log_visible else "Show Output Log"


func _log(msg: String) -> void:
	var time_str := Time.get_time_string_from_system()
	output_log.append_text("[color=#555570]%s[/color]  %s\n" % [time_str, msg])
	output_log.scroll_to_line(output_log.get_line_count() - 1)


# ===================================================================
# BUTTON HANDLERS
# ===================================================================

func _on_connect() -> void:
	adapter.cluster = cluster_option.get_selected_id() as MWATypes.Cluster
	_set_loading(connect_btn, "Connecting...")
	_log("Connecting on %s..." % MWATypes.cluster_to_chain(adapter.cluster))
	adapter.authorize()


func _on_sign_in_with_solana() -> void:
	adapter.cluster = cluster_option.get_selected_id() as MWATypes.Cluster
	var siws := MWATypes.SignInPayload.new()
	siws.domain = "mwa-sdk-demo.solana.com"
	siws.statement = "Sign in to MWA SDK Demo"
	siws.uri = "https://mwa-sdk-demo.solana.com"
	siws.version = "1"
	siws.chain_id = MWATypes.cluster_to_chain(adapter.cluster).replace("solana:", "")
	siws.issued_at = Time.get_datetime_string_from_system(true)
	_set_loading(siws_btn, "Signing in...")
	_log("SIWS on %s — domain: %s" % [MWATypes.cluster_to_chain(adapter.cluster), siws.domain])
	adapter.authorize(siws)


func _on_sign_transaction() -> void:
	var dummy_tx := PackedByteArray()
	dummy_tx.resize(64)
	for i in range(64):
		dummy_tx[i] = randi() % 256
	_set_loading(sign_tx_btn, "Signing...")
	_log("Signing transaction (dummy bytes)...")
	adapter.sign_transactions([dummy_tx] as Array)


func _on_sign_and_send() -> void:
	var dummy_tx := PackedByteArray()
	dummy_tx.resize(64)
	for i in range(64):
		dummy_tx[i] = randi() % 256
	var options := MWATypes.SendOptions.new()
	options.commitment = "confirmed"
	_set_loading(sign_send_btn, "Sending...")
	_log("Sign & send transaction (dummy bytes)...")
	adapter.sign_and_send_transactions([dummy_tx] as Array, options)


func _on_sign_message() -> void:
	var msg := "Hello from Godot MWA SDK!".to_utf8_buffer()
	_set_loading(sign_msg_btn, "Signing...")
	_log("Signing message...")
	adapter.sign_messages([msg] as Array)


func _on_get_capabilities() -> void:
	_set_loading(features_btn, "Checking...")
	_log("Querying wallet features...")
	adapter.get_capabilities()


func _on_disconnect() -> void:
	_set_loading(disconnect_btn, "Disconnecting...")
	_log("Disconnecting...")
	adapter.disconnect_wallet()


func _on_reconnect() -> void:
	adapter.cluster = cluster_option.get_selected_id() as MWATypes.Cluster
	_set_loading(reconnect_btn, "Reconnecting...")
	_log("Reconnecting from cached session...")
	adapter.reconnect()


func _on_deauthorize() -> void:
	_set_loading(deauth_btn, "Deauthorizing...")
	_log("Deauthorizing session...")
	adapter.deauthorize()


func _on_reset_session() -> void:
	adapter.auth_cache.clear()
	_show_toast("Session reset — cache cleared")
	_log("Session reset. Authorization cache cleared.")
	_update_steps()


# ===================================================================
# SIGNAL HANDLERS
# ===================================================================

func _on_authorized(result) -> void:
	var acc = result.accounts[0] if result.accounts.size() > 0 else null
	var addr: String = acc.address if acc != null else "unknown"
	_show_toast("Wallet connected: %s" % _shorten(addr))
	_log("[color=#00d4aa]Connected![/color] %s" % _shorten(addr))
	_log("  Auth token: %s..." % result.auth_token.substr(0, 16))
	if result.sign_in_result.size() > 0:
		_log("[color=#9945ff]  SIWS verified[/color]")
		for key in result.sign_in_result:
			var val = result.sign_in_result[key]
			if val is String and val.length() > 40:
				val = val.substr(0, 40) + "..."
			_log("    %s: %s" % [key, str(val)])
	_update_steps()


func _on_auth_failed(error_code: int, error_message: String) -> void:
	var msg := _error_label(error_code, error_message)
	_show_toast(msg, true)
	_log("[color=#ff6b6b]Auth failed[/color] (%d): %s" % [error_code, error_message])
	_update_steps()


func _on_deauthorized() -> void:
	_show_toast("Disconnected from wallet")
	_log("[color=#e8a838]Disconnected.[/color] Session ended.")
	_update_steps()


func _on_deauth_failed(error_message: String) -> void:
	_show_toast("Disconnect failed: %s" % error_message, true)
	_log("[color=#ff6b6b]Disconnect failed:[/color] %s" % error_message)
	_update_steps()


func _on_capabilities(caps) -> void:
	_show_toast("Wallet features loaded")
	_log("[color=#4a9eff]Wallet Features:[/color]")
	_log("  Sign & send: %s" % str(caps.supports_sign_and_send_transactions))
	_log("  Max tx/req: %d" % caps.max_transactions_per_request)
	_log("  Max msg/req: %d" % caps.max_messages_per_request)
	_log("  Tx versions: %s" % str(caps.supported_transaction_versions))
	_update_steps()


func _on_capabilities_failed(error_code: int, error_message: String) -> void:
	_show_toast("Failed to load features", true)
	_log("[color=#ff6b6b]Features failed[/color] (%d): %s" % [error_code, error_message])
	_update_steps()


func _on_tx_signed(signed_payloads: Array) -> void:
	_show_toast("Transaction signed (%d)" % signed_payloads.size())
	_log("[color=#00d4aa]Signed![/color] %d transaction(s)" % signed_payloads.size())
	for i in range(signed_payloads.size()):
		_log("  [%d] %d bytes" % [i, (signed_payloads[i] as PackedByteArray).size()])
	_update_steps()


func _on_tx_sign_failed(error_code: int, error_message: String) -> void:
	var msg := error_message if error_message != "" and error_message != "null" else "Wallet rejected (demo uses dummy bytes)"
	_show_toast("Sign failed: %s" % msg, true)
	_log("[color=#ff6b6b]Sign failed[/color] (%d): %s" % [error_code, msg])
	_update_steps()


func _on_tx_sent(signatures: Array) -> void:
	_show_toast("Transaction sent!")
	_log("[color=#00d4aa]Sent![/color] %d signature(s)" % signatures.size())
	for i in range(signatures.size()):
		var sig: PackedByteArray = signatures[i]
		_log("  [%d] %s..." % [i, Marshalls.raw_to_base64(sig).substr(0, 32)])
	_update_steps()


func _on_tx_send_failed(error_code: int, error_message: String) -> void:
	var msg := error_message if error_message != "" and error_message != "null" else "Wallet rejected (demo uses dummy bytes)"
	_show_toast("Send failed: %s" % msg, true)
	_log("[color=#ff6b6b]Send failed[/color] (%d): %s" % [error_code, msg])
	_update_steps()


func _on_msg_signed(signatures: Array) -> void:
	_show_toast("Message signed!")
	_log("[color=#00d4aa]Message signed![/color] %d signature(s)" % signatures.size())
	for i in range(signatures.size()):
		var sig: PackedByteArray = signatures[i]
		_log("  [%d] %s..." % [i, Marshalls.raw_to_base64(sig).substr(0, 32)])
	_update_steps()


func _on_msg_sign_failed(error_code: int, error_message: String) -> void:
	_show_toast("Message sign failed", true)
	_log("[color=#ff6b6b]Message sign failed[/color] (%d): %s" % [error_code, error_message])
	_update_steps()


func _on_state_changed(_new_state) -> void:
	_update_steps()


# ===================================================================
# HELPERS
# ===================================================================

func _shorten(addr: String) -> String:
	if addr.length() > 12:
		return addr.substr(0, 4) + "..." + addr.substr(addr.length() - 4)
	return addr


func _error_label(code: int, msg: String) -> String:
	match code:
		MWATypes.ErrorCode.NO_WALLET_FOUND:
			return "No wallet app installed"
		MWATypes.ErrorCode.USER_DECLINED:
			return "Request declined by user"
		MWATypes.ErrorCode.TIMEOUT:
			return "Wallet timed out"
		MWATypes.ErrorCode.BUSY:
			return "Another operation in progress"
	return msg if msg != "" else "Unknown error"
