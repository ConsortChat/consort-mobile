package org.jitsi.jitsi_meet_flutter_sdk

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import org.jitsi.meet.sdk.BroadcastEvent
import org.jitsi.meet.sdk.JitsiMeetActivity
import org.jitsi.meet.sdk.JitsiMeetActivityDelegate
import android.app.KeyguardManager
import android.view.WindowManager
import android.os.Build
import org.jitsi.meet.sdk.JitsiMeetConferenceOptions
import org.jitsi.jitsi_meet_flutter_sdk.JitsiMeetEventStreamHandler
import org.jitsi.meet.sdk.JitsiMeet

class WrapperJitsiMeetActivity : JitsiMeetActivity() {
    private val eventStreamHandler = JitsiMeetEventStreamHandler.instance
    private val broadcastReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            this@WrapperJitsiMeetActivity.onBroadcastReceived(intent)
        }
    }

    companion object {
        fun launch(context: Context, options: JitsiMeetConferenceOptions?) {
            val intent = Intent(context, WrapperJitsiMeetActivity::class.java)
            intent.action = "org.jitsi.meet.CONFERENCE"
            intent.putExtra("JitsiMeetConferenceOptions", options)
            if (context !is Activity) {
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        showOnLockscreen()

        // Ensure JitsiMeet is initialized as a safeguard
        try {
            val defaultOptions = JitsiMeetConferenceOptions.Builder().build()
            JitsiMeet.setDefaultConferenceOptions(defaultOptions)
        } catch (e: Exception) {
            // Log or handle initialization error
        }

        super.onCreate(savedInstanceState)
        registerForBroadcastMessages()
        registerBackHandler()
    }

    // Consort: whether the SDK is done with the conference,
    // so that finishing this activity won't leave it.
    private var readyToClose = false

    // Consort: with predictive back (targetSdk 36 on Android 16), Android no
    // longer calls JitsiMeetActivity.onBackPressed, so the back gesture just
    // finished this activity, leaving the call.  Hand it to the SDK's React
    // Native back handling instead, which closes an open menu or screen, or
    // else keeps the call going in picture-in-picture.
    private fun registerBackHandler() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                JitsiMeetActivityDelegate.onBackPressed()
            }
        })
    }

    override fun onReadyToClose() {
        readyToClose = true
        super.onReadyToClose()
    }

    // Consort: when nothing in the SDK handles a back press, it finishes this
    // activity, which would leave the call.  Keep the call going instead,
    // and return to the app.
    override fun finish() {
        if (!readyToClose) {
            moveTaskToBack(true)
            return
        }
        super.finish()
    }

    private fun showOnLockscreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun registerForBroadcastMessages() {
        val intentFilter = IntentFilter()
        for (eventType in BroadcastEvent.Type.values()) {
            intentFilter.addAction(eventType.action)
        }
        intentFilter.addAction("org.jitsi.meet.ENTER_PICTURE_IN_PICTURE")
        LocalBroadcastManager.getInstance(this)
            .registerReceiver(this.broadcastReceiver, intentFilter)
    }

    private fun onBroadcastReceived(intent: Intent?) {
        if (intent != null) {
            if (intent.action == "org.jitsi.meet.ENTER_PICTURE_IN_PICTURE") {
                enterPiP()
            } else {
                val event = BroadcastEvent(intent)
                val data = event.data
                when (event.type.action!!) {
                    BroadcastEvent.Type.CONFERENCE_JOINED.action -> eventStreamHandler.conferenceJoined(data)
                    BroadcastEvent.Type.CONFERENCE_TERMINATED.action -> eventStreamHandler.conferenceTerminated(
                        data
                    )

                    BroadcastEvent.Type.CONFERENCE_WILL_JOIN.action -> eventStreamHandler.conferenceWillJoin(
                        data
                    )

                    BroadcastEvent.Type.PARTICIPANT_JOINED.action -> eventStreamHandler.participantJoined(data)
                    BroadcastEvent.Type.PARTICIPANT_LEFT.action -> eventStreamHandler.participantLeft(data)
                    BroadcastEvent.Type.AUDIO_MUTED_CHANGED.action -> eventStreamHandler.audioMutedChanged(data)
                    BroadcastEvent.Type.VIDEO_MUTED_CHANGED.action -> eventStreamHandler.videoMutedChanged(data)
                    BroadcastEvent.Type.ENDPOINT_TEXT_MESSAGE_RECEIVED.action -> eventStreamHandler.endpointTextMessageReceived(
                        data
                    )

                    BroadcastEvent.Type.SCREEN_SHARE_TOGGLED.action -> eventStreamHandler.screenShareToggled(
                        data
                    )

                    BroadcastEvent.Type.CHAT_MESSAGE_RECEIVED.action -> eventStreamHandler.chatMessageReceived(
                        data
                    )

                    BroadcastEvent.Type.CHAT_TOGGLED.action -> eventStreamHandler.chatToggled(data)
                    BroadcastEvent.Type.PARTICIPANTS_INFO_RETRIEVED.action -> eventStreamHandler.participantsInfoRetrieved(
                        data
                    )

                    BroadcastEvent.Type.READY_TO_CLOSE.action -> eventStreamHandler.readyToClose()

                    BroadcastEvent.Type.CUSTOM_BUTTON_PRESSED.action -> eventStreamHandler.customButtonPressed(
                        data
                    )

                    else -> {}
                }
            }
        }
    }

    override fun onDestroy() {
        LocalBroadcastManager.getInstance(this).unregisterReceiver(this.broadcastReceiver)
        super.onDestroy()
    }

    fun enterPiP() {
        jitsiView?.enterPictureInPicture()
    }
}
