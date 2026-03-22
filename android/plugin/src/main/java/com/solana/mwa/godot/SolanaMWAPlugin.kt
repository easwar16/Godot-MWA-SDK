package com.solana.mwa.godot

import android.util.Base64
import android.util.Log
import androidx.activity.ComponentActivity
import com.solana.mobilewalletadapter.clientlib.ActivityResultSender
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot Android plugin for Mobile Wallet Adapter 2.0.
 * Exposes full MWA API surface to GDScript: authorize, deauthorize, getCapabilities,
 * signTransactions, signAndSendTransactions, signMessages.
 *
 * All operations are async — GDScript polls getStatus() to check completion.
 * Results are retrieved via getResultJson(), errors via getErrorMessage()/getErrorCode().
 */
class SolanaMWAPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "SolanaMWA"
    }

    override fun getPluginName(): String = "SolanaMWA"

    private val mwaClient = MWAClient()
    private var sender: ActivityResultSender? = null

    override fun onMainCreate(pActivity: android.app.Activity?): android.view.View? {
        Log.d(TAG, "onMainCreate: creating ActivityResultSender")
        val act = pActivity ?: activity
        if (act is ComponentActivity) {
            sender = ActivityResultSender(act)
            Log.d(TAG, "onMainCreate: ActivityResultSender created successfully")
        } else {
            Log.e(TAG, "onMainCreate: Activity is not ComponentActivity: ${act?.javaClass?.name}")
        }
        return super.onMainCreate(pActivity)
    }

    override fun onMainDestroy() {
        super.onMainDestroy()
        mwaClient.cancelAll()
        Log.d(TAG, "onMainDestroy: cancelled pending operations")
    }

    override fun onMainPause() {
        super.onMainPause()
        Log.d(TAG, "onMainPause")
    }

    override fun onMainResume() {
        super.onMainResume()
        Log.d(TAG, "onMainResume")
    }

    private fun getSender(): ActivityResultSender? {
        if (sender != null) return sender
        Log.e(TAG, "getSender: sender is null (was not created in onMainCreate)")
        mwaClient.setError(MWAErrorCode.NOT_INITIALIZED, "ActivityResultSender not initialized")
        return null
    }

    // ===================================================================
    // STATUS POLLING (called from GDScript _process)
    // ===================================================================

    @UsedByGodot
    fun getStatus(): Int = mwaClient.status

    @UsedByGodot
    fun getResultJson(): String = mwaClient.resultJson

    @UsedByGodot
    fun getErrorMessage(): String = mwaClient.errorMessage

    @UsedByGodot
    fun getErrorCode(): Int = mwaClient.errorCode

    @UsedByGodot
    fun clearState() {
        mwaClient.clearState()
    }

    @UsedByGodot
    fun setTimeoutMs(ms: Int) {
        mwaClient.timeoutMs = ms.toLong()
    }

    // ===================================================================
    // MWA 2.0 API METHODS
    // ===================================================================

    @UsedByGodot
    fun authorize(
        identityUri: String,
        iconPath: String,
        identityName: String,
        chain: String,
        cachedAuthToken: String,
        signInPayloadJson: String
    ) {
        try {
            Log.d(TAG, "authorize: name=$identityName chain=$chain cached=${cachedAuthToken.isNotEmpty()}")
            val sender = getSender() ?: return
            mwaClient.authorize(
                sender, identityUri, iconPath, identityName,
                chain, cachedAuthToken, signInPayloadJson
            )
        } catch (e: Throwable) {
            Log.e(TAG, "authorize: CAUGHT EXCEPTION", e)
        }
    }

    @UsedByGodot
    fun authorizeWithFeatures(
        identityUri: String,
        iconPath: String,
        identityName: String,
        chain: String,
        cachedAuthToken: String,
        signInPayloadJson: String,
        featuresJson: String,
        addressesJson: String
    ) {
        try {
            Log.d(TAG, "authorizeWithFeatures: name=$identityName chain=$chain")
            val sender = getSender() ?: return

            val features: Array<String>? = if (featuresJson.isNotEmpty()) {
                try {
                    val arr = org.json.JSONArray(featuresJson)
                    Array(arr.length()) { arr.getString(it) }
                } catch (e: Exception) { null }
            } else null

            val addresses: Array<ByteArray>? = if (addressesJson.isNotEmpty()) {
                try {
                    val arr = org.json.JSONArray(addressesJson)
                    Array(arr.length()) { Base64.decode(arr.getString(it), Base64.DEFAULT) }
                } catch (e: Exception) { null }
            } else null

            mwaClient.authorize(
                sender, identityUri, iconPath, identityName,
                chain, cachedAuthToken, signInPayloadJson,
                features, addresses
            )
        } catch (e: Throwable) {
            Log.e(TAG, "authorizeWithFeatures: CAUGHT EXCEPTION", e)
        }
    }

    @UsedByGodot
    fun deauthorize(identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String) {
        Log.d(TAG, "deauthorize")
        val sender = getSender() ?: return
        mwaClient.deauthorize(sender, identityUri, iconPath, identityName, chain, authToken)
    }

    @UsedByGodot
    fun getCapabilities(identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String) {
        Log.d(TAG, "getCapabilities")
        val sender = getSender() ?: return
        mwaClient.getCapabilities(sender, identityUri, iconPath, identityName, chain, authToken)
    }

    @UsedByGodot
    fun signTransactions(identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String, payloadsB64: Array<String>) {
        Log.d(TAG, "signTransactions: count=${payloadsB64.size}")
        val sender = getSender() ?: return
        val payloads = payloadsB64.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        mwaClient.signTransactions(sender, identityUri, iconPath, identityName, chain, authToken, payloads)
    }

    @UsedByGodot
    fun signAndSendTransactions(identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String, payloadsB64: Array<String>, optionsJson: String) {
        Log.d(TAG, "signAndSendTransactions: count=${payloadsB64.size}")
        val sender = getSender() ?: return
        val payloads = payloadsB64.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        mwaClient.signAndSendTransactions(sender, identityUri, iconPath, identityName, chain, authToken, payloads, optionsJson)
    }

    @UsedByGodot
    fun signMessages(identityUri: String, iconPath: String, identityName: String, chain: String, authToken: String, messagesB64: Array<String>, addresses: Array<String>) {
        Log.d(TAG, "signMessages: count=${messagesB64.size}")
        val sender = getSender() ?: return
        val messages = messagesB64.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        val addressBytes = addresses.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        mwaClient.signMessages(sender, identityUri, iconPath, identityName, chain, authToken, messages, addressBytes)
    }

    // ===================================================================
    // COMBINED AUTHORIZE + OPERATION METHODS
    // ===================================================================

    @UsedByGodot
    fun authorizeAndSignTransactions(
        identityUri: String, iconPath: String, identityName: String,
        chain: String, cachedAuthToken: String, signInPayloadJson: String,
        payloadsB64: Array<String>
    ) {
        Log.d(TAG, "authorizeAndSignTransactions: count=${payloadsB64.size}")
        val sender = getSender() ?: return
        val payloads = payloadsB64.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        mwaClient.authorizeAndSignTransactions(
            sender, identityUri, iconPath, identityName,
            chain, cachedAuthToken, signInPayloadJson, payloads
        )
    }

    @UsedByGodot
    fun authorizeAndSignAndSendTransactions(
        identityUri: String, iconPath: String, identityName: String,
        chain: String, cachedAuthToken: String, signInPayloadJson: String,
        payloadsB64: Array<String>, optionsJson: String
    ) {
        Log.d(TAG, "authorizeAndSignAndSendTransactions: count=${payloadsB64.size}")
        val sender = getSender() ?: return
        val payloads = payloadsB64.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        mwaClient.authorizeAndSignAndSendTransactions(
            sender, identityUri, iconPath, identityName,
            chain, cachedAuthToken, signInPayloadJson, payloads, optionsJson
        )
    }

    @UsedByGodot
    fun authorizeAndSignMessages(
        identityUri: String, iconPath: String, identityName: String,
        chain: String, cachedAuthToken: String, signInPayloadJson: String,
        messagesB64: Array<String>, addresses: Array<String>
    ) {
        Log.d(TAG, "authorizeAndSignMessages: count=${messagesB64.size}")
        val sender = getSender() ?: return
        val messages = messagesB64.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        val addressBytes = addresses.map { Base64.decode(it, Base64.DEFAULT) }.toTypedArray()
        mwaClient.authorizeAndSignMessages(
            sender, identityUri, iconPath, identityName,
            chain, cachedAuthToken, signInPayloadJson, messages, addressBytes
        )
    }
}
