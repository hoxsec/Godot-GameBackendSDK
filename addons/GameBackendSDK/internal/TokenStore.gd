class_name BackendTokenStore
extends RefCounted

## Persistent token storage using user:// directory

const STORE_PATH := "user://game_backend_sdk.json"

var _data := {
	"user_id": "",
	"access_token": "",
	"refresh_token": ""
}

func _init() -> void:
	load_from_disk()

## Save tokens and user_id to disk
func save(user_id: String, access_token: String, refresh_token: String) -> void:
	_data.user_id = user_id
	_data.access_token = access_token
	_data.refresh_token = refresh_token
	_write_to_disk()

## Update only access token (used during refresh)
func update_access_token(access_token: String, refresh_token := "") -> void:
	_data.access_token = access_token
	if refresh_token != "":
		_data.refresh_token = refresh_token
	_write_to_disk()

## Clear all stored tokens
func clear() -> void:
	_data.user_id = ""
	_data.access_token = ""
	_data.refresh_token = ""
	_write_to_disk()

## Get current user_id
func get_user_id() -> String:
	return _data.user_id

## Get current access_token
func get_access_token() -> String:
	return _data.access_token

## Get current refresh_token
func get_refresh_token() -> String:
	return _data.refresh_token

## Check if we have valid tokens
func has_tokens() -> bool:
	return _data.access_token != "" and _data.refresh_token != ""

## Load tokens from disk
func load_from_disk() -> void:
	if not FileAccess.file_exists(STORE_PATH):
		return
	
	var file := FileAccess.open(STORE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Failed to open token store: %s" % FileAccess.get_open_error())
		return
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_warning("Failed to parse token store JSON")
		return
	
	var parsed_data: Variant = json.data
	if parsed_data is Dictionary:
		_data.user_id = parsed_data.get("user_id", "")
		_data.access_token = parsed_data.get("access_token", "")
		_data.refresh_token = parsed_data.get("refresh_token", "")

## Write current data to disk
func _write_to_disk() -> void:
	var file := FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write token store: %s" % FileAccess.get_open_error())
		return
	
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()

