class_name BackendResult
extends RefCounted

## Result factory helpers for consistent return shapes

const Types = preload("res://addons/GameBackendSDK/internal/Types.gd")

static func ok(data: Variant = {}) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"error": null
	}

static func error(code: String, message: String, status := 0, details: Variant = null) -> Dictionary:
	return {
		"ok": false,
		"data": null,
		"error": {
			"code": code,
			"message": message,
			"status": status,
			"details": details
		}
	}

static func from_error_code(error_code: Types.ErrorCode, message: String, status := 0, details: Variant = null) -> Dictionary:
	var code_str := Types.error_code_to_string(error_code)
	return error(code_str, message, status, details)

static func network_error(message: String, details: Variant = null) -> Dictionary:
	return from_error_code(Types.ErrorCode.NETWORK_ERROR, message, 0, details)

static func timeout_error(message := "Request timed out") -> Dictionary:
	return from_error_code(Types.ErrorCode.TIMEOUT, message, 0, null)

static func invalid_response(message: String, details: Variant = null) -> Dictionary:
	return from_error_code(Types.ErrorCode.INVALID_RESPONSE, message, 0, details)

static func http_error(status: int, message: String, details: Variant = null) -> Dictionary:
	var error_code := Types.status_to_error_code(status)
	return from_error_code(error_code, message, status, details)

