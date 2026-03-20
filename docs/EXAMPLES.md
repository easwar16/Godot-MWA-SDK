# Examples

## Basic Connect / Disconnect

```gdscript
extends Node

func _ready():
    MWA.adapter.identity = MWATypes.DappIdentity.new("My Game", "https://mygame.com", "icon.png")
    MWA.adapter.cluster = MWATypes.Cluster.DEVNET
    MWA.adapter.authorized.connect(_on_authorized)
    MWA.adapter.deauthorized.connect(_on_deauthorized)

func connect_wallet():
    MWA.adapter.authorize()

func disconnect_wallet():
    MWA.adapter.deauthorize()

func _on_authorized(result: MWATypes.AuthorizationResult):
    var pubkey = result.accounts[0].address
    print("Connected: ", pubkey)

func _on_deauthorized():
    print("Disconnected")
```

## Reconnect from Cache

```gdscript
func _ready():
    # Check if we have a cached session.
    if MWA.adapter.auth_cache.has_authorization():
        print("Found cached session, reconnecting...")
        MWA.adapter.reconnect()
    else:
        print("No cached session, need fresh authorization")
        MWA.adapter.authorize()
```

## Sign and Send a Transaction

```gdscript
func send_sol(to_pubkey: PackedByteArray, lamports: int):
    # Build your Solana transaction bytes here.
    var tx_bytes: PackedByteArray = build_transfer_tx(to_pubkey, lamports)

    MWA.adapter.transactions_sent.connect(_on_sent, CONNECT_ONE_SHOT)
    MWA.adapter.transactions_send_failed.connect(_on_send_failed, CONNECT_ONE_SHOT)
    MWA.adapter.sign_and_send_transactions([tx_bytes])

func _on_sent(signatures: Array):
    var sig = Marshalls.raw_to_base64(signatures[0])
    print("Transaction confirmed! Signature: ", sig)

func _on_send_failed(code: int, msg: String):
    print("Send failed: ", msg)
```

## Sign a Message

```gdscript
func verify_ownership():
    var message = "Prove you own this wallet".to_utf8_buffer()
    MWA.adapter.messages_signed.connect(_on_message_signed, CONNECT_ONE_SHOT)
    MWA.adapter.sign_messages([message])

func _on_message_signed(signatures: Array):
    var sig: PackedByteArray = signatures[0]
    print("Signature: ", Marshalls.raw_to_base64(sig))
    # Verify this signature server-side against the public key.
```

## Query Wallet Capabilities

```gdscript
func check_wallet():
    MWA.adapter.capabilities_received.connect(_on_caps, CONNECT_ONE_SHOT)
    MWA.adapter.get_capabilities()

func _on_caps(caps: MWATypes.WalletCapabilities):
    if caps.supports_sign_and_send_transactions:
        print("Wallet can sign & send!")
    else:
        print("Wallet only supports sign — we must send manually")

    print("Max tx per request: ", caps.max_transactions_per_request)
```

## Custom Cache Backend

```gdscript
class_name EncryptedCache
extends MWACache

const KEY = "my-encryption-key"

func get_authorization() -> MWATypes.AuthorizationResult:
    if not FileAccess.file_exists("user://mwa_encrypted.dat"):
        return null
    var file = FileAccess.open("user://mwa_encrypted.dat", FileAccess.READ)
    var encrypted = file.get_as_text()
    file.close()
    var decrypted = decrypt(encrypted, KEY)
    var json = JSON.new()
    if json.parse(decrypted) != OK:
        return null
    return MWATypes.AuthorizationResult.from_dict(json.data)

func set_authorization(auth: MWATypes.AuthorizationResult) -> void:
    var json_str = JSON.stringify(auth.to_dict())
    var encrypted = encrypt(json_str, KEY)
    var file = FileAccess.open("user://mwa_encrypted.dat", FileAccess.WRITE)
    file.store_string(encrypted)
    file.close()

func clear() -> void:
    DirAccess.remove_absolute("user://mwa_encrypted.dat")

# Implement your encrypt/decrypt methods...
```

## Batch Sign Multiple Transactions

```gdscript
func batch_sign():
    var transactions: Array[PackedByteArray] = []
    for i in range(5):
        transactions.append(build_transaction(i))

    MWA.adapter.transactions_signed.connect(_on_batch_signed, CONNECT_ONE_SHOT)
    MWA.adapter.sign_transactions(transactions)

func _on_batch_signed(signed_payloads: Array):
    print("Signed ", signed_payloads.size(), " transactions!")
    # Submit each to RPC manually, or use sign_and_send_transactions.
```

## Full Lifecycle Example

```gdscript
extends Node

func _ready():
    var adapter = MWA.adapter
    adapter.identity = MWATypes.DappIdentity.new("Full Demo", "https://demo.com", "icon.png")
    adapter.cluster = MWATypes.Cluster.DEVNET

    # Connect all signals.
    adapter.authorized.connect(_on_authorized)
    adapter.authorization_failed.connect(func(c, m): print("Auth failed: ", m))
    adapter.deauthorized.connect(func(): print("Disconnected"))
    adapter.state_changed.connect(_on_state)

    # Try reconnect, fall back to fresh auth.
    if adapter.auth_cache.has_authorization():
        adapter.reconnect()
    else:
        adapter.authorize()

func _on_authorized(result: MWATypes.AuthorizationResult):
    print("Authorized with ", result.accounts.size(), " accounts")

    # Query capabilities.
    MWA.adapter.capabilities_received.connect(func(caps):
        print("Capabilities: sign_and_send=", caps.supports_sign_and_send_transactions)
    , CONNECT_ONE_SHOT)
    MWA.adapter.get_capabilities()

func _on_state(state: MWATypes.ConnectionState):
    match state:
        MWATypes.ConnectionState.DISCONNECTED: print("State: Disconnected")
        MWATypes.ConnectionState.CONNECTING: print("State: Connecting...")
        MWATypes.ConnectionState.CONNECTED: print("State: Connected")
        MWATypes.ConnectionState.SIGNING: print("State: Signing...")
```
