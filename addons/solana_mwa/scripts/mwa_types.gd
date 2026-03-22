class_name MWATypes
## Data types for Mobile Wallet Adapter SDK.

## Blockchain cluster identifiers.
enum Cluster {
	DEVNET = 0,
	MAINNET = 1,
	TESTNET = 2,
}

## MWA protocol error codes.
enum ErrorCode {
	AUTHORIZATION_FAILED = -1,
	INVALID_PAYLOADS = -2,
	NOT_SIGNED = -3,
	NOT_SUBMITTED = -4,
	NOT_CLONED = -5,
	TOO_MANY_PAYLOADS = -6,
	CLUSTER_NOT_SUPPORTED = -7,
	BUSY = -8,
	NO_WALLET_FOUND = -10,
	TIMEOUT = -11,
	USER_DECLINED = -12,
	NOT_INITIALIZED = -13,
	ATTEST_ORIGIN_ANDROID = -100,
}

## Connection states.
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	SIGNING,
	DEAUTHORIZING,
}

## Result wrapper for async operations.
class Result:
	var success: bool
	var data: Variant
	var error_code: int
	var error_message: String

	func _init(
			p_success: bool = false, p_data: Variant = null,
			p_error_code: int = 0, p_error_message: String = "") -> void:
		success = p_success
		data = p_data
		error_code = p_error_code
		error_message = p_error_message

	static func ok(p_data: Variant = null) -> Result:
		return Result.new(true, p_data)

	static func err(p_error_code: int, p_error_message: String) -> Result:
		return Result.new(false, null, p_error_code, p_error_message)

## Account information returned from authorization.
class Account:
	var address: String
	var public_key: PackedByteArray
	var label: String
	var icon: String
	var chains: PackedStringArray
	var features: PackedStringArray

	func _init(
			p_address: String = "", p_public_key: PackedByteArray = [],
			p_label: String = "", p_icon: String = "",
			p_chains: PackedStringArray = [],
			p_features: PackedStringArray = []) -> void:
		address = p_address
		public_key = p_public_key
		label = p_label
		icon = p_icon
		chains = p_chains
		features = p_features

	func to_dict() -> Dictionary:
		return {
			"address": address,
			"public_key": Marshalls.raw_to_base64(public_key),
			"label": label,
			"icon": icon,
			"chains": chains,
			"features": features,
		}

	static func from_dict(d: Dictionary) -> Account:
		var acc := Account.new()
		acc.address = d.get("address", "")
		var pk_b64: String = d.get("public_key", "")
		if pk_b64 != "":
			acc.public_key = Marshalls.base64_to_raw(pk_b64)
		acc.label = d.get("label", "")
		acc.icon = d.get("icon", "")
		acc.chains = d.get("chains", PackedStringArray())
		acc.features = d.get("features", PackedStringArray())
		return acc

## Sign-In With Solana result returned inside AuthorizationResult.
class SignInResult:
	var public_key: PackedByteArray
	var signed_message: PackedByteArray
	var signature: PackedByteArray
	var signature_type: String

	static func from_dict(d: Dictionary) -> SignInResult:
		var r := SignInResult.new()
		var pk_b64: String = d.get("public_key", "")
		if pk_b64 != "":
			r.public_key = Marshalls.base64_to_raw(pk_b64)
		var sm_b64: String = d.get("signed_message", "")
		if sm_b64 != "":
			r.signed_message = Marshalls.base64_to_raw(sm_b64)
		var sig_b64: String = d.get("signature", "")
		if sig_b64 != "":
			r.signature = Marshalls.base64_to_raw(sig_b64)
		r.signature_type = d.get("signature_type", "ed25519")
		return r

## Authorization result returned from authorize/reauthorize.
class AuthorizationResult:
	var accounts: Array
	var auth_token: String
	var wallet_uri_base: String
	var sign_in_result: SignInResult

	func to_dict() -> Dictionary:
		var accs: Array = []
		for acc in accounts:
			accs.append(acc.to_dict())
		var d := {
			"accounts": accs,
			"auth_token": auth_token,
			"wallet_uri_base": wallet_uri_base,
		}
		if sign_in_result != null:
			d["sign_in_result"] = {
				"public_key": Marshalls.raw_to_base64(
					sign_in_result.public_key),
				"signed_message": Marshalls.raw_to_base64(
					sign_in_result.signed_message),
				"signature": Marshalls.raw_to_base64(
					sign_in_result.signature),
				"signature_type": sign_in_result.signature_type,
			}
		return d

	static func from_dict(d: Dictionary) -> AuthorizationResult:
		var result := AuthorizationResult.new()
		result.auth_token = d.get("auth_token", "")
		result.wallet_uri_base = d.get("wallet_uri_base", "")
		var siws_dict: Dictionary = d.get("sign_in_result", {})
		if not siws_dict.is_empty():
			result.sign_in_result = SignInResult.from_dict(siws_dict)
		var accs_raw: Array = d.get("accounts", [])
		for acc_d in accs_raw:
			result.accounts.append(Account.from_dict(acc_d))
		return result

## Wallet capabilities returned from get_capabilities.
class WalletCapabilities:
	var supports_clone_authorization: bool
	var supports_sign_and_send_transactions: bool
	var max_transactions_per_request: int
	var max_messages_per_request: int
	var supported_transaction_versions: PackedStringArray
	var features: PackedStringArray

## Dapp identity for authorize requests.
class DappIdentity:
	var uri: String
	var icon: String
	var name: String

	func _init(
			p_name: String = "Godot dApp",
			p_uri: String = "https://solana.com",
			p_icon: String = "icon.png") -> void:
		name = p_name
		uri = p_uri
		icon = p_icon

## Options for sign_and_send_transactions.
class SendOptions:
	var min_context_slot: int
	var commitment: String
	var skip_preflight: bool
	var max_retries: int
	var wait_for_commitment_to_send_next_transaction: bool

	func _init() -> void:
		min_context_slot = -1
		commitment = ""
		skip_preflight = false
		max_retries = -1
		wait_for_commitment_to_send_next_transaction = false

	func to_dict() -> Dictionary:
		var d := {}
		if min_context_slot >= 0:
			d["min_context_slot"] = min_context_slot
		if commitment != "":
			d["commitment"] = commitment
		if skip_preflight:
			d["skip_preflight"] = skip_preflight
		if max_retries >= 0:
			d["max_retries"] = max_retries
		if wait_for_commitment_to_send_next_transaction:
			d["wait_for_commitment_to_send_next_transaction"] = true
		return d

## Sign In With Solana payload.
class SignInPayload:
	var domain: String
	var address: String
	var statement: String
	var uri: String
	var version: String
	var chain_id: String
	var nonce: String
	var issued_at: String
	var expiration_time: String
	var not_before: String
	var request_id: String
	var resources: PackedStringArray

	func to_dict() -> Dictionary:
		var d := {}
		if domain != "":
			d["domain"] = domain
		if address != "":
			d["address"] = address
		if statement != "":
			d["statement"] = statement
		if uri != "":
			d["uri"] = uri
		if version != "":
			d["version"] = version
		if chain_id != "":
			d["chainId"] = chain_id
		if nonce != "":
			d["nonce"] = nonce
		if issued_at != "":
			d["issuedAt"] = issued_at
		if expiration_time != "":
			d["expirationTime"] = expiration_time
		if not_before != "":
			d["notBefore"] = not_before
		if request_id != "":
			d["requestId"] = request_id
		if resources.size() > 0:
			d["resources"] = resources
		return d

## Chain identifiers.
static func cluster_to_chain(cluster: int) -> String:
	match cluster:
		Cluster.MAINNET:
			return "solana:mainnet"
		Cluster.DEVNET:
			return "solana:devnet"
		Cluster.TESTNET:
			return "solana:testnet"
	return "solana:mainnet"

static func chain_to_cluster(chain: String) -> int:
	match chain:
		"solana:mainnet":
			return Cluster.MAINNET
		"solana:devnet":
			return Cluster.DEVNET
		"solana:testnet":
			return Cluster.TESTNET
	return Cluster.MAINNET
