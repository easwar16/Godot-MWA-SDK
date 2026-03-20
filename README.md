# Godot MWA SDK

GDScript SDK for the Solana [Mobile Wallet Adapter](https://docs.solanamobile.com/getting-started/overview) protocol. Wraps the MWA 2.0 client library so Godot games can authorize wallets, sign transactions, and sign messages on Android using Phantom, Solflare, or any MWA-compatible wallet.

Built for API parity with the [React Native MWA SDK](https://docs.solanamobile.com/react-native/overview). If you've used `transact(wallet => wallet.authorize(...))` in React Native, the Godot equivalent is `MWA.adapter.authorize()`.

## What is Mobile Wallet Adapter?

MWA is a protocol that lets mobile apps communicate with wallet apps on the same device. Instead of embedding a wallet or managing private keys, your game sends signing requests to an external wallet (Phantom, Solflare, etc.) over a local connection. The wallet handles key management and approval UI.

The protocol defines these operations:

- **authorize / reauthorize** - Request permission to interact with a wallet
- **deauthorize** - Revoke a previously granted authorization
- **getCapabilities** - Query what the wallet supports
- **signTransactions** - Get transactions signed without broadcasting
- **signAndSendTransactions** - Get transactions signed and submitted to the network
- **signMessages** - Sign arbitrary off-chain messages

Each operation opens the wallet app briefly for user approval, then returns control to your game.

## How Authorization Works

When your game calls `authorize()`, the wallet app opens and asks the player to approve the connection. On success, the wallet returns an **authorization token** - an opaque string that represents the player's approval.

This token matters because:

1. **Subsequent operations use it.** Every `signTransactions` or `signMessages` call includes the auth token so the wallet knows this game was already approved.
2. **It can expire.** Wallets may invalidate tokens after some time. When that happens, the SDK automatically passes the cached token on the next `authorize()` call, and the wallet may upgrade it without showing a prompt (reauthorization).
3. **It should be cached.** If the player closes your game and reopens it, you don't want to force another wallet approval. The SDK caches the token to `user://mwa_auth_cache.json` by default.

The full lifecycle looks like this:

```
authorize()  -->  wallet approves  -->  token cached
    |
    v
sign_transactions() / sign_messages() / sign_and_send_transactions()
    |
    v
[player closes game, reopens later]
    |
    v
reconnect()  -->  uses cached token  -->  wallet reauthorizes silently
    |
    v
deauthorize()  -->  token revoked  -->  cache cleared
```

## Quick Start

### 1. Set up your dapp identity

```gdscript
func _ready():
    # This is what the wallet shows to the player during authorization.
    # Use your game's name, website, and icon.
    MWA.adapter.identity = MWATypes.DappIdentity.new(
        "My Game",              # Display name
        "https://mygame.com",   # URI identifying your game
        "icon.png"              # Icon (relative path or URL)
    )
    MWA.adapter.cluster = MWATypes.Cluster.DEVNET
```

### 2. Connect to a wallet

```gdscript
    # Signal-based (traditional Godot pattern)
    MWA.adapter.authorized.connect(_on_authorized)
    MWA.adapter.authorization_failed.connect(_on_auth_failed)
    MWA.adapter.authorize()

func _on_authorized(result):
    print("Wallet connected: ", result.accounts[0].address)

func _on_auth_failed(error_code: int, error_message: String):
    match error_code:
        MWATypes.ErrorCode.NO_WALLET_FOUND:
            print("No wallet app installed")
        MWATypes.ErrorCode.USER_DECLINED:
            print("Player declined the connection")
        MWATypes.ErrorCode.TIMEOUT:
            print("Wallet didn't respond in time")
```

### 3. Or use await (GDScript 4)

```gdscript
    # Await-based (less boilerplate, good for linear flows)
    var result = await MWA.adapter.authorize_async()
    if result.success:
        print("Connected: ", result.data.accounts[0].address)
    else:
        print("Failed: ", result.error_message)
```

### 4. Sign a transaction

```gdscript
    var tx_bytes: PackedByteArray = build_your_transaction()
    MWA.adapter.sign_and_send_transactions([tx_bytes])
```

### Common mistakes

- **Forgetting to set identity.** The wallet shows "Unknown dApp" if identity is not set.
- **Wrong cluster.** If your wallet is on Mainnet but your game sets `DEVNET`, authorization fails.
- **Calling sign methods before authorize.** The SDK emits an `AUTHORIZATION_FAILED` error. Always authorize first.
- **Not handling errors.** Always connect both the success and failure signal, or use the `_async()` variant which returns both in a single `Result`.

## Installation

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for the full setup guide.

### Quick setup (recommended)

Run the setup script from the project root:

```bash
./setup.sh
```

This automatically handles all build steps: extracting `godot-lib.aar`, installing the Android build template, building the Kotlin plugin, and generating the debug keystore. After it completes, open the project in Godot and configure the Android export preset (see script output for settings).

### Manual setup

1. Copy `addons/solana_mwa/` into your project
2. Enable the plugin in Project Settings > Plugins
3. Install the Android build template (Project > Install Android Build Template, or run `setup.sh`)
4. Extract `godot-lib.template_release.aar` from your export templates into `android/plugin/libs/`
5. Build the Kotlin plugin: `cd android && ./gradlew :plugin:assembleRelease`
6. Copy the AAR to `android/plugins/` with a `.gdap` manifest
7. Configure Android export with Gradle build enabled

The `godot-lib.aar`, Android build template, and export templates must all match your Godot editor version. See the troubleshooting section in INSTALLATION.md if you get version mismatch errors.

## API Overview

Access everything through the `MWA.adapter` singleton, which is registered automatically when you enable the plugin.

### Connection

| Method | Description |
|--------|-------------|
| `authorize(sign_in_payload?)` | Connect to a wallet. Reauthorizes automatically if a cached token exists. |
| `deauthorize()` | Disconnect and revoke the auth token. Clears the cache. |
| `disconnect_wallet()` | Alias for `deauthorize()`. |
| `reconnect()` | Load cached token and call `authorize()`. Falls back to fresh auth if no cache. |

### Signing

| Method | Description |
|--------|-------------|
| `sign_transactions(payloads)` | Sign one or more transactions. Returns signed bytes. Does not broadcast. |
| `sign_and_send_transactions(payloads, options?)` | Sign and submit to the network. Returns transaction signatures. |
| `sign_messages(messages, addresses?)` | Sign arbitrary off-chain messages. Defaults to the first authorized account. |

### Session Batching

These combine authorization and signing into a single wallet interaction. The player sees the wallet open once instead of twice.

| Method | Description |
|--------|-------------|
| `authorize_and_sign_transactions(payloads, sign_in_payload?)` | Authorize, then sign transactions in one session. |
| `authorize_and_sign_and_send_transactions(payloads, sign_in_payload?, options?)` | Authorize, then sign and send in one session. |
| `authorize_and_sign_messages(messages, addresses?, sign_in_payload?)` | Authorize, then sign messages in one session. |

### Async Wrappers

Every method above has an `_async()` variant that returns `MWATypes.Result` and works with `await`:

```gdscript
var r = await MWA.adapter.authorize_async()
var r = await MWA.adapter.sign_transactions_async([tx])
var r = await MWA.adapter.authorize_and_sign_transactions_async([tx])
# etc.
```

### Query and State

| Method / Property | Description |
|--------|-------------|
| `get_capabilities()` | Query wallet features (batch limits, supported versions, etc.) |
| `is_authorized()` | Returns `true` if a valid auth token exists. |
| `is_wallet_connected()` | Returns `true` if state is CONNECTED and authorized. |
| `is_busy()` | Returns `true` if an operation is in flight. |
| `get_account()` | Returns the primary authorized account, or `null`. |
| `get_accounts()` | Returns all authorized accounts. |
| `get_public_key()` | Returns the primary account's public key as `PackedByteArray`. |
| `state` | Current `ConnectionState`: DISCONNECTED, CONNECTING, CONNECTED, SIGNING, DEAUTHORIZING. |
| `timeout_seconds` | Configurable timeout (default: 30s). Applies to both Kotlin and GDScript layers. |
| `debug_logging` | Set to `true` to print `[MWA]` logs and emit the `debug_log` signal. |

### Signals

Every operation emits a pair of success/failure signals:

| Signal | Emitted when |
|--------|-------------|
| `authorized(result)` | Wallet approved the connection |
| `authorization_failed(code, message)` | Authorization was denied or failed |
| `deauthorized()` | Successfully disconnected |
| `deauthorization_failed(message)` | Disconnect failed |
| `capabilities_received(capabilities)` | Wallet capabilities returned |
| `capabilities_failed(code, message)` | Capabilities query failed |
| `transactions_signed(signed_payloads)` | Transactions signed |
| `transactions_sign_failed(code, message)` | Signing failed |
| `transactions_sent(signatures)` | Transactions sent to network |
| `transactions_send_failed(code, message)` | Send failed |
| `messages_signed(signatures)` | Messages signed |
| `messages_sign_failed(code, message)` | Message signing failed |
| `state_changed(new_state)` | Connection state changed |
| `debug_log(message)` | Debug message (when `debug_logging = true`) |

### Error Codes

The SDK classifies errors so you can distinguish between user actions and system failures:

| Code | Name | Meaning |
|------|------|---------|
| -1 | `AUTHORIZATION_FAILED` | Generic wallet/protocol error |
| -8 | `BUSY` | Another operation is already in progress |
| -10 | `NO_WALLET_FOUND` | No MWA-compatible wallet is installed |
| -11 | `TIMEOUT` | Wallet didn't respond within `timeout_seconds` |
| -12 | `USER_DECLINED` | Player explicitly rejected the request |
| -13 | `NOT_INITIALIZED` | Android plugin not set up correctly |

## Authorization Cache

### Why cache?

Without caching, every time your game starts it would force the player to open their wallet and approve the connection again. The cache stores the auth token locally so `reconnect()` can silently reauthorize.

### Default: MWAFileCache

The SDK ships with `MWAFileCache`, which writes to `user://mwa_auth_cache.json`. This is Godot's sandboxed user directory (not world-readable on Android). It's enabled by default.

```gdscript
# This happens automatically. You don't need to write this code.
# Shown here to explain the behavior.

# On successful auth:
auth_cache.set_authorization(current_auth)

# On app startup:
var cached = auth_cache.get_authorization()
if cached != null and cached.auth_token != "":
    current_auth = cached  # Ready for reconnect()

# On deauthorize:
auth_cache.clear()
```

### Custom cache backends

Extend `MWACache` to store tokens however you want:

```gdscript
class_name EncryptedCache
extends MWACache

func get_authorization() -> Variant:
    # Read from encrypted storage, return AuthorizationResult or null
    return null

func set_authorization(auth) -> void:
    # Write to encrypted storage
    pass

func clear() -> void:
    # Delete from storage
    pass
```

Swap it at runtime:

```gdscript
MWA.adapter.set_cache(EncryptedCache.new())
```

The abstract interface has four methods: `get_authorization()`, `set_authorization(auth)`, `clear()`, and `has_authorization()` (which has a default implementation that calls `get_authorization()` and checks for a non-empty token).

## Example App

The `example/` directory contains a demo app that exercises every SDK method. It includes:

- **Cluster selector** (Devnet, Mainnet, Testnet)
- **Connect / Disconnect / Reconnect** buttons
- **API method buttons** for capabilities, sign tx, sign and send, sign message, clone auth
- **Cache controls** to clear the stored authorization
- **Output log** with color-coded results and timestamps
- **Debug logging** enabled by default, showing internal SDK state transitions

### Running it

1. Follow the [Installation guide](docs/INSTALLATION.md)
2. The project's main scene is already set to `example/scenes/main.tscn`
3. Export to Android and install on a device/emulator with a wallet app

### What to test

1. **Connect** - Tap Connect, approve in wallet, verify status turns green
2. **Reconnect** - Close and reopen the app, tap Reconnect, verify it connects without wallet prompt
3. **Sign Transaction** - After connecting, tap Sign Tx (sends dummy bytes, wallet will show an error about invalid transaction format, which is expected)
4. **Sign Message** - Tap Sign Message, approve in wallet, verify signature appears in log
5. **Disconnect** - Tap Disconnect, verify status turns red and cache is cleared
6. **Error handling** - Try connecting with no wallet installed, verify `NO_WALLET_FOUND` error

## Project Structure

```
addons/solana_mwa/              # GDScript plugin (copy this into your project)
  plugin.cfg                    # Plugin metadata (name, version)
  plugin.gd                    # Registers MWA autoload on enable
  scripts/
    mobile_wallet_adapter.gd   # Main API: signals, methods, polling
    mwa_types.gd               # Enums, data classes, Result type
    mwa_cache.gd               # Abstract cache interface
    mwa_file_cache.gd          # File-based cache implementation
    mwa_autoload.gd            # Creates MWA.adapter singleton

android/                        # Kotlin Android plugin (builds to .aar)
  build.gradle.kts             # Root Gradle config (AGP 8.5, Kotlin 2.1)
  settings.gradle.kts          # Repository config (Maven Central, jitpack)
  gradlew + gradle/wrapper/    # Gradle 8.7 wrapper
  plugin/
    build.gradle.kts           # Plugin deps (MWA clientlib-ktx 2.0.3)
    src/main/
      AndroidManifest.xml      # Plugin registration
      java/com/solana/mwa/godot/
        SolanaMWAPlugin.kt     # @UsedByGodot bridge methods
        MWAClient.kt           # Coroutine-based MWA client

example/                        # Demo app
  scenes/main.tscn             # UI layout
  scripts/main.gd              # Signal handlers, button wiring

docs/
  INSTALLATION.md              # Build and setup guide
  API_REFERENCE.md             # Full API docs with React Native parity matrix
  EXAMPLES.md                  # Code examples for common flows
```

## Design Decisions

**Signals, not callbacks.** Godot's signal system is the standard way to handle async events. Every wallet operation emits a success or failure signal. This is the Godot equivalent of React Native's Promise pattern, and it integrates naturally with the editor's signal connection UI.

**Polling, not JNI callbacks.** The Kotlin layer runs wallet operations on coroutines (`Dispatchers.IO`) and writes results to `@Volatile` fields. GDScript reads these in `_process()`. This avoids threading issues with JNI callbacks into Godot's single-threaded main loop.

**Abstract cache.** The `MWACache` base class has no dependencies on file I/O, encryption, or storage format. The default `MWAFileCache` is simple JSON on disk. For games that need encrypted storage, a database backend, or server-side token management, you extend the base class without touching the SDK.

**Classified error codes.** React Native's MWA SDK distinguishes between "no wallet found" and "user declined." The Godot SDK does the same. This lets you show "Please install Phantom" vs "You cancelled the request" instead of a generic "Something went wrong."

**Session batching.** The MWA protocol requires opening a `transact()` session for each operation. Without batching, authorize + sign = 2 wallet opens. The `authorize_and_sign_*` methods perform both in a single session, so the player sees the wallet once.

**Concurrent operation guard.** Both the GDScript and Kotlin layers prevent overlapping operations. If you call `sign_transactions()` while `authorize()` is still running, the SDK emits a `BUSY` error immediately instead of corrupting state.

## React Native Parity

| React Native | Godot | Status |
|-------------|-------|--------|
| `transact(w => w.authorize({...}))` | `MWA.adapter.authorize()` | Supported |
| `transact(w => w.reauthorize({...}))` | `MWA.adapter.authorize()` (automatic with cached token) | Supported |
| `transact(w => w.deauthorize({...}))` | `MWA.adapter.deauthorize()` | Supported |
| `transact(w => w.getCapabilities())` | `MWA.adapter.get_capabilities()` | Supported |
| `transact(w => w.signTransactions({...}))` | `MWA.adapter.sign_transactions([...])` | Supported |
| `transact(w => w.signAndSendTransactions({...}))` | `MWA.adapter.sign_and_send_transactions([...])` | Supported |
| `transact(w => w.signMessages({...}))` | `MWA.adapter.sign_messages([...])` | Supported |
| `transact(w => w.cloneAuthorization())` | `MWA.adapter.clone_authorization()` | Deprecated in MWA 2.0 |
| Session persistence via `authTokenStore` | `MWA.adapter.auth_cache` + `reconnect()` | Supported |
| Sign In With Solana | `MWA.adapter.authorize(siws_payload)` | Supported |

## Requirements

- Godot 4.3+
- Android device or emulator with an MWA-compatible wallet (Phantom, Solflare)
- Android SDK 24+ (Android 7.0)
- Java JDK 17 (for building the Kotlin plugin)

## Future Improvements

- **iOS support.** MWA is Android-only today. If Solana Mobile releases an iOS MWA client, the GDScript layer is ready; only the native bridge needs replacement.
- **Transaction building.** The SDK handles signing but not transaction construction. A companion library for building Solana transactions in GDScript would make end-to-end flows possible without a backend.
- **GDExtension port.** The current JNI bridge adds some latency. A C++ GDExtension wrapping the MWA protocol directly could reduce overhead, though the current approach is fast enough for typical game flows.

## Documentation

- [Installation Guide](docs/INSTALLATION.md) - Setup, building, troubleshooting
- [API Reference](docs/API_REFERENCE.md) - Complete method and signal documentation
- [Examples](docs/EXAMPLES.md) - Code samples for common patterns

## License

MIT
