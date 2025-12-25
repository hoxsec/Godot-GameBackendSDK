<p align="center">
  <img src="https://img.shields.io/badge/Godot-4.4+-478CBF?logo=godotengine&logoColor=white" alt="Godot 4.4+">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License">
</p>

<h1 align="center">🎮 GameBackendSDK</h1>

<p align="center">
  <strong>Production-ready Godot 4.4+ addon for custom game backends</strong><br>
  Authentication, Cloud Saves, Leaderboards, and Remote Config
</p>

<p align="center">
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-api-reference">API Reference</a> •
  <a href="#-backend-contract">Backend Contract</a>
</p>

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔐 **Authentication** | Guest login, email/password registration & login, automatic token refresh |
| 💾 **Cloud Saves** | Key-value storage with optimistic locking and versioning |
| 🏆 **Leaderboards** | Submit scores, fetch rankings, get player position |
| ⚙️ **Remote Config** | Platform-specific configuration and feature flags |
| 🔄 **Auto-Retry** | Exponential backoff with jitter on network failures |
| 📦 **Zero Dependencies** | Pure GDScript, no external plugins required |
| 🛡️ **Type-Safe** | Consistent return shapes with comprehensive error handling |

---

## 📦 Installation

### Option 1: Manual Installation

1. Download or clone this repository
2. Copy the `addons/GameBackendSDK/` folder into your Godot project's `addons/` directory
3. Add `Backend.gd` as an autoload singleton:
   - Open **Project Settings** → **Autoload**
   - Path: `res://addons/GameBackendSDK/Backend.gd`
   - Node Name: `Backend`
   - Click **Add**

### Option 2: Git Submodule

```bash
cd your-godot-project
git submodule add https://github.com/hoxsec/Godot-GameBackendSDK.git addons/GameBackendSDK
```

---

## 🚀 Quick Start

```gdscript
extends Node

func _ready() -> void:
    # Initialize the SDK
    var result := await Backend.init("https://api.yourgame.com", "your_project_id", {
        "timeout_sec": 10,
        "retries": 3,
        "debug": true  # Enable debug logging (disable in production)
    })
    
    if not result.ok:
        print("Init failed: ", result.error.message)
        return
    
    # Ensure guest session
    result = await Backend.ensure_guest()
    if result.ok:
        print("Logged in as: ", result.data.user_id)
    
    # Save player data
    result = await Backend.kv_set("player_progress", {
        "level": 5,
        "coins": 1000
    })
    
    # Submit score
    result = await Backend.leaderboard_submit("global", 9999)
    if result.ok:
        print("Your rank: ", result.data.rank)
```

---

## 📚 API Reference

### Initialization

```gdscript
Backend.init(base_url: String, project_id: String, options := {}) -> Dictionary
```

**Options:**
- `timeout_sec: int = 10` - Request timeout in seconds
- `retries: int = 3` - Maximum retry attempts for failed requests
- `backoff_base_ms: int = 100` - Base delay for exponential backoff
- `user_agent: String = "GameBackendSDK/1.0"` - Custom user agent
- `default_headers: Dictionary = {}` - Additional headers for all requests
- `endpoints: Dictionary = {}` - Override default endpoint paths
- `queue_requests: bool = true` - Serialize requests to prevent race conditions
- `debug: bool = false` - Enable debug logging to Godot console

### Authentication

```gdscript
Backend.ensure_guest()                              # Create/retrieve guest session
Backend.register(email: String, password: String)   # Register new account
Backend.login(email: String, password: String)      # Login with credentials
Backend.logout()                                    # Logout current user
Backend.refresh()                                   # Manually refresh access token
```

### Cloud Storage

```gdscript
Backend.kv_set(key: String, value: Variant, expected_version := null)  # Store data
Backend.kv_get(key: String)                                            # Retrieve data
Backend.kv_delete(key: String, expected_version := null)               # Delete data
```

### Leaderboards

```gdscript
Backend.leaderboard_submit(board: String, score: int)  # Submit score
Backend.leaderboard_top(board: String, limit: int)     # Get top entries
Backend.leaderboard_me(board: String)                  # Get player's rank
```

### Remote Config

```gdscript
Backend.config_fetch(platform: String, app_version: String)
```

### Signals

```gdscript
Backend.auth_changed.connect(func(user_id): ...)        # Auth state changed
Backend.request_started.connect(func(method, path): ...) 
Backend.request_finished.connect(func(method, path, ok, status): ...)
Backend.token_refreshed.connect(func(ok): ...)          # Token refresh result
Backend.banned_detected.connect(func(details): ...)     # Account banned
```

---

## 🔗 Backend Contract

This SDK requires a backend that implements the REST API contract. Your backend must provide these endpoints:

### Authentication Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/auth/guest` | Create guest session |
| `POST` | `/v1/auth/register` | Register new user |
| `POST` | `/v1/auth/login` | Login existing user |
| `POST` | `/v1/auth/refresh` | Refresh access token |
| `POST` | `/v1/auth/logout` | Logout (invalidate tokens) |

### Cloud Storage Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/kv/:key` | Get stored value |
| `PUT` | `/v1/kv/:key` | Set value |
| `DELETE` | `/v1/kv/:key` | Delete value |

### Leaderboard Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v1/leaderboards/:board/submit` | Submit score |
| `GET` | `/v1/leaderboards/:board/top` | Get top entries |
| `GET` | `/v1/leaderboards/:board/me` | Get player's rank |

### Configuration Endpoint

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/v1/config` | Get remote config |

**Need a backend?** Check out [GameBackendAPI](https://github.com/hoxsec/Godot-GameBackendAPI) - a reference implementation ready to deploy!

For complete endpoint specifications, see the [Backend Contract Documentation](addons/GameBackendSDK/README.md#backend-contract).

---

## 📖 Return Format

All API methods return a consistent `Dictionary` structure:

```gdscript
{
    "ok": bool,           # true if successful, false if error
    "data": Variant,      # Method-specific data (null on error)
    "error": {            # null if ok=true
        "code": String,       # Error code (e.g., "unauthorized", "network_error")
        "message": String,    # Human-readable error message
        "status": int,        # HTTP status code (0 for non-HTTP errors)
        "details": Variant    # Additional error context
    }
}
```

### Error Codes

- `network_error` - Connection failed, DNS resolution failed, etc.
- `timeout` - Request exceeded timeout limit
- `http_error` - Generic HTTP error (4xx/5xx)
- `unauthorized` - 401 response (invalid/expired token)
- `forbidden` - 403 response (access denied)
- `not_found` - 404 response (resource not found)
- `conflict` - 409 response (version mismatch, duplicate, etc.)
- `rate_limited` - 429 response (too many requests)
- `server_error` - 5xx response (backend error)
- `invalid_response` - Response is not valid JSON
- `banned` - Account has been banned
- `validation_error` - Request validation failed

---

## 🎯 Advanced Features

### Automatic Token Refresh

When a request receives a 401 response and a refresh token exists:
1. The SDK automatically calls the refresh endpoint
2. Updates stored tokens
3. Retries the original request once with the new token
4. Emits `token_refreshed` signal

### Retry Logic

Requests automatically retry on:
- Network errors (connection failed, DNS errors, etc.)
- Server errors (5xx responses)
- Timeouts

Retry behavior:
- Exponential backoff with jitter
- Configurable max attempts
- Automatic cancellation on non-retryable errors

### Request Queueing

By default, requests are queued and processed serially to prevent:
- Token refresh race conditions
- Concurrent writes to the same key
- Server overload

Disable for parallel requests: `queue_requests: false` in init options.

### Token Storage

Tokens are automatically persisted to `user://game_backend_sdk.json` and survive game restarts.

---

## 🎮 Demo Scene

This repository includes a demo scene to test all features:

1. Open `addons/GameBackendSDK/demo/Demo.tscn` in Godot
2. Set your backend URL
3. Click "Initialize SDK" and test all features!

---

## 🧪 Testing

Run automated smoke tests:

```gdscript
# Add as autoload or instantiate
var tests = preload("res://addons/GameBackendSDK/demo/SmokeTest.gd").new()
add_child(tests)
```

---

## 🔧 Troubleshooting

### "SDK not initialized" error
Call `Backend.init()` before any other methods.

### Requests timeout immediately
Check your `timeout_sec` setting and network connectivity.

### 401 errors persist
- Verify backend returns valid tokens
- Check token format (should be Bearer token)
- Ensure refresh endpoint works correctly

### Tokens don't persist
Check that `user://` directory is writable and not cleared between sessions.

---

## 📁 Project Structure

```
GameBackendSDK/
├── addons/
│   └── GameBackendSDK/
│       ├── Backend.gd          # Main SDK singleton
│       ├── internal/
│       │   ├── HttpClient.gd   # HTTP request handling
│       │   ├── TokenStore.gd   # Token persistence
│       │   ├── Result.gd       # Result type helpers
│       │   ├── Types.gd        # Constants & types
│       │   └── Backoff.gd      # Exponential backoff logic
│       ├── demo/
│       │   ├── Demo.tscn       # Interactive demo scene
│       │   └── SmokeTest.gd    # Automated tests
│       └── README.md           # Detailed SDK documentation
├── LICENSE
└── README.md
```

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

## 💬 Support

- 📖 [Full Documentation](addons/GameBackendSDK/README.md)
- 🐛 [Report Issues](https://github.com/hoxsec/Godot-GameBackendSDK/issues)
- 💡 [Request Features](https://github.com/hoxsec/Godot-GameBackendSDK/issues)

---

<p align="center">
  Made with ❤️ for the Godot community
</p>

