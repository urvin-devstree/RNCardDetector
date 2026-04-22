package com.reactnativecarddetector

import android.app.Activity
import android.content.Intent
import androidx.activity.result.ActivityResult
import androidx.activity.result.ActivityResultCallback
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.BaseActivityEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableMap
import lens24.intent.Card
import lens24.intent.ScanCardCallback
import lens24.intent.ScanCardIntent

class CardScannerModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    companion object {
        private const val MODULE_NAME = "CardScannerModule"
        private const val REQUEST_CODE_SCAN_CARD = 49201
        private const val DEFAULT_HINT = "Align the card in the frame"
        private const val DEFAULT_TOOLBAR_TITLE = "Scan card"
    }

    private var pendingPromise: Promise? = null
    private var activityResultCallback: ActivityResultCallback<ActivityResult>? = null

    private val activityEventListener: ActivityEventListener =
        object : BaseActivityEventListener() {
            override fun onActivityResult(
                activity: Activity, requestCode: Int, resultCode: Int, data: Intent?
            ) {
                if (requestCode != REQUEST_CODE_SCAN_CARD) return

                val callback = activityResultCallback
                if (callback == null) {
                    pendingPromise?.reject("E_NO_CALLBACK", "Card scan callback not set")
                    clearPending()
                    return
                }
                callback.onActivityResult(ActivityResult(resultCode, data))
            }
        }

    init {
        reactContext.addActivityEventListener(activityEventListener)
    }

    override fun getName(): String = MODULE_NAME

    @ReactMethod
    fun scanCard(promise: Promise) {
        scanCardWithOptions(null, promise)
    }

    @ReactMethod
    fun scanCardWithOptions(options: ReadableMap?, promise: Promise) {
        val activity: Activity = reactContext.currentActivity ?: run {
            promise.reject("E_NO_ACTIVITY", "No current Activity. Is the app in foreground?")
            return
        }
        if (pendingPromise != null) {
            promise.reject("E_IN_PROGRESS", "Card scan already in progress")
            return
        }

        pendingPromise = promise

        activityResultCallback = ScanCardCallback.Builder().setOnSuccess { card: Card, _ ->
            val result = Arguments.createMap().apply {
                putString("cardNumber", card.cardNumber)
                putString("cardNumberRedacted", card.cardNumberRedacted)
                putString("cardHolderName", card.cardHolderName)
                putString("expirationDate", card.expirationDate)
            }
            pendingPromise?.resolve(result)
            clearPending()
        }.setOnBackPressed {
            pendingPromise?.reject("E_CANCELED", "Card scan canceled (back pressed)")
            clearPending()
        }.setOnManualInput {
            pendingPromise?.reject("E_CANCELED", "Card scan canceled (manual input)")
            clearPending()
        }.setOnError {
            pendingPromise?.reject("E_SCAN_FAILED", "Card scan failed")
            clearPending()
        }.build()

        val androidOptions =
            if (options != null && options.hasKey("android") && !options.isNull("android")) {
                options.getMap("android")
            } else {
                options
            }
        val hint = androidOptions.getNonBlankString("hint") ?: DEFAULT_HINT
        val toolbarTitle = androidOptions.getNonBlankString("toolbarTitle") ?: DEFAULT_TOOLBAR_TITLE

        val intent =
            ScanCardIntent.Builder(activity).setScanCardHolder(true).setScanExpirationDate(true)
                .setSaveCard(false).setVibrationEnabled(true).setHint(hint)
                .setToolbarTitle(toolbarTitle).build()

        try {
            activity.startActivityForResult(intent, REQUEST_CODE_SCAN_CARD)
        } catch (e: Exception) {
            pendingPromise?.reject("E_START_FAILED", e.message, e)
            clearPending()
        }
    }

    private fun clearPending() {
        pendingPromise = null
        activityResultCallback = null
    }

    private fun ReadableMap?.getNonBlankString(key: String): String? {
        if (this == null) return null
        if (!this.hasKey(key) || this.isNull(key)) return null
        val value = this.getString(key) ?: return null
        val trimmed = value.trim()
        return trimmed.ifEmpty { null }
    }
}
