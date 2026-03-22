extends Control
## Guided SDK Playground — step-based MWA demo with progressive unlocking.

# --- Step Cards ---
@onready var step1_card: PanelContainer = %Step1Card
@onready var step2_card: PanelContainer = %Step2Card
@onready var step3_card: PanelContainer = %Step3Card
@onready var step4_card: PanelContainer = %Step4Card
@onready var log_card: PanelContainer = %LogCard

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
@onready var output_log: RichTextLabel = %OutputLog
@onready var clear_btn: Button = %ClearBtn

# --- Toast ---
@onready var toast_margin: MarginContainer = %ToastMargin
@onready var toast_panel: PanelContainer = %ToastPanel
@onready var toast_label: Label = %ToastLabel

# --- State ---
var adapter: MobileWalletAdapter
var _button_labels := {}
var _toast_tween: Tween
var _connect_btn_normal_style: StyleBox
var _prev_step2_locked := true
var _prev_step3_locked := true
var _prev_step4_locked := true

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

	_connect_btn_normal_style = connect_btn.get_theme_stylebox("normal")

	_connect_adapter_signals()
	_wire_buttons()
	_setup_cluster_selector()
	_setup_toast()
	_update_steps()
	_play_entrance_animation()

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
	clear_btn.pressed.connect(_on_clear_log)

	# Wire press animations to all interactive buttons.
	for btn in [connect_btn, siws_btn, sign_tx_btn, sign_send_btn,
			sign_msg_btn, features_btn, disconnect_btn, reconnect_btn,
			deauth_btn, reset_btn, clear_btn]:
		btn.button_down.connect(_animate_button_press.bind(btn))
		btn.button_up.connect(_animate_button_release.bind(btn))


func _setup_cluster_selector() -> void:
	cluster_option.add_item("Devnet", MWATypes.Cluster.DEVNET)
	cluster_option.add_item("Mainnet", MWATypes.Cluster.MAINNET)
	cluster_option.add_item("Testnet", MWATypes.Cluster.TESTNET)
	cluster_option.selected = 0


func _setup_toast() -> void:
	toast_panel.visible = false
	toast_panel.modulate.a = 0.0
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.y > 0:
		var safe_top := int(safe.position.y * get_viewport().get_visible_rect().size.y / screen.y)
		if safe_top > 0:
			toast_margin.add_theme_constant_override("margin_top", safe_top + 6)


# ===================================================================
# ENTRANCE ANIMATION
# ===================================================================

func _play_entrance_animation() -> void:
	var cards: Array[Control] = [step1_card, step2_card, step3_card, step4_card, log_card]
	for card in cards:
		card.modulate.a = 0.0
		card.position.y += 12.0

	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)

	for i in range(cards.size()):
		var card := cards[i]
		var target_y := card.position.y - 12.0
		tw.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(i * 0.06)
		tw.parallel().tween_property(card, "position:y", target_y, 0.3).set_delay(i * 0.06)


# ===================================================================
# BUTTON PRESS ANIMATIONS
# ===================================================================

func _animate_button_press(btn: Button) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(btn, "scale", Vector2(0.97, 0.97), 0.08)


func _animate_button_release(btn: Button) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_ELASTIC)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.35)


# ===================================================================
# STEP STATE MANAGEMENT
# ===================================================================

func _update_steps() -> void:
	var authorized := adapter.is_authorized()
	var busy := adapter.is_busy()

	# Step 1: Always enabled.
	_update_status_indicator()
	connect_btn.disabled = busy
	if authorized:
		connect_btn.text = "Disconnect"
		connect_btn.add_theme_color_override("font_color", C_RED)
		connect_btn.add_theme_color_override("font_hover_color", C_RED)
		var outline := StyleBoxFlat.new()
		outline.bg_color = Color.TRANSPARENT
		outline.border_color = C_RED
		outline.set_border_width_all(1)
		outline.set_corner_radius_all(10)
		outline.content_margin_left = 12.0
		outline.content_margin_top = 12.0
		outline.content_margin_right = 12.0
		outline.content_margin_bottom = 12.0
		connect_btn.add_theme_stylebox_override("normal", outline)
		connect_btn.add_theme_stylebox_override("hover", outline)
	else:
		connect_btn.text = "Connect Wallet"
		connect_btn.add_theme_color_override("font_color", Color(0.02, 0.02, 0.03))
		connect_btn.add_theme_color_override("font_hover_color", Color(0.02, 0.02, 0.03))
		connect_btn.add_theme_color_override("font_pressed_color", Color(0.02, 0.02, 0.03))
		connect_btn.add_theme_stylebox_override("normal", _connect_btn_normal_style)
		connect_btn.add_theme_stylebox_override("hover", connect_btn.get_theme_stylebox("hover"))
		connect_btn.add_theme_stylebox_override("pressed", connect_btn.get_theme_stylebox("pressed"))

	# Step 2: Unlock after connected.
	var s2_locked := !authorized
	_set_step_locked(step2_content, step2_hint, s2_locked)
	if _prev_step2_locked and not s2_locked:
		_animate_step_unlock(step2_card)
	_prev_step2_locked = s2_locked

	# Step 3: Unlock after authorized.
	var s3_locked := !authorized
	_set_step_locked(step3_content, step3_hint, s3_locked)
	if _prev_step3_locked and not s3_locked:
		_animate_step_unlock(step3_card)
	_prev_step3_locked = s3_locked

	# Step 4: Unlock after connected (need something to manage).
	var has_session := authorized or adapter.auth_cache.has_authorization()
	var s4_locked := !has_session
	_set_step_locked(step4_content, step4_hint, s4_locked)
	if _prev_step4_locked and not s4_locked:
		_animate_step_unlock(step4_card)
	_prev_step4_locked = s4_locked

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


func _animate_step_unlock(card: PanelContainer) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	# Brief scale pulse to draw attention.
	card.pivot_offset = card.size / 2.0
	tw.tween_property(card, "scale", Vector2(1.015, 1.015), 0.15)
	tw.tween_property(card, "scale", Vector2.ONE, 0.25)


func _update_status_indicator() -> void:
	var prev_text := status_label.text
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

	# Pulse the status dot when state changes.
	if status_label.text != prev_text:
		_pulse_status_dot()


func _pulse_status_dot() -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	status_dot.pivot_offset = status_dot.size / 2.0
	tw.tween_property(status_dot, "scale", Vector2(1.6, 1.6), 0.12)
	tw.tween_property(status_dot, "scale", Vector2.ONE, 0.2)


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
	_toast_tween.set_ease(Tween.EASE_OUT)
	_toast_tween.set_trans(Tween.TRANS_CUBIC)
	# Slide in from top.
	toast_panel.position.y = -20.0
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.25)
	_toast_tween.parallel().tween_property(toast_panel, "position:y", 0.0, 0.25)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func(): toast_panel.visible = false)


# ===================================================================
# LOG PANEL
# ===================================================================

func _on_clear_log() -> void:
	output_log.clear()
	_log("[color=#555570]Log cleared.[/color]")


func _log(msg: String) -> void:
	var time_str := Time.get_time_string_from_system()
	output_log.append_text("[color=#555570]%s[/color]  %s\n" % [time_str, msg])
	output_log.scroll_to_line(output_log.get_line_count() - 1)


# ===================================================================
# BUTTON HANDLERS
# ===================================================================

func _on_connect() -> void:
	if adapter.is_authorized():
		_set_loading(connect_btn, "Disconnecting...")
		_log("Disconnecting...")
		adapter.disconnect_wallet()
	else:
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
