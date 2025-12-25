extends Node

## Smoke tests for GameBackendSDK
## Run this script to verify basic functionality

const TEST_BASE_URL := "http://localhost:3000"
const TEST_PROJECT_ID := "test_project"
const TEST_EMAIL := "smoketest@example.com"
const TEST_PASSWORD := "testpass123"

var backend: Backend
var passed := 0
var failed := 0

func _ready() -> void:
	print("\n=== GameBackendSDK Smoke Tests ===\n")
	
	backend = Backend.new()
	backend.name = "BackendTest"
	add_child(backend)
	
	await get_tree().process_frame
	
	await run_tests()
	
	print("\n=== Test Summary ===")
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)
	print("====================\n")
	
	get_tree().quit()

func run_tests() -> void:
	# Test 1: Initialization
	await test_init()
	
	# Test 2: Result helpers
	test_result_helpers()
	
	# Test 3: Backoff calculation
	test_backoff()
	
	# Test 4: Token store
	test_token_store()
	
	# Test 5: Types and error codes
	test_types()
	
	# Note: Network tests would require a running backend server
	print("\nNote: Network integration tests skipped (require running backend)")

func test_init() -> void:
	print("Test: SDK Initialization")
	
	var result := await backend.init(TEST_BASE_URL, TEST_PROJECT_ID, {
		"timeout_sec": 5,
		"retries": 2
	})
	
	assert_true(result.ok, "Init should succeed")
	
	var state := backend.get_state()
	assert_equals(state.base_url, TEST_BASE_URL, "Base URL should be set")
	assert_equals(state.project_id, TEST_PROJECT_ID, "Project ID should be set")
	
	# Test double init
	var result2 := await backend.init(TEST_BASE_URL, TEST_PROJECT_ID)
	assert_false(result2.ok, "Double init should fail")

func test_result_helpers() -> void:
	print("\nTest: Result Helpers")
	
	var ok_result := BackendResult.ok({"test": "data"})
	assert_true(ok_result.ok, "OK result should have ok=true")
	assert_equals(ok_result.data.test, "data", "OK result should contain data")
	assert_null(ok_result.error, "OK result should have null error")
	
	var error_result := BackendResult.error("test_error", "Test message", 400, {"detail": "info"})
	assert_false(error_result.ok, "Error result should have ok=false")
	assert_null(error_result.data, "Error result should have null data")
	assert_equals(error_result.error.code, "test_error", "Error should have correct code")
	assert_equals(error_result.error.message, "Test message", "Error should have correct message")
	assert_equals(error_result.error.status, 400, "Error should have correct status")

func test_backoff() -> void:
	print("\nTest: Backoff Calculation")
	
	var backoff := BackendBackoff.new(100, 5000)
	
	var delay0 := backoff.delay_for_attempt(0)
	assert_true(delay0 >= 0.09 and delay0 <= 0.11, "First delay should be ~100ms")
	
	var delay1 := backoff.delay_for_attempt(1)
	assert_true(delay1 >= 0.18 and delay1 <= 0.22, "Second delay should be ~200ms")
	
	var delay10 := backoff.delay_for_attempt(10)
	assert_true(delay10 <= 5.5, "Delay should be capped at max_ms")

func test_token_store() -> void:
	print("\nTest: Token Store")
	
	var store := BackendTokenStore.new()
	
	assert_false(store.has_tokens(), "New store should have no tokens")
	assert_equals(store.get_user_id(), "", "New store should have empty user_id")
	
	store.save("user123", "access_xyz", "refresh_abc")
	assert_true(store.has_tokens(), "Store should have tokens after save")
	assert_equals(store.get_user_id(), "user123", "User ID should be saved")
	assert_equals(store.get_access_token(), "access_xyz", "Access token should be saved")
	assert_equals(store.get_refresh_token(), "refresh_abc", "Refresh token should be saved")
	
	store.update_access_token("new_access")
	assert_equals(store.get_access_token(), "new_access", "Access token should be updated")
	assert_equals(store.get_refresh_token(), "refresh_abc", "Refresh token should remain")
	
	store.clear()
	assert_false(store.has_tokens(), "Store should have no tokens after clear")

func test_types() -> void:
	print("\nTest: Types and Error Codes")
	
	var code_str := BackendTypes.error_code_to_string(BackendTypes.ErrorCode.UNAUTHORIZED)
	assert_equals(code_str, "unauthorized", "Error code should convert to string")
	
	var error_code := BackendTypes.status_to_error_code(401)
	assert_equals(error_code, BackendTypes.ErrorCode.UNAUTHORIZED, "401 should map to UNAUTHORIZED")
	
	var error_code_404 := BackendTypes.status_to_error_code(404)
	assert_equals(error_code_404, BackendTypes.ErrorCode.NOT_FOUND, "404 should map to NOT_FOUND")
	
	var error_code_500 := BackendTypes.status_to_error_code(500)
	assert_equals(error_code_500, BackendTypes.ErrorCode.SERVER_ERROR, "500 should map to SERVER_ERROR")

# Assertion helpers

func assert_true(condition: bool, message: String) -> void:
	if condition:
		print("  ✓ %s" % message)
		passed += 1
	else:
		print("  ✗ FAILED: %s" % message)
		failed += 1

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)

func assert_equals(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		print("  ✓ %s" % message)
		passed += 1
	else:
		print("  ✗ FAILED: %s (expected: %s, got: %s)" % [message, expected, actual])
		failed += 1

func assert_null(value: Variant, message: String) -> void:
	if value == null:
		print("  ✓ %s" % message)
		passed += 1
	else:
		print("  ✗ FAILED: %s (expected null, got: %s)" % [message, value])
		failed += 1

