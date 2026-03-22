package com.solana.mwa.godot

import android.net.Uri
import android.util.Base64
import android.util.Log
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import com.solana.mobilewalletadapter.clientlib.ConnectionIdentity
import com.solana.mobilewalletadapter.clientlib.MobileWalletAdapter
import com.solana.mobilewalletadapter.clientlib.Blockchain
import com.solana.mobilewalletadapter.clientlib.Solana
import com.solana.mobilewalletadapter.clientlib.TransactionResult
import com.solana.mobilewalletadapter.clientlib.TransactionParams
import com.solana.mobilewalletadapter.common.signin.SignInWithSolana
import kotlinx.coroutines.*
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

object MWAErrorCode {
    const val AUTHORIZATION_FAILED = -1
    const val INVALID_PAYLOADS = -2
    const val NOT_SIGNED = -3
    const val NOT_SUBMITTED = -4
    const val NOT_CLONED = -5
    const val TOO_MANY_PAYLOADS = -6
    const val CLUSTER_NOT_SUPPORTED = -7
    const val BUSY = -8
    const val NO_WALLET_FOUND = -10
    const val TIMEOUT = -11
    const val USER_DECLINED = -12
    const val NOT_INITIALIZED = -13
}

/**
 * Core MWA client that performs wallet adapter operations.
 * All methods are non-blocking — they launch coroutines and update status/result fields
 * that are polled from GDScript.
 */
class MWAClient {

    companion object {
        private const val TAG = "MWAClient"
    }

    // --- Polling state (read from GDScript) ---
    @Volatile var status: Int = 0          // 0=pending, 1=success, 2=error
    @Volatile var resultJson: String = ""
    @Volatile var errorMessage: String = ""
    @Volatile var errorCode: Int = 0

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Busy guard to prevent concurrent operations
    private val busy = java.util.concurrent.atomic.AtomicBoolean(false)

    /** Timeout in milliseconds for wallet operations. */
    var timeoutMs: Long = 30_000L

    // Persistent adapter instance — reused across operations to preserve
    // walletUriBase routing (like KTX reference does).
    private var walletAdapter: MobileWalletAdapter? = null
    private var currentChain: String = ""
    private var currentIdentityUri: String = ""
    private var currentIconPath: String = ""
    private var currentIdentityName: String = ""

    private fun getOrCreateAdapter(
        identityUri: String, iconPath: String,
        identityName: String, chain: String,
        authToken: String = ""
    ): MobileWalletAdapter {
        // Reuse existing adapter if identity and chain match.
        val existing = walletAdapter
        if (existing != null &&
            currentChain == chain &&
            currentIdentityUri == identityUri &&
            currentIdentityName == identityName
        ) {
            if (authToken.isNotEmpty()) existing.authToken = authToken
            return existing
        }
        // Create new adapter for new identity/chain.
        val identity = buildIdentity(identityUri, iconPath, identityName)
        val adapter = MobileWalletAdapter(connectionIdentity = identity)
        adapter.blockchain = chainToBlockchain(chain)
        if (authToken.isNotEmpty()) adapter.authToken = authToken
        walletAdapter = adapter
        currentChain = chain
        currentIdentityUri = identityUri
        currentIconPath = iconPath
        currentIdentityName = identityName
        return adapter
    }

    /** Clear the cached adapter (e.g., on deauthorize). */
    fun clearAdapter() {
        walletAdapter = null
        currentChain = ""
    }

    fun clearState() {
        status = 0
        resultJson = ""
        errorMessage = ""
        errorCode = 0
        busy.set(false)
    }

    fun setError(code: Int, message: String) {
        errorCode = code
        errorMessage = message
        status = 2
        busy.set(false)
    }

    private fun setSuccess(json: String) {
        resultJson = json
        status = 1
        busy.set(false)
    }

    fun cancelAll() {
        scope.coroutineContext.cancelChildren()
        if (status == 0) {
            setError(MWAErrorCode.AUTHORIZATION_FAILED, "Operation cancelled")
        }
        busy.set(false)
    }

    private fun classifyError(e: Exception): Int {
        // Try typed exception classification first (protocol error codes).
        if (e is com.solana.mobilewalletadapter.clientlib.protocol.JsonRpc20Client.JsonRpc20RemoteException) {
            return when (e.code) {
                -1 -> MWAErrorCode.AUTHORIZATION_FAILED
                -2 -> MWAErrorCode.INVALID_PAYLOADS
                -3 -> MWAErrorCode.NOT_SIGNED
                -4 -> MWAErrorCode.NOT_SUBMITTED
                -5 -> MWAErrorCode.NOT_CLONED
                -6 -> MWAErrorCode.TOO_MANY_PAYLOADS
                -7 -> MWAErrorCode.CLUSTER_NOT_SUPPORTED
                else -> MWAErrorCode.AUTHORIZATION_FAILED
            }
        }

        // Fall back to message-based classification.
        val msg = e.message?.lowercase() ?: ""
        return when {
            msg.contains("decline") || msg.contains("cancel") ||
                msg.contains("reject") -> MWAErrorCode.USER_DECLINED
            msg.contains("invalid payload") ||
                msg.contains("invalid transaction") -> MWAErrorCode.INVALID_PAYLOADS
            msg.contains("not signed") -> MWAErrorCode.NOT_SIGNED
            msg.contains("not submitted") ||
                msg.contains("send failed") -> MWAErrorCode.NOT_SUBMITTED
            msg.contains("too many") -> MWAErrorCode.TOO_MANY_PAYLOADS
            msg.contains("cluster") ||
                msg.contains("chain not supported") -> MWAErrorCode.CLUSTER_NOT_SUPPORTED
            else -> MWAErrorCode.AUTHORIZATION_FAILED
        }
    }

    private fun buildAuthJson(authResult: com.solana.mobilewalletadapter.clientlib.protocol.MobileWalletAdapterClient.AuthorizationResult): JSONObject {
        return JSONObject().apply {
            put("auth_token", authResult.authToken)
            put("wallet_uri_base", authResult.walletUriBase?.toString() ?: "")

            val accounts = JSONArray()
            authResult.accounts.forEach { acc ->
                val account = JSONObject().apply {
                    put("address", Base64.encodeToString(acc.publicKey, Base64.NO_WRAP))
                    put("public_key", Base64.encodeToString(acc.publicKey, Base64.NO_WRAP))
                    put("label", acc.accountLabel ?: "")
                    put("icon", "")
                    val chainsArr = JSONArray()
                    acc.chains?.forEach { c -> chainsArr.put(c) }
                    put("chains", chainsArr)
                    val featuresArr = JSONArray()
                    acc.features?.forEach { f -> featuresArr.put(f) }
                    put("features", featuresArr)
                }
                accounts.put(account)
            }
            put("accounts", accounts)
        }
    }

    private fun buildIdentity(uri: String, icon: String, name: String): ConnectionIdentity {
        return ConnectionIdentity(
            identityUri = Uri.parse(uri),
            iconUri = Uri.parse(icon),
            identityName = name
        )
    }

    private fun parseSendOptions(optionsJson: String): TransactionParams {
        var minContextSlot: Int? = null
        var commitment: String? = null
        var skipPreflight: Boolean? = null
        var maxRetries: Int? = null
        var waitForCommitment: Boolean? = null

        if (optionsJson.isNotEmpty()) {
            try {
                val opts = JSONObject(optionsJson)
                if (opts.has("min_context_slot"))
                    minContextSlot = opts.getInt("min_context_slot")
                if (opts.has("commitment"))
                    commitment = opts.getString("commitment")
                if (opts.has("skip_preflight"))
                    skipPreflight = opts.getBoolean("skip_preflight")
                if (opts.has("max_retries"))
                    maxRetries = opts.getInt("max_retries")
                if (opts.has("wait_for_commitment_to_send_next_transaction"))
                    waitForCommitment = opts.getBoolean("wait_for_commitment_to_send_next_transaction")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to parse send options: ${e.message}")
            }
        }
        return TransactionParams(
            minContextSlot, commitment, skipPreflight,
            maxRetries, waitForCommitment
        )
    }

    private fun chainToBlockchain(chain: String): Blockchain {
        return when (chain) {
            "solana:devnet" -> Solana.Devnet
            "solana:testnet" -> Solana.Testnet
            "solana:mainnet" -> Solana.Mainnet
            // For custom chains, map to closest Solana cluster.
            // The chain string is still passed via the MWA protocol.
            else -> Solana.Mainnet
        }
    }

    // ===================================================================
    // AUTHORIZE
    // ===================================================================

    fun authorize(
        sender: ActivityResultSender,
        identityUri: String,
        iconPath: String,
        identityName: String,
        chain: String,
        existingAuthToken: String,
        signInPayloadJson: String,
        features: Array<String>? = null,
        addresses: Array<ByteArray>? = null
    ) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        Log.d(TAG, "authorize: starting coroutine")
        scope.launch(CoroutineExceptionHandler { _, throwable ->
            Log.e(TAG, "Coroutine exception", throwable)
            setError(MWAErrorCode.AUTHORIZATION_FAILED, "Coroutine error: ${throwable.message}")
        }) {
            try {
                Log.d(TAG, "authorize: building identity uri=$identityUri name=$identityName")
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, existingAuthToken
                )

                // Parse Sign In With Solana payload if provided.
                var signInPayload: SignInWithSolana.Payload? = null
                if (signInPayloadJson.isNotEmpty()) {
                    try {
                        signInPayload = SignInWithSolana.Payload.fromJson(JSONObject(signInPayloadJson))
                    } catch (e: Exception) {
                        Log.w(TAG, "authorize: failed to parse sign-in payload: ${e.message}")
                    }
                }

                Log.d(TAG, "authorize: calling transact...")

                if (signInPayload != null) {
                    // Use signIn for SIWS flow.
                    val result = withTimeoutOrNull(timeoutMs) {
                        walletAdapter.signIn(sender, signInPayload)
                    }

                    if (result == null) {
                        setError(MWAErrorCode.TIMEOUT, "Connection timed out. No wallet responded.")
                        return@launch
                    }

                    when (result) {
                        is TransactionResult.Success -> {
                            val authResult = result.authResult

                            val json = buildAuthJson(authResult)

                            // Add SIWS sign-in result.
                            val signInResult = result.payload
                            val siws = JSONObject().apply {
                                put("public_key", Base64.encodeToString(signInResult.publicKey, Base64.NO_WRAP))
                                put("signed_message", Base64.encodeToString(signInResult.signedMessage, Base64.NO_WRAP))
                                put("signature", Base64.encodeToString(signInResult.signature, Base64.NO_WRAP))
                                put("signature_type", signInResult.signatureType ?: "ed25519")
                            }
                            json.put("sign_in_result", siws)

                            setSuccess(json.toString())
                            Log.d(TAG, "authorize (signIn): success")
                        }
                        is TransactionResult.NoWalletFound -> {
                            setError(MWAErrorCode.NO_WALLET_FOUND, "No MWA-compatible wallet found on device")
                        }
                        is TransactionResult.Failure -> {
                            setError(classifyError(result.e), "Authorization failed: ${result.e.message}")
                        }
                    }
                } else {
                    // Standard authorize/reauthorize flow.
                    val result = withTimeoutOrNull(timeoutMs) {
                        walletAdapter.transact(sender) { authResult ->
                            authResult
                        }
                    }

                    if (result == null) {
                        setError(MWAErrorCode.TIMEOUT, "Connection timed out. No wallet responded.")
                        return@launch
                    }

                    when (result) {
                        is TransactionResult.Success -> {
                            val authResult = result.authResult

                            val json = buildAuthJson(authResult)
                            setSuccess(json.toString())
                            Log.d(TAG, "authorize: success")
                        }
                        is TransactionResult.NoWalletFound -> {
                            setError(MWAErrorCode.NO_WALLET_FOUND, "No MWA-compatible wallet found on device")
                        }
                        is TransactionResult.Failure -> {
                            setError(classifyError(result.e), "Authorization failed: ${result.e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "authorize error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "Authorization error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // DEAUTHORIZE
    // ===================================================================

    fun deauthorize(sender: ActivityResultSender, identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, authToken
                )

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.disconnect(sender)
                }

                clearAdapter()

                when (result) {
                    is TransactionResult.Success -> {
                        setSuccess("{}")
                        Log.d(TAG, "deauthorize: success")
                    }
                    is TransactionResult.Failure -> {
                        // Deauthorize succeeds locally even if wallet reports failure.
                        setSuccess("{}")
                        Log.w(TAG, "deauthorize: wallet reported failure, cleared locally")
                    }
                    else -> {
                        setSuccess("{}")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "deauthorize error", e)
                clearAdapter()
                setSuccess("{}")
            }
        }
    }

    // ===================================================================
    // GET CAPABILITIES
    // ===================================================================

    fun getCapabilities(sender: ActivityResultSender, identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, authToken
                )

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        getCapabilities()
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out. No wallet responded.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val caps = result.payload
                        val json = JSONObject().apply {
                            put("supports_clone_authorization", caps.supportsCloneAuthorization)
                            put("supports_sign_and_send_transactions", caps.supportsSignAndSendTransactions)
                            put("max_transactions_per_request", caps.maxTransactionsPerSigningRequest)
                            put("max_messages_per_request", caps.maxMessagesPerSigningRequest)

                            val versions = JSONArray()
                            caps.supportedTransactionVersions.forEach { versions.put(it.toString()) }
                            put("supported_transaction_versions", versions)

                            val features = JSONArray()
                            caps.supportedOptionalFeatures.forEach { features.put(it) }
                            put("features", features)
                        }
                        setSuccess(json.toString())
                        Log.d(TAG, "getCapabilities: success")
                    }
                    is TransactionResult.Failure -> {
                        setError(classifyError(result.e), "getCapabilities failed: ${result.e.message}")
                    }
                    else -> {
                        setError(MWAErrorCode.AUTHORIZATION_FAILED, "getCapabilities: unexpected result")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "getCapabilities error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "getCapabilities error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // SIGN TRANSACTIONS (batch support)
    // ===================================================================

    fun signTransactions(sender: ActivityResultSender, identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String, payloads: Array<ByteArray>) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, authToken
                )

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        signTransactions(payloads)
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out. No wallet responded.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val signedPayloads = result.payload.signedPayloads
                        val json = JSONObject().apply {
                            val arr = JSONArray()
                            signedPayloads.forEach { payload ->
                                arr.put(Base64.encodeToString(payload, Base64.NO_WRAP))
                            }
                            put("signed_payloads", arr)
                        }
                        setSuccess(json.toString())
                        Log.d(TAG, "signTransactions: success, count=${signedPayloads.size}")
                    }
                    is TransactionResult.Failure -> {
                        setError(classifyError(result.e), "signTransactions failed: ${result.e.message}")
                    }
                    else -> {
                        setError(MWAErrorCode.AUTHORIZATION_FAILED, "signTransactions: unexpected result")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "signTransactions error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "signTransactions error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // SIGN AND SEND TRANSACTIONS
    // ===================================================================

    fun signAndSendTransactions(
        sender: ActivityResultSender,
        identityUri: String,
        iconPath: String,
        identityName: String,
        chain: String,
        authToken: String,
        payloads: Array<ByteArray>,
        optionsJson: String
    ) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, authToken
                )

                val params = parseSendOptions(optionsJson)

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        signAndSendTransactions(payloads, params)
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out. No wallet responded.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val signatures = result.payload.signatures
                        val json = JSONObject().apply {
                            val arr = JSONArray()
                            signatures.forEach { sig ->
                                arr.put(Base64.encodeToString(sig, Base64.NO_WRAP))
                            }
                            put("signatures", arr)
                        }
                        setSuccess(json.toString())
                        Log.d(TAG, "signAndSendTransactions: success, sigs=${signatures.size}")
                    }
                    is TransactionResult.Failure -> {
                        setError(classifyError(result.e), "signAndSendTransactions failed: ${result.e.message}")
                    }
                    else -> {
                        setError(MWAErrorCode.AUTHORIZATION_FAILED, "signAndSendTransactions: unexpected result")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "signAndSendTransactions error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "signAndSendTransactions error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // SIGN MESSAGES
    // ===================================================================

    fun signMessages(
        sender: ActivityResultSender,
        identityUri: String,
        iconPath: String,
        identityName: String,
        chain: String,
        authToken: String,
        messages: Array<ByteArray>,
        addresses: Array<ByteArray>
    ) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, authToken
                )

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        signMessagesDetached(messages, addresses)
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out. No wallet responded.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val signed = result.payload
                        val json = JSONObject().apply {
                            val arr = JSONArray()
                            signed.messages.forEach { msg ->
                                msg.signatures.forEach { sig ->
                                    arr.put(Base64.encodeToString(sig, Base64.NO_WRAP))
                                }
                            }
                            put("signatures", arr)
                        }
                        setSuccess(json.toString())
                        Log.d(TAG, "signMessages: success")
                    }
                    is TransactionResult.Failure -> {
                        setError(classifyError(result.e), "signMessages failed: ${result.e.message}")
                    }
                    else -> {
                        setError(MWAErrorCode.AUTHORIZATION_FAILED, "signMessages: unexpected result")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "signMessages error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "signMessages error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // COMBINED AUTHORIZE + SIGN TRANSACTIONS (single session)
    // ===================================================================

    fun authorizeAndSignTransactions(
        sender: ActivityResultSender,
        identityUri: String, iconPath: String, identityName: String,
        chain: String, existingAuthToken: String, signInPayloadJson: String,
        payloads: Array<ByteArray>
    ) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch(CoroutineExceptionHandler { _, t ->
            Log.e(TAG, "Coroutine exception", t)
            setError(MWAErrorCode.AUTHORIZATION_FAILED, "Error: ${t.message}")
        }) {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, existingAuthToken
                )

                // Note: signInPayloadJson is accepted for API consistency but
                // the KTX transact() auto-handles auth. For SIWS, use
                // authorize(siws_payload) then sign_transactions() separately.
                if (signInPayloadJson.isNotEmpty()) {
                    Log.w(TAG, "authorizeAndSignTransactions: SIWS payload provided " +
                        "but combined methods use transact() auto-auth. " +
                        "Use authorize(siws) + sign_transactions() for SIWS flows.")
                }

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        val signed = signTransactions(payloads)
                        signed
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val authResult = result.authResult
                        val json = buildAuthJson(authResult)
                        // Add signed payloads
                        val signedArr = JSONArray()
                        result.payload.signedPayloads.forEach { p ->
                            signedArr.put(Base64.encodeToString(p, Base64.NO_WRAP))
                        }
                        json.put("signed_payloads", signedArr)
                        setSuccess(json.toString())
                    }
                    is TransactionResult.NoWalletFound -> setError(MWAErrorCode.NO_WALLET_FOUND, "No wallet found")
                    is TransactionResult.Failure -> setError(classifyError(result.e), "Failed: ${result.e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "authorizeAndSignTransactions error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "Error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // COMBINED AUTHORIZE + SIGN AND SEND TRANSACTIONS (single session)
    // ===================================================================

    fun authorizeAndSignAndSendTransactions(
        sender: ActivityResultSender,
        identityUri: String, iconPath: String, identityName: String,
        chain: String, existingAuthToken: String, signInPayloadJson: String,
        payloads: Array<ByteArray>, optionsJson: String
    ) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch(CoroutineExceptionHandler { _, t ->
            Log.e(TAG, "Coroutine exception", t)
            setError(MWAErrorCode.AUTHORIZATION_FAILED, "Error: ${t.message}")
        }) {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, existingAuthToken
                )

                if (signInPayloadJson.isNotEmpty()) {
                    Log.w(TAG, "authorizeAndSignAndSendTransactions: SIWS in " +
                        "combined methods not supported. Use authorize(siws) separately.")
                }

                val params = parseSendOptions(optionsJson)

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        val sigs = signAndSendTransactions(payloads, params)
                        sigs
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val authResult = result.authResult
                        val json = buildAuthJson(authResult)
                        // Add signatures
                        val sigArr = JSONArray()
                        result.payload.signatures.forEach { sig ->
                            sigArr.put(Base64.encodeToString(sig, Base64.NO_WRAP))
                        }
                        json.put("signatures", sigArr)
                        setSuccess(json.toString())
                    }
                    is TransactionResult.NoWalletFound -> setError(MWAErrorCode.NO_WALLET_FOUND, "No wallet found")
                    is TransactionResult.Failure -> setError(classifyError(result.e), "Failed: ${result.e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "authorizeAndSignAndSendTransactions error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "Error: ${e.message}")
            }
        }
    }

    // ===================================================================
    // COMBINED AUTHORIZE + SIGN MESSAGES (single session)
    // ===================================================================

    fun authorizeAndSignMessages(
        sender: ActivityResultSender,
        identityUri: String, iconPath: String, identityName: String,
        chain: String, existingAuthToken: String, signInPayloadJson: String,
        messages: Array<ByteArray>, addresses: Array<ByteArray>
    ) {
        clearState()
        if (!busy.compareAndSet(false, true)) {
            setError(MWAErrorCode.BUSY, "Another operation is in progress")
            return
        }
        scope.launch(CoroutineExceptionHandler { _, t ->
            Log.e(TAG, "Coroutine exception", t)
            setError(MWAErrorCode.AUTHORIZATION_FAILED, "Error: ${t.message}")
        }) {
            try {
                val walletAdapter = getOrCreateAdapter(
                    identityUri, iconPath, identityName, chain, existingAuthToken
                )

                if (signInPayloadJson.isNotEmpty()) {
                    Log.w(TAG, "authorizeAndSignMessages: SIWS in combined " +
                        "methods not supported. Use authorize(siws) separately.")
                }

                val result = withTimeoutOrNull(timeoutMs) {
                    walletAdapter.transact(sender) { _ ->
                        val signed = signMessagesDetached(messages, addresses)
                        signed
                    }
                }

                if (result == null) {
                    setError(MWAErrorCode.TIMEOUT, "Connection timed out.")
                    return@launch
                }

                when (result) {
                    is TransactionResult.Success -> {
                        val authResult = result.authResult
                        val json = buildAuthJson(authResult)
                        // Add signatures
                        val sigArr = JSONArray()
                        result.payload.messages.forEach { msg ->
                            msg.signatures.forEach { sig ->
                                sigArr.put(Base64.encodeToString(sig, Base64.NO_WRAP))
                            }
                        }
                        json.put("signatures", sigArr)
                        setSuccess(json.toString())
                    }
                    is TransactionResult.NoWalletFound -> setError(MWAErrorCode.NO_WALLET_FOUND, "No wallet found")
                    is TransactionResult.Failure -> setError(classifyError(result.e), "Failed: ${result.e.message}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "authorizeAndSignMessages error", e)
                setError(MWAErrorCode.AUTHORIZATION_FAILED, "Error: ${e.message}")
            }
        }
    }
}
