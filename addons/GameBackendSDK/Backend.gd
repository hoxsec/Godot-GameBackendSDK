extends Node

## GameBackendSDK - Production-ready client SDK for custom game backends
##
## This singleton provides a complete interface for authentication, cloud saves,
## leaderboards, and remote configuration over HTTPS REST APIs.
##
## @tutorial: See README.md for full documentation and backend contract
##
## Access globally via the Backend autoload singleton

const HttpClient = preload("res://addons/GameBackendSDK/internal/HttpClient.gd")
const TokenStore = preload("res://addons/GameBackendSDK/internal/TokenStore.gd")
const Result = preload("res://addons/GameBackendSDK/internal/Result.gd")
const Types = preload("res://addons/GameBackendSDK/internal/Types.gd")

#region Signals

## Emitted when authentication state changes (login, logout, guest, etc.)
signal auth_changed(user_id: String)

## Emitted when any HTTP request starts
signal request_started(method: String, path: String)

## Emitted when any HTTP request completes
signal request_finished(method: String, path: String, ok: bool, status: int)

## Emitted after automatic token refresh (success or failure)
signal token_refreshed(ok: bool)

## Emitted when the backend returns a "banned" status
signal banned_detected(details: Dictionary)

#endregion

#region Private State

var _initialized := false
var _base_url := ""
var _project_id := ""
var _endpoints := {}
var _http_client: HttpClient
var _token_store: TokenStore
var _last_error: Dictionary = {}
var _is_refreshing := false

#endregion

#region Debug Settings

## Enable debug logging to Godot console
var debug_mode := false

func set_debug_mode(enabled: bool) -> void:
	debug_mode = enabled
	if _http_client:
		_http_client.debug_mode = enabled

func _debug_log(message: String) -> void:
	if debug_mode:
		print("[GameBackendSDK] ", message)

#endregion

func _ready() -> void:
	_token_store = TokenStore.new()
	
	# Create HTTP client
	_http_client = HttpClient.new()
	add_child(_http_client)
	
	# Set up callbacks
	_http_client.on_unauthorized = _handle_unauthorized
	_http_client.on_banned = _handle_banned
	_http_client.request_completed.connect(_on_request_completed)

#region Public API

## Initialize the SDK with backend URL and project configuration
##
## @param base_url: Backend API base URL (e.g., "https://api.example.com")
## @param project_id: Your project/game identifier
## @param options: Configuration dictionary with optional keys:
##   - timeout_sec: int = 10
##   - retries: int = 3
##   - backoff_base_ms: int = 100
##   - user_agent: String = "GameBackendSDK/1.0"
##   - default_headers: Dictionary = {}
##   - endpoints: Dictionary = {} (override default endpoint paths)
##   - queue_requests: bool = true (serialize requests to avoid race conditions)
##   - debug: bool = false (enable debug logging to console)
## @returns: Dictionary with {ok, data, error}
func init(base_url: String, project_id: String, options := {}) -> Dictionary:
	if _initialized:
		return Result.error("already_initialized", "SDK is already initialized", 0, null)
	
	_base_url = base_url.trim_suffix("/")
	_project_id = project_id
	
	# Merge default endpoints with custom overrides
	_endpoints = Types.DEFAULT_ENDPOINTS.duplicate()
	if options.has("endpoints"):
		_endpoints.merge(options.endpoints, true)
	
	# Configure HTTP client
	var http_config := {
		"base_url": _base_url,
		"project_id": _project_id,
		"timeout_sec": options.get("timeout_sec", 10),
		"max_retries": options.get("retries", 3),
		"backoff_base_ms": options.get("backoff_base_ms", 100),
		"queue_requests": options.get("queue_requests", true),
		"debug": options.get("debug", false)
	}
	_http_client.configure(http_config)
	
	# Set default headers
	var default_headers: Dictionary = options.get("default_headers", {}).duplicate()
	default_headers["User-Agent"] = options.get("user_agent", "GameBackendSDK/1.0")
	_http_client.set_default_headers(default_headers)
	
	# Enable debug mode if requested
	debug_mode = options.get("debug", false)
	_http_client.debug_mode = debug_mode
	
	_initialized = true
	_debug_log("SDK initialized: base_url=%s, project_id=%s" % [_base_url, _project_id])
	
	# If we have stored tokens, emit auth_changed
	if _token_store.has_tokens():
		auth_changed.emit(_token_store.get_user_id())
	
	return Result.ok({"initialized": true})

## Set a default HTTP header for all requests
func set_default_header(header_name: String, value: String) -> void:
	_http_client.add_default_header(header_name, value)

## Remove a default HTTP header
func clear_default_header(header_name: String) -> void:
	_http_client.remove_default_header(header_name)

## Override access token (useful for development/testing)
func set_access_token(token: String) -> void:
	var refresh_token: String = _token_store.get_refresh_token()
	var user_id: String = _token_store.get_user_id()
	_token_store.save(user_id, token, refresh_token)

## Get current SDK state
## @returns: Dictionary {base_url, project_id, user_id, has_tokens, last_error}
func get_state() -> Dictionary:
	return {
		"base_url": _base_url,
		"project_id": _project_id,
		"user_id": _token_store.get_user_id(),
		"has_tokens": _token_store.has_tokens(),
		"last_error": _last_error
	}

## Ensure a guest session exists (create if needed)
## @returns: Dictionary {ok, data: {user_id, access_token, refresh_token}, error}
func ensure_guest() -> Dictionary:
	_check_initialized()
	_debug_log("ensure_guest() called")
	
	# If we already have tokens, consider it success
	if _token_store.has_tokens():
		_debug_log("ensure_guest() - already have tokens, returning existing session")
		return Result.ok({
			"user_id": _token_store.get_user_id(),
			"access_token": _token_store.get_access_token(),
			"refresh_token": _token_store.get_refresh_token()
		})
	
	# Create guest session
	var path: String = _endpoints.guest
	request_started.emit("POST", path)
	
	var result: Dictionary = await _http_client.post(path, {})
	_track_result(result)
	
	if result.ok and result.data != null:
		_store_auth_tokens(result.data)
		_debug_log("ensure_guest() - success, user_id: %s" % result.data.get("user_id", ""))
	else:
		_debug_log("ensure_guest() - failed: %s" % result.get("error", {}))
	
	return result

## Register a new user account
## @returns: Dictionary {ok, data: {user_id, access_token, refresh_token}, error}
func register(email: String, password: String) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.register
	request_started.emit("POST", path)
	
	var body := {
		"email": email,
		"password": password
	}
	
	var result := await _http_client.post(path, body)
	_track_result(result)
	
	if result.ok:
		_store_auth_tokens(result.data)
	
	return result

## Login with email and password
## @returns: Dictionary {ok, data: {user_id, access_token, refresh_token}, error}
func login(email: String, password: String) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.login
	request_started.emit("POST", path)
	
	var body := {
		"email": email,
		"password": password
	}
	
	var result := await _http_client.post(path, body)
	_track_result(result)
	
	if result.ok:
		_store_auth_tokens(result.data)
	
	return result

## Refresh access token using stored refresh token
## @returns: Dictionary {ok, data: {access_token, refresh_token?}, error}
func refresh() -> Dictionary:
	_check_initialized()
	
	if _is_refreshing:
		# Wait for current refresh to complete
		await token_refreshed
		# Return current state
		if _token_store.has_tokens():
			return Result.ok({
				"access_token": _token_store.get_access_token(),
				"refresh_token": _token_store.get_refresh_token()
			})
		else:
			return Result.error("refresh_failed", "Token refresh failed", 0, null)
	
	_is_refreshing = true
	
	var refresh_token: String = _token_store.get_refresh_token()
	if refresh_token == "":
		_is_refreshing = false
		token_refreshed.emit(false)
		return Result.error("no_refresh_token", "No refresh token available", 0, null)
	
	var path: String = _endpoints.refresh
	request_started.emit("POST", path)
	
	var body := {
		"refresh_token": refresh_token
	}
	
	# Don't use Authorization header for refresh (use refresh_token in body)
	var headers := {}
	var result: Dictionary = await _http_client.post(path, body, headers)
	_track_result(result)
	
	if result.ok:
		var new_access: String = result.data.get("access_token", "")
		var new_refresh: String = result.data.get("refresh_token", refresh_token)
		_token_store.update_access_token(new_access, new_refresh)
	else:
		# Refresh failed - clear tokens
		_token_store.clear()
		auth_changed.emit("")
	
	_is_refreshing = false
	token_refreshed.emit(result.ok)
	
	return result

## Logout current user (clears local tokens, attempts server-side revoke)
## @returns: Dictionary {ok, data: {}, error}
func logout() -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.logout
	request_started.emit("POST", path)
	
	# Try to revoke on server (best effort)
	await _authorized_request(HTTPClient.METHOD_POST, path, {})
	
	# Always clear local tokens regardless of server response
	_token_store.clear()
	auth_changed.emit("")
	
	# Return success even if server revoke failed
	return Result.ok({})

## Set a cloud key-value pair
## @param expected_version: Optional version for optimistic locking
## @returns: Dictionary {ok, data: {key, value, version}, error}
func kv_set(key: String, value: Variant, expected_version = null) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.kv_set.replace("{key}", key)
	request_started.emit("PUT", path)
	
	var body := {
		"value": value
	}
	if expected_version != null:
		body.expected_version = expected_version
	
	var result := await _authorized_request(HTTPClient.METHOD_PUT, path, body)
	_track_result(result)
	
	return result

## Get a cloud key-value pair
## @returns: Dictionary {ok, data: {key, value, version}, error}
func kv_get(key: String) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.kv_get.replace("{key}", key)
	request_started.emit("GET", path)
	
	var result := await _authorized_request(HTTPClient.METHOD_GET, path)
	_track_result(result)
	
	return result

## Delete a cloud key-value pair
## @param expected_version: Optional version for optimistic locking
## @returns: Dictionary {ok, data: {}, error}
func kv_delete(key: String, expected_version = null) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.kv_delete.replace("{key}", key)
	if expected_version != null:
		path += "?expected_version=%s" % expected_version
	
	request_started.emit("DELETE", path)
	
	var result := await _authorized_request(HTTPClient.METHOD_DELETE, path)
	_track_result(result)
	
	return result

## Submit a score to a leaderboard
## @returns: Dictionary {ok, data: {best_score, rank}, error}
func leaderboard_submit(board := "default", score: int = 0) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.leaderboard_submit.replace("{board}", board)
	request_started.emit("POST", path)
	
	var body := {
		"score": score
	}
	
	var result := await _authorized_request(HTTPClient.METHOD_POST, path, body)
	_track_result(result)
	
	return result

## Fetch top leaderboard entries
## @returns: Dictionary {ok, data: {entries: [{user_id, score, rank}]}, error}
func leaderboard_top(board := "default", limit := 20) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.leaderboard_top.replace("{board}", board)
	path += "?limit=%d" % limit
	
	request_started.emit("GET", path)
	
	var result := await _authorized_request(HTTPClient.METHOD_GET, path)
	_track_result(result)
	
	return result

## Fetch current user's leaderboard entry
## @returns: Dictionary {ok, data: {user_id, score, rank}, error}
func leaderboard_me(board := "default") -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.leaderboard_me.replace("{board}", board)
	request_started.emit("GET", path)
	
	var result := await _authorized_request(HTTPClient.METHOD_GET, path)
	_track_result(result)
	
	return result

## Fetch remote configuration
## @returns: Dictionary {ok, data: {config, flags}, error}
func config_fetch(platform: String, app_version: String) -> Dictionary:
	_check_initialized()
	
	var path: String = _endpoints.config
	path += "?platform=%s&app_version=%s" % [platform.uri_encode(), app_version.uri_encode()]
	
	request_started.emit("GET", path)
	
	# Config doesn't require auth
	var result: Dictionary = await _http_client.get_request(path)
	_track_result(result)
	
	return result

#endregion

#region Private Helpers

func _check_initialized() -> void:
	if not _initialized:
		push_error("Backend SDK not initialized. Call init() first.")

func _store_auth_tokens(data: Dictionary) -> void:
	var user_id: String = data.get("user_id", "")
	var access_token: String = data.get("access_token", "")
	var refresh_token: String = data.get("refresh_token", "")
	
	_token_store.save(user_id, access_token, refresh_token)
	auth_changed.emit(user_id)

func _authorized_request(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	var headers := {}
	var access_token: String = _token_store.get_access_token()
	
	if access_token != "":
		headers["Authorization"] = "Bearer %s" % access_token
	
	return await _http_client.request(method, path, body, headers)

func _handle_unauthorized(original_request: Dictionary) -> Dictionary:
	# Try to refresh token once
	if _token_store.get_refresh_token() == "":
		return Result.from_error_code(
			Types.ErrorCode.UNAUTHORIZED,
			"Unauthorized and no refresh token available",
			401,
			null
		)
	
	var refresh_result := await refresh()
	
	if not refresh_result.ok:
		return Result.from_error_code(
			Types.ErrorCode.UNAUTHORIZED,
			"Token refresh failed",
			401,
			refresh_result.error
		)
	
	# Retry original request with new token
	var new_access_token: String = _token_store.get_access_token()
	original_request.headers["Authorization"] = "Bearer %s" % new_access_token
	
	return await _http_client.request(
		original_request.method,
		original_request.path,
		original_request.body,
		original_request.headers
	)

func _handle_banned(details: Dictionary) -> void:
	banned_detected.emit(details)

func _on_request_completed(result: Dictionary) -> void:
	# Defensive check - ensure result is valid
	if result == null or not result is Dictionary:
		return
	
	var status := 0
	var ok := result.get("ok", false)
	
	if result.has("error") and result.error != null:
		status = result.error.get("status", 0)
	else:
		status = 200
	
	# Note: We don't have method/path here easily, so emit generic
	request_finished.emit("", "", ok, status)

func _track_result(result: Dictionary) -> void:
	if not result.ok:
		_last_error = result.error

#endregion
