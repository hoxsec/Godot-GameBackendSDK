class_name BackendHttpClient
extends Node

## HTTP wrapper with queue, retries, timeout, and automatic token refresh
## REWRITTEN for reliability - each request gets its own HTTPRequest node

const Backoff = preload("res://addons/GameBackendSDK/internal/Backoff.gd")
const Result = preload("res://addons/GameBackendSDK/internal/Result.gd")

signal request_completed(result: Dictionary)

var base_url := ""
var project_id := ""
var timeout_sec := 10
var max_retries := 3
var default_headers := {}
var queue_requests := true
var debug_mode := false

var _backoff: Backoff
var _request_queue: Array[Dictionary] = []
var _is_processing := false

## Callback refs (set by Backend.gd for auto-refresh)
var on_unauthorized: Callable
var on_banned: Callable

func _debug_log(message: String) -> void:
	if debug_mode:
		print("[HttpClient] ", message)

func _init() -> void:
	_backoff = Backoff.new(100, 10000)

## Configure the client
func configure(config: Dictionary) -> void:
	base_url = config.get("base_url", "")
	project_id = config.get("project_id", "")
	timeout_sec = config.get("timeout_sec", 10)
	max_retries = config.get("max_retries", 3)
	queue_requests = config.get("queue_requests", true)
	debug_mode = config.get("debug", false)
	
	if config.has("backoff_base_ms"):
		_backoff = Backoff.new(config.backoff_base_ms, 10000)
	
	_debug_log("Configured: base_url=%s, timeout=%ds, retries=%d" % [base_url, timeout_sec, max_retries])

## Set default headers
func set_default_headers(headers: Dictionary) -> void:
	default_headers = headers.duplicate()

## Add a single default header
func add_default_header(header_name: String, value: String) -> void:
	default_headers[header_name] = value

## Remove a default header
func remove_default_header(header_name: String) -> void:
	default_headers.erase(header_name)

## Make an HTTP request
func request(method: HTTPClient.Method, path: String, body: Variant = null, headers := {}) -> Dictionary:
	var method_name := _method_to_string(method)
	_debug_log("%s %s - queuing request" % [method_name, path])
	
	var req := {
		"method": method,
		"path": path,
		"body": body,
		"headers": headers,
		"signal_emitter": SignalEmitter.new()
	}
	
	add_child(req.signal_emitter)
	
	if queue_requests:
		_request_queue.append(req)
		_process_queue()
	else:
		_execute_request(req)
	
	var result: Dictionary = await req.signal_emitter.completed
	
	if result.ok:
		_debug_log("%s %s - SUCCESS (status: %d)" % [method_name, path, 200])
	else:
		var error_msg: String = result.error.get("message", "unknown error") if result.has("error") else "unknown error"
		var status: int = result.error.get("status", 0) if result.has("error") else 0
		_debug_log("%s %s - FAILED: %s (status: %d)" % [method_name, path, error_msg, status])
	
	return result

## Helper methods for common HTTP verbs
func get_request(path: String, headers := {}) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, path, null, headers)

func post(path: String, body: Variant, headers := {}) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, path, body, headers)

func put(path: String, body: Variant, headers := {}) -> Dictionary:
	return await request(HTTPClient.METHOD_PUT, path, body, headers)

func patch(path: String, body: Variant, headers := {}) -> Dictionary:
	return await request(HTTPClient.METHOD_PATCH, path, body, headers)

func delete(path: String, headers := {}) -> Dictionary:
	return await request(HTTPClient.METHOD_DELETE, path, null, headers)

## Process the request queue
func _process_queue() -> void:
	if _is_processing or _request_queue.is_empty():
		return
	
	_is_processing = true
	var req := _request_queue.pop_front()
	_execute_request(req)

## Execute a single request
func _execute_request(req: Dictionary) -> void:
	# Create a dedicated request executor for this request
	var executor = RequestExecutor.new()
	executor.base_url = base_url
	executor.project_id = project_id
	executor.timeout_sec = timeout_sec
	executor.max_retries = max_retries
	executor.default_headers = default_headers
	executor.backoff = _backoff
	executor.debug_mode = debug_mode
	executor.on_unauthorized = on_unauthorized
	executor.on_banned = on_banned
	
	add_child(executor)
	
	# Execute the request
	var result := await executor.execute(req.method, req.path, req.body, req.headers)
	
	# Clean up executor
	executor.queue_free()
	
	# Complete the request
	req.signal_emitter.complete(result)
	req.signal_emitter.queue_free()
	
	# Mark as not processing and process next in queue
	_is_processing = false
	if queue_requests:
		_process_queue()
	
	request_completed.emit(result)

## Convert HTTP method enum to string
func _method_to_string(method: HTTPClient.Method) -> String:
	match method:
		HTTPClient.METHOD_GET: return "GET"
		HTTPClient.METHOD_POST: return "POST"
		HTTPClient.METHOD_PUT: return "PUT"
		HTTPClient.METHOD_DELETE: return "DELETE"
		HTTPClient.METHOD_PATCH: return "PATCH"
		HTTPClient.METHOD_HEAD: return "HEAD"
		HTTPClient.METHOD_OPTIONS: return "OPTIONS"
		_: return "UNKNOWN"

## Simple signal emitter node
class SignalEmitter extends Node:
	signal completed(result: Dictionary)
	
	func complete(result: Dictionary) -> void:
		completed.emit(result)

## Request executor - handles a single HTTP request with retries and timeout
class RequestExecutor extends Node:
	var base_url := ""
	var project_id := ""
	var timeout_sec := 10
	var max_retries := 3
	var default_headers := {}
	var backoff: Backoff
	var debug_mode := false
	var on_unauthorized: Callable
	var on_banned: Callable
	
	signal execution_completed(result: Dictionary)
	
	var _http_request: HTTPRequest
	var _timeout_timer: Timer
	var _retry_count := 0
	var _completed := false
	var _result: Dictionary = {"ok": false, "error": {"code": "unknown", "message": "Request not completed", "status": 0}}
	var _current_method: HTTPClient.Method
	var _current_path: String
	var _current_body: Variant
	var _current_headers: Dictionary
	
	func _ready() -> void:
		_http_request = HTTPRequest.new()
		add_child(_http_request)
		_http_request.request_completed.connect(_on_http_request_completed)
		
		_timeout_timer = Timer.new()
		add_child(_timeout_timer)
		_timeout_timer.one_shot = true
		_timeout_timer.timeout.connect(_on_timeout)
	
	func _debug_log(message: String) -> void:
		if debug_mode:
			print("[RequestExecutor] ", message)
	
	## Execute the HTTP request
	func execute(method: HTTPClient.Method, path: String, body: Variant, headers: Dictionary) -> Dictionary:
		_current_method = method
		_current_path = path
		_current_body = body
		_current_headers = headers
		
		# Start the request (non-blocking)
		_attempt_request()
		
		# Wait for completion signal
		var result: Dictionary = await execution_completed
		
		# Safety check - ensure we always return a valid Result
		if not result.has("ok"):
			_debug_log("WARNING: Invalid result structure, returning error")
			return Result.error("execution_failed", "Request execution failed", 0, result)
		
		return result
	
	## Attempt the request (with retry support)
	func _attempt_request() -> void:
		if _completed:
			return
		
		var url: String = base_url + _current_path
		var method_name := _method_to_string(_current_method)
		
		_debug_log("%s %s - attempting (try %d/%d)" % [method_name, _current_path, _retry_count + 1, max_retries + 1])
		
		# Build headers
		var headers_array: PackedStringArray = []
		
		# Add default headers
		for key in default_headers:
			headers_array.append("%s: %s" % [key, default_headers[key]])
		
		# Add project_id header
		if project_id != "":
			headers_array.append("X-Project-Id: %s" % project_id)
		
		# Add custom headers
		for key in _current_headers:
			headers_array.append("%s: %s" % [key, _current_headers[key]])
		
		# Prepare body
		var body_data: PackedByteArray = []
		if _current_body != null:
			headers_array.append("Content-Type: application/json")
			var json_str := JSON.stringify(_current_body)
			body_data = json_str.to_utf8_buffer()
			_debug_log("Request body: %s" % json_str)
		
		# Start timeout timer
		_timeout_timer.start(timeout_sec)
		_debug_log("Timeout timer started: %ds" % timeout_sec)
		
		# Make request
		var err := _http_request.request_raw(url, headers_array, _current_method, body_data)
		if err != OK:
			_debug_log("Failed to start request: %s" % error_string(err))
			_timeout_timer.stop()
			_complete(Result.network_error("Failed to start HTTP request: %s" % error_string(err)))
	
	## Handle HTTP request completion
	func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if _completed:
			return
		
		_timeout_timer.stop()
		
		# Check for network errors
		if result != HTTPRequest.RESULT_SUCCESS:
			await _handle_request_error(result, response_code)
			return
		
		# Parse response body
		var body_text := body.get_string_from_utf8()
		var response_data: Variant
		
		if body_text != "":
			var json := JSON.new()
			var parse_result := json.parse(body_text)
			if parse_result == OK:
				response_data = json.data
			else:
				# Invalid JSON
				_complete(Result.invalid_response("Response is not valid JSON", body_text))
				return
		else:
			response_data = null
		
		# Handle HTTP errors
		if response_code >= 400:
			await _handle_http_error(response_code, response_data, body_text)
			return
		
		# Success
		_complete(Result.ok(response_data if response_data != null else {}))
	
	## Handle network/connection errors
	func _handle_request_error(result: int, _response_code: int) -> void:
		if _completed:
			return
		
		var should_retry := false
		
		# Retry on certain network errors
		if result in [
			HTTPRequest.RESULT_CANT_CONNECT,
			HTTPRequest.RESULT_CANT_RESOLVE,
			HTTPRequest.RESULT_CONNECTION_ERROR,
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR
		]:
			should_retry = true
		
		if should_retry and _retry_count < max_retries:
			await _retry_request()
		else:
			var error_msg := "Network error: "
			match result:
				HTTPRequest.RESULT_CANT_CONNECT:
					error_msg += "Can't connect"
				HTTPRequest.RESULT_CANT_RESOLVE:
					error_msg += "Can't resolve hostname"
				HTTPRequest.RESULT_CONNECTION_ERROR:
					error_msg += "Connection error"
				HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
					error_msg += "TLS handshake error"
				HTTPRequest.RESULT_NO_RESPONSE:
					error_msg += "No response"
				HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
					error_msg += "Response too large"
				HTTPRequest.RESULT_REQUEST_FAILED:
					error_msg += "Request failed"
				HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
					error_msg += "Can't open download file"
				HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
					error_msg += "Download write error"
				HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
					error_msg += "Redirect limit reached"
				HTTPRequest.RESULT_TIMEOUT:
					error_msg += "Timeout"
				_:
					error_msg += "Unknown (%d)" % result
			
			_complete(Result.network_error(error_msg, result))
	
	## Handle HTTP error responses
	func _handle_http_error(status: int, response_data: Variant, _body_text: String) -> void:
		if _completed:
			return
		
		# Check for retry on 5xx
		if status >= 500 and _retry_count < max_retries:
			await _retry_request()
			return
		
		# Check for banned status
		if status == 403 and response_data is Dictionary:
			if response_data.get("error", {}).get("code", "") == "banned":
				if on_banned.is_valid():
					on_banned.call(response_data)
		
		# Check for unauthorized (401) - let Backend.gd handle auto-refresh
		if status == 401:
			if on_unauthorized.is_valid():
				# Note: This is handled by Backend.gd, just return unauthorized error
				pass
		
		# Extract error message
		var error_message := "HTTP %d" % status
		var error_details = response_data
		
		if response_data is Dictionary and response_data.has("error"):
			var error_obj = response_data.error
			if error_obj is Dictionary and error_obj.has("message"):
				error_message = error_obj.message
			elif error_obj is String:
				error_message = error_obj
		elif response_data is Dictionary and response_data.has("message"):
			error_message = response_data.message
		
		_complete(Result.http_error(status, error_message, error_details))
	
	## Handle request timeout
	func _on_timeout() -> void:
		if _completed:
			return
		
		_debug_log("Request timeout after %ds (retry %d/%d)" % [timeout_sec, _retry_count + 1, max_retries + 1])
		_http_request.cancel_request()
		
		if _retry_count < max_retries:
			_debug_log("Retrying request after timeout...")
			await _retry_request()
		else:
			_debug_log("Max retries reached, request failed")
			_complete(Result.timeout_error())
	
	## Retry the current request after backoff delay
	func _retry_request() -> void:
		if _completed:
			return
		
		_retry_count += 1
		var delay: float = backoff.delay_for_attempt(_retry_count - 1) / 1000.0  # Convert ms to seconds
		_debug_log("Waiting %0.2fs before retry..." % delay)
		await get_tree().create_timer(delay).timeout
		
		# Attempt the request again
		await _attempt_request()
	
	## Complete the request
	func _complete(result: Dictionary) -> void:
		if _completed:
			return
		
		_completed = true
		_result = result
		_timeout_timer.stop()
		_debug_log("Request completed with ok=%s" % result.get("ok", false))
		
		# Emit completion signal
		execution_completed.emit(result)
	
	## Convert HTTP method enum to string
	func _method_to_string(method: HTTPClient.Method) -> String:
		match method:
			HTTPClient.METHOD_GET: return "GET"
			HTTPClient.METHOD_POST: return "POST"
			HTTPClient.METHOD_PUT: return "PUT"
			HTTPClient.METHOD_DELETE: return "DELETE"
			HTTPClient.METHOD_PATCH: return "PATCH"
			HTTPClient.METHOD_HEAD: return "HEAD"
			HTTPClient.METHOD_OPTIONS: return "OPTIONS"
			_: return "UNKNOWN"
