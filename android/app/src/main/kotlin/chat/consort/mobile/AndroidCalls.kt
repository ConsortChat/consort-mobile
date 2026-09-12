package chat.consort.mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

private const val CALL_PERMISSIONS_REQUEST_CODE = 0x7a02

class AndroidCallsHost(val context: Context) : AndroidCallsHostApi {
    private var activityBinding: ActivityPluginBinding? = null

    private val pendingCallbacks = mutableListOf<(Result<CallPermissions>) -> Unit>()

    private val permissionsResultListener =
        PluginRegistry.RequestPermissionsResultListener { requestCode, _, _ ->
            if (requestCode != CALL_PERMISSIONS_REQUEST_CODE) {
                return@RequestPermissionsResultListener false
            }
            val result = callPermissions(requestedFrom = activityBinding?.activity)
            pendingCallbacks.forEach { it(Result.success(result)) }
            pendingCallbacks.clear()
            true
        }

    fun attachToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(permissionsResultListener)
    }

    fun detachFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(permissionsResultListener)
        activityBinding = null
    }

    override fun requestCallPermissions(callback: (Result<CallPermissions>) -> Unit) {
        val missing = listOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
            .filter { !isGranted(it) }
        val activity = activityBinding?.activity
        if (missing.isEmpty() || activity == null) {
            callback(Result.success(callPermissions(requestedFrom = null)))
            return
        }
        pendingCallbacks.add(callback)
        if (pendingCallbacks.size == 1) {
            ActivityCompat.requestPermissions(activity, missing.toTypedArray(),
                CALL_PERMISSIONS_REQUEST_CODE)
        }
    }

    private fun isGranted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /**
     * The status of each call permission.
     *
     * Pass [requestedFrom] only just after requesting the permissions from
     * that activity.  Otherwise a permission that was never requested
     * would look blocked.
     */
    private fun callPermissions(requestedFrom: Activity?): CallPermissions {
        fun status(permission: String): CallPermissionStatus = when {
            isGranted(permission) -> CallPermissionStatus.GRANTED
            // After a denied request, no rationale means Android wouldn't show another.
            requestedFrom != null
                && !ActivityCompat.shouldShowRequestPermissionRationale(requestedFrom, permission)
                -> CallPermissionStatus.BLOCKED
            else -> CallPermissionStatus.DENIED
        }
        return CallPermissions(
            microphone = status(Manifest.permission.RECORD_AUDIO),
            camera = status(Manifest.permission.CAMERA),
        )
    }
}
