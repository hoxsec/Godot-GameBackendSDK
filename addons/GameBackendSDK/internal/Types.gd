class_name BackendTypes
extends RefCounted

## Constants and enums for GameBackendSDK

enum ErrorCode {
	NONE,
	NETWORK_ERROR,
	HTTP_ERROR,
	INVALID_RESPONSE,
	UNAUTHORIZED,
	FORBIDDEN,
	NOT_FOUND,
	CONFLICT,
	RATE_LIMITED,
	SERVER_ERROR,
	TIMEOUT,
	VALIDATION_ERROR,
	BANNED,
	UNKNOWN
}

const ERROR_CODE_STRINGS := {
	ErrorCode.NONE: "",
	ErrorCode.NETWORK_ERROR: "network_error",
	ErrorCode.HTTP_ERROR: "http_error",
	ErrorCode.INVALID_RESPONSE: "invalid_response",
	ErrorCode.UNAUTHORIZED: "unauthorized",
	ErrorCode.FORBIDDEN: "forbidden",
	ErrorCode.NOT_FOUND: "not_found",
	ErrorCode.CONFLICT: "conflict",
	ErrorCode.RATE_LIMITED: "rate_limited",
	ErrorCode.SERVER_ERROR: "server_error",
	ErrorCode.TIMEOUT: "timeout",
	ErrorCode.VALIDATION_ERROR: "validation_error",
	ErrorCode.BANNED: "banned",
	ErrorCode.UNKNOWN: "unknown"
}

const DEFAULT_ENDPOINTS := {
	"guest": "/v1/auth/guest",
	"register": "/v1/auth/register",
	"login": "/v1/auth/login",
	"refresh": "/v1/auth/refresh",
	"logout": "/v1/auth/logout",
	"kv_get": "/v1/kv/{key}",
	"kv_set": "/v1/kv/{key}",
	"kv_delete": "/v1/kv/{key}",
	"leaderboard_submit": "/v1/leaderboards/{board}/submit",
	"leaderboard_top": "/v1/leaderboards/{board}/top",
	"leaderboard_me": "/v1/leaderboards/{board}/me",
	"config": "/v1/config"
}

static func error_code_to_string(code: ErrorCode) -> String:
	return ERROR_CODE_STRINGS.get(code, "unknown")

static func status_to_error_code(status: int) -> ErrorCode:
	match status:
		401:
			return ErrorCode.UNAUTHORIZED
		403:
			return ErrorCode.FORBIDDEN
		404:
			return ErrorCode.NOT_FOUND
		409:
			return ErrorCode.CONFLICT
		429:
			return ErrorCode.RATE_LIMITED
		_:
			if status >= 500:
				return ErrorCode.SERVER_ERROR
			elif status >= 400:
				return ErrorCode.HTTP_ERROR
			else:
				return ErrorCode.UNKNOWN

