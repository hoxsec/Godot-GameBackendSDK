extends Control

## Demo scene for GameBackendSDK

@onready var base_url_input: LineEdit = %BaseUrlInput
@onready var project_id_input: LineEdit = %ProjectIdInput
@onready var init_button: Button = %InitButton
@onready var email_input: LineEdit = %EmailInput
@onready var password_input: LineEdit = %PasswordInput
@onready var guest_button: Button = %GuestButton
@onready var register_button: Button = %RegisterButton
@onready var login_button: Button = %LoginButton
@onready var refresh_button: Button = %RefreshButton
@onready var logout_button: Button = %LogoutButton
@onready var kv_key_input: LineEdit = %KVKeyInput
@onready var kv_value_input: LineEdit = %KVValueInput
@onready var kv_set_button: Button = %KVSetButton
@onready var kv_get_button: Button = %KVGetButton
@onready var kv_delete_button: Button = %KVDeleteButton
@onready var lb_board_input: LineEdit = %LBBoardInput
@onready var lb_score_input: SpinBox = %LBScoreInput
@onready var lb_submit_button: Button = %LBSubmitButton
@onready var lb_top_button: Button = %LBTopButton
@onready var lb_me_button: Button = %LBMeButton
@onready var config_platform_input: LineEdit = %ConfigPlatformInput
@onready var config_version_input: LineEdit = %ConfigVersionInput
@onready var config_button: Button = %ConfigButton
@onready var log_output: TextEdit = %LogOutput
@onready var state_label: Label = %StateLabel

var backend: Backend

func _ready() -> void:
	# Set default values
	base_url_input.text = "http://localhost:3000"
	project_id_input.text = "demo_project"
	email_input.text = "test@example.com"
	password_input.text = "password123"
	kv_key_input.text = "player_data"
	kv_value_input.text = '{"level": 5, "coins": 100}'
	lb_board_input.text = "default"
	lb_score_input.value = 1000
	config_platform_input.text = "windows"
	config_version_input.text = "1.0.0"
	
	# Connect buttons
	init_button.pressed.connect(_on_init_pressed)
	guest_button.pressed.connect(_on_guest_pressed)
	register_button.pressed.connect(_on_register_pressed)
	login_button.pressed.connect(_on_login_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	kv_set_button.pressed.connect(_on_kv_set_pressed)
	kv_get_button.pressed.connect(_on_kv_get_pressed)
	kv_delete_button.pressed.connect(_on_kv_delete_pressed)
	lb_submit_button.pressed.connect(_on_lb_submit_pressed)
	lb_top_button.pressed.connect(_on_lb_top_pressed)
	lb_me_button.pressed.connect(_on_lb_me_pressed)
	config_button.pressed.connect(_on_config_pressed)
	
	# Get or create Backend singleton
	backend = get_node_or_null("/root/Backend")
	if backend == null:
		backend = Backend.new()
		backend.name = "Backend"
		get_tree().root.add_child(backend)
	
	# Connect signals
	backend.auth_changed.connect(_on_auth_changed)
	backend.request_started.connect(_on_request_started)
	backend.request_finished.connect(_on_request_finished)
	backend.token_refreshed.connect(_on_token_refreshed)
	backend.banned_detected.connect(_on_banned_detected)
	
	_update_state()
	_log("Demo ready. Initialize the SDK to begin.")

func _on_init_pressed() -> void:
	print("[Demo] _on_init_pressed: Button clicked")
	await _safe_async_call(func():
		print("[Demo] _on_init_pressed: Inside callable, calling backend.init")
		var result := await backend.init(base_url_input.text, project_id_input.text, {
			"timeout_sec": 10,
			"retries": 2,
			"user_agent": "GameBackendSDK-Demo/1.0",
			"debug": true  # Enable debug logging
		})
		print("[Demo] _on_init_pressed: backend.init returned")
		_log_result("init", result)
		_update_state()
		print("[Demo] _on_init_pressed: Callable complete")
	)
	print("[Demo] _on_init_pressed: _safe_async_call returned")

func _on_guest_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.ensure_guest()
		_log_result("ensure_guest", result)
		_update_state()
	)

func _on_register_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.register(email_input.text, password_input.text)
		_log_result("register", result)
		_update_state()
	)

func _on_login_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.login(email_input.text, password_input.text)
		_log_result("login", result)
		_update_state()
	)

func _on_refresh_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.refresh()
		_log_result("refresh", result)
		_update_state()
	)

func _on_logout_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.logout()
		_log_result("logout", result)
		_update_state()
	)

func _on_kv_set_pressed() -> void:
	await _safe_async_call(func():
		var value_variant: Variant = kv_value_input.text
		
		# Try to parse as JSON
		var json := JSON.new()
		if json.parse(kv_value_input.text) == OK:
			value_variant = json.data
		
		var result := await backend.kv_set(kv_key_input.text, value_variant)
		_log_result("kv_set", result)
	)

func _on_kv_get_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.kv_get(kv_key_input.text)
		_log_result("kv_get", result)
	)

func _on_kv_delete_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.kv_delete(kv_key_input.text)
		_log_result("kv_delete", result)
	)

func _on_lb_submit_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.leaderboard_submit(lb_board_input.text, int(lb_score_input.value))
		_log_result("leaderboard_submit", result)
	)

func _on_lb_top_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.leaderboard_top(lb_board_input.text, 20)
		_log_result("leaderboard_top", result)
	)

func _on_lb_me_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.leaderboard_me(lb_board_input.text)
		_log_result("leaderboard_me", result)
	)

func _on_config_pressed() -> void:
	await _safe_async_call(func():
		var result := await backend.config_fetch(config_platform_input.text, config_version_input.text)
		_log_result("config_fetch", result)
	)

func _on_auth_changed(user_id: String) -> void:
	_log("[SIGNAL] auth_changed: %s" % user_id)
	_update_state()

func _on_request_started(method: String, path: String) -> void:
	_log("[SIGNAL] request_started: %s %s" % [method, path])

func _on_request_finished(method: String, path: String, ok: bool, status: int) -> void:
	_log("[SIGNAL] request_finished: %s %s -> %s (status %d)" % [method, path, "OK" if ok else "ERROR", status])

func _on_token_refreshed(ok: bool) -> void:
	_log("[SIGNAL] token_refreshed: %s" % ("success" if ok else "failed"))

func _on_banned_detected(details: Dictionary) -> void:
	_log("[SIGNAL] banned_detected: %s" % JSON.stringify(details))

func _log(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	log_output.text += "[%s] %s\n" % [timestamp, message]
	# Scroll to bottom
	log_output.scroll_vertical = INF

func _log_result(method: String, result: Dictionary) -> void:
	var status := "OK" if result.ok else "ERROR"
	_log("[%s] %s: %s" % [status, method, JSON.stringify(result, "\t")])

func _update_state() -> void:
	if backend == null:
		return
	
	var state := backend.get_state()
	state_label.text = "State: user_id=%s, has_tokens=%s" % [
		state.user_id if state.user_id != "" else "(none)",
		state.has_tokens
	]

func _disable_buttons() -> void:
	print("[Demo] Disabling buttons")
	_set_buttons_enabled(false)

func _enable_buttons() -> void:
	print("[Demo] Enabling buttons")
	_set_buttons_enabled(true)

func _set_buttons_enabled(enabled: bool) -> void:
	init_button.disabled = !enabled
	guest_button.disabled = !enabled
	register_button.disabled = !enabled
	login_button.disabled = !enabled
	refresh_button.disabled = !enabled
	logout_button.disabled = !enabled
	kv_set_button.disabled = !enabled
	kv_get_button.disabled = !enabled
	kv_delete_button.disabled = !enabled
	lb_submit_button.disabled = !enabled
	lb_top_button.disabled = !enabled
	lb_me_button.disabled = !enabled
	config_button.disabled = !enabled

## Safe wrapper for async calls that ensures buttons are re-enabled even on error/timeout
func _safe_async_call(callable: Callable) -> void:
	print("[Demo] _safe_async_call: Starting operation")
	_disable_buttons()
	
	# Always re-enable buttons using deferred call as safety net
	# This ensures buttons are enabled even if something goes wrong
	var safety_timer := get_tree().create_timer(30.0)
	safety_timer.timeout.connect(func():
		_log("[WARNING] Safety timeout triggered - force enabling buttons")
		_enable_buttons()
	)
	
	# Execute the operation
	print("[Demo] _safe_async_call: About to call operation")
	await callable.call()
	print("[Demo] _safe_async_call: Operation completed, re-enabling buttons")
	
	# Re-enable buttons immediately after operation completes
	_enable_buttons()
