# API Reference

> This documentation follows the same structure as the [React Native MWA SDK](https://docs.solanamobile.com/react-native/overview) to ensure parity and ease of migration.

## MobileWalletAdapter

The main class providing full MWA 2.0 API parity with the React Native SDK. Access via the `MWA.adapter` autoload singleton.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `identity` | `MWATypes.DappIdentity` | Dapp identity presented to wallet during authorization |
| `cluster` | `int` (MWATypes.Cluster) | Blockchain cluster (DEVNET, MAINNET, TESTNET) |
| `auth_cache` | `MWACache` | Authorization cache implementation (default: `MWAFileCache`) |
| `state` | `int` (MWATypes.ConnectionState) | Current connection state (read-only) |
| `current_auth` | `MWATypes.AuthorizationResult` | Current authorization result (read-only) |
| `capabilities` | `MWATypes.WalletCapabilities` | Last queried wallet capabilities (read-only) |

---

## Wallet Methods

> These methods map 1:1 to the React Native SDK's `transact()` callback methods.

### authorize(sign_in_payload = null)

Authorize the dapp with a wallet. If a cached auth token exists, attempts reauthorization first (equivalent to React Native's `transact → authorize/reauthorize`).

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.authorize({...}))` | `MWA.adapter.authorize()` |
| `transact(wallet => wallet.reauthorize({...}))` | `MWA.adapter.authorize()` (automatic with cached token) |

```gdscript
# Basic authorize
MWA.adapter.authorize()

# With Sign In With Solana payload
var siws = MWATypes.SignInPayload.new()
siws.domain = "myapp.com"
siws.statement = "Sign in to My App"
MWA.adapter.authorize(siws)
```

**Signals:** `authorized(result)`, `authorization_failed(error_code, error_message)`

---

### deauthorize()

Revoke the auth token and disconnect from the wallet. Clears the authorization cache. Equivalent to React Native's `transact → deauthorize`.

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.deauthorize({auth_token}))` | `MWA.adapter.deauthorize()` |

```gdscript
MWA.adapter.deauthorize()
```

**Signals:** `deauthorized()`, `deauthorization_failed(error_message)`

---

### disconnect_wallet()

Alias for `deauthorize()`. Provided for convenience.

---

### reconnect()

Restore a session from the authorization cache. If no cached token exists, falls back to full `authorize()`. This has no direct React Native equivalent — it's a convenience method that combines cache lookup + reauthorize.

```gdscript
MWA.adapter.reconnect()
```

**Signals:** Same as `authorize()`

---

### get_capabilities()

Query the wallet's supported methods, transaction limits, and features. Equivalent to React Native's `transact → getCapabilities`.

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.getCapabilities())` | `MWA.adapter.get_capabilities()` |

```gdscript
MWA.adapter.get_capabilities()
```

**Signals:** `capabilities_received(capabilities)`

---

### sign_transactions(payloads: Array)

Sign one or more transactions without submitting to the network. Equivalent to React Native's `transact → signTransactions`.

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.signTransactions({payloads}))` | `MWA.adapter.sign_transactions([tx_bytes])` |

```gdscript
var tx_bytes: PackedByteArray = build_transaction()
MWA.adapter.sign_transactions([tx_bytes])
```

**Signals:** `transactions_signed(signed_payloads)`, `transactions_sign_failed(error_code, error_message)`

---

### sign_and_send_transactions(payloads: Array, options = null)

Sign and send transactions to the Solana network. The wallet handles submission. Equivalent to React Native's `transact → signAndSendTransactions`.

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.signAndSendTransactions({payloads, options}))` | `MWA.adapter.sign_and_send_transactions([tx_bytes], opts)` |

```gdscript
var tx_bytes: PackedByteArray = build_transaction()
var opts = MWATypes.SendOptions.new()
opts.commitment = "confirmed"
opts.skip_preflight = false
MWA.adapter.sign_and_send_transactions([tx_bytes], opts)
```

**Signals:** `transactions_sent(signatures)`, `transactions_send_failed(error_code, error_message)`

---

### sign_messages(messages: Array, addresses: PackedStringArray = [])

Sign arbitrary messages (off-chain). Defaults to the first authorized account if no addresses specified. Equivalent to React Native's `transact → signMessages`.

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.signMessages({payloads, addresses}))` | `MWA.adapter.sign_messages([msg_bytes])` |

```gdscript
var msg = "Hello Solana!".to_utf8_buffer()
MWA.adapter.sign_messages([msg])
```

**Signals:** `messages_signed(signatures)`, `messages_sign_failed(error_code, error_message)`

---

### clone_authorization()

Clone the current auth token for use in another session.

> **Note:** `cloneAuthorization` has been deprecated in MWA 2.0. This method returns an error message explaining the deprecation. It is included for API completeness.

| React Native SDK | Godot SDK |
|-----------------|-----------|
| `transact(wallet => wallet.cloneAuthorization())` | `MWA.adapter.clone_authorization()` |

**Signals:** `authorization_cloned(auth_token)`, `clone_failed(error_message)`

---

## Helper Methods

| Method | Return Type | Description |
|--------|-----------|-------------|
| `is_authorized()` | `bool` | Returns true if a valid auth token exists |
| `is_wallet_connected()` | `bool` | Returns true if connected with active authorization |
| `get_account()` | `MWATypes.Account` or `null` | Returns the primary authorized account |
| `get_accounts()` | `Array` | Returns all authorized accounts |
| `get_public_key()` | `PackedByteArray` | Returns the public key of the primary account |
| `set_cache(cache: MWACache)` | `void` | Replace the authorization cache at runtime |

---

## Signals

All wallet operations are asynchronous and use Godot's signal system (equivalent to React Native's Promise/callback pattern).

| Signal | Parameters | Description |
|--------|-----------|-------------|
| `authorized` | `result` | Wallet authorized the dapp |
| `authorization_failed` | `error_code: int, error_message: String` | Authorization was denied or failed |
| `deauthorized` | — | Successfully deauthorized |
| `deauthorization_failed` | `error_message: String` | Deauthorization failed |
| `capabilities_received` | `capabilities` | Wallet capabilities returned |
| `transactions_signed` | `signed_payloads: Array` | Transactions signed successfully |
| `transactions_sign_failed` | `error_code: int, error_message: String` | Transaction signing failed |
| `transactions_sent` | `signatures: Array` | Transactions sent to network |
| `transactions_send_failed` | `error_code: int, error_message: String` | Send failed |
| `messages_signed` | `signatures: Array` | Messages signed successfully |
| `messages_sign_failed` | `error_code: int, error_message: String` | Message signing failed |
| `authorization_cloned` | `auth_token: String` | Auth token cloned (deprecated in MWA 2.0) |
| `clone_failed` | `error_message: String` | Clone failed |
| `state_changed` | `new_state: int` | Connection state changed |

---

## Data Types (MWATypes)

### Cluster

```gdscript
enum Cluster { DEVNET = 0, MAINNET = 1, TESTNET = 2 }
```

### ConnectionState

```gdscript
enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, SIGNING, DEAUTHORIZING }
```

### ErrorCode

```gdscript
enum ErrorCode {
    AUTHORIZATION_FAILED = -1,
    INVALID_PAYLOADS = -2,
    NOT_SIGNED = -3,
    NOT_SUBMITTED = -4,
    NOT_CLONED = -5,
    TOO_MANY_PAYLOADS = -6,
    CLUSTER_NOT_SUPPORTED = -7,
}
```

### DappIdentity

```gdscript
var id = MWATypes.DappIdentity.new("App Name", "https://app.com", "icon.png")
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Display name of your dapp |
| `uri` | `String` | URI identifying your dapp |
| `icon` | `String` | Path to your dapp's icon |

### Account

| Field | Type | Description |
|-------|------|-------------|
| `address` | `String` | Base64-encoded public key |
| `public_key` | `PackedByteArray` | Raw public key bytes |
| `label` | `String` | Human-readable label |
| `chains` | `PackedStringArray` | Supported chains (e.g., `["solana:mainnet"]`) |
| `features` | `PackedStringArray` | Supported features |

### AuthorizationResult

| Field | Type | Description |
|-------|------|-------------|
| `accounts` | `Array` | Array of `Account` objects |
| `auth_token` | `String` | Opaque authorization token for reauthorization |
| `wallet_uri_base` | `String` | Wallet endpoint URI |
| `sign_in_result` | `Dictionary` | SIWS result (if Sign In With Solana was used) |

### WalletCapabilities

| Field | Type | Description |
|-------|------|-------------|
| `supports_clone_authorization` | `bool` | Whether wallet supports clone auth (deprecated) |
| `supports_sign_and_send_transactions` | `bool` | Whether wallet can sign + send in one step |
| `max_transactions_per_request` | `int` | Maximum batch size for transactions |
| `max_messages_per_request` | `int` | Maximum batch size for messages |
| `supported_transaction_versions` | `PackedStringArray` | Supported tx versions ("legacy", "0", etc.) |
| `features` | `PackedStringArray` | Optional feature flags |

### SendOptions

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `min_context_slot` | `int` | -1 (unset) | Wait for this slot before sending |
| `commitment` | `String` | `"confirmed"` | Commitment level |
| `skip_preflight` | `bool` | `false` | Skip preflight simulation |
| `max_retries` | `int` | -1 (unset) | Maximum retry attempts |

---

## Authorization Cache

The SDK provides an extensible cache layer for persisting auth tokens across app restarts, matching the session persistence features of the React Native SDK.

### MWACache (Abstract Base Class)

Extend this class to implement custom cache backends (file, database, encrypted storage, etc.).

```gdscript
class_name MyCustomCache
extends MWACache

func get_authorization():
    # Return cached MWATypes.AuthorizationResult or null
    return null

func set_authorization(auth) -> void:
    # Store the authorization result
    pass

func clear() -> void:
    # Delete cached authorization
    pass

func has_authorization() -> bool:
    # Built-in: checks if get_authorization() returns non-null with valid token
    return super.has_authorization()
```

### Built-in: MWAFileCache

The default cache implementation. Persists to `user://mwa_auth_cache.json` using Godot's sandboxed user directory. Automatically serializes/deserializes `AuthorizationResult`.

### Swapping Cache at Runtime

```gdscript
# Replace with your custom implementation
MWA.adapter.set_cache(MyEncryptedCache.new())
```

---

## React Native SDK Parity Matrix

| React Native Method | Godot SDK Method | Status |
|--------------------|-----------------|--------|
| `transact(wallet => wallet.authorize({...}))` | `MWA.adapter.authorize()` | Supported |
| `transact(wallet => wallet.reauthorize({...}))` | `MWA.adapter.authorize()` (automatic) | Supported |
| `transact(wallet => wallet.deauthorize({...}))` | `MWA.adapter.deauthorize()` | Supported |
| `transact(wallet => wallet.getCapabilities())` | `MWA.adapter.get_capabilities()` | Supported |
| `transact(wallet => wallet.signTransactions({...}))` | `MWA.adapter.sign_transactions([...])` | Supported |
| `transact(wallet => wallet.signAndSendTransactions({...}))` | `MWA.adapter.sign_and_send_transactions([...])` | Supported |
| `transact(wallet => wallet.signMessages({...}))` | `MWA.adapter.sign_messages([...])` | Supported |
| `transact(wallet => wallet.cloneAuthorization())` | `MWA.adapter.clone_authorization()` | Deprecated in MWA 2.0 |
| Session persistence | `MWA.adapter.auth_cache` + `reconnect()` | Supported |
| Disconnect flow | `MWA.adapter.deauthorize()` / `disconnect_wallet()` | Supported |
