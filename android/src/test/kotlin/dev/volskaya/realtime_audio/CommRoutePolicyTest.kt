package dev.volskaya.realtime_audio

import android.media.AudioDeviceInfo
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * MODE_IN_COMMUNICATION defaults the route to the EARPIECE on phones, while
 * Ouna is a speakerphone-style call. The policy: force the built-in speaker
 * ONLY when no external playback device (headset/BT/USB/hearing aid) is
 * available — an external device keeps the system's default communication
 * routing (which prefers it), matching what every VoIP app does.
 */
class CommRoutePolicyTest {

  @Test
  fun `no external devices forces the built-in speaker`() {
    assertEquals(
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      CommRoutePolicy.forcedCommunicationDeviceType(
        listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER),
      ),
    )
  }

  @Test
  fun `bluetooth present keeps system routing`() {
    assertNull(
      CommRoutePolicy.forcedCommunicationDeviceType(
        listOf(
          AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        ),
      ),
    )
  }

  @Test
  fun `wired headset present keeps system routing`() {
    assertNull(
      CommRoutePolicy.forcedCommunicationDeviceType(
        listOf(
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_WIRED_HEADSET,
        ),
      ),
    )
  }

  @Test
  fun `usb and ble devices count as external`() {
    assertNull(
      CommRoutePolicy.forcedCommunicationDeviceType(
        listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_USB_HEADSET),
      ),
    )
    assertNull(
      CommRoutePolicy.forcedCommunicationDeviceType(
        listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BLE_HEADSET),
      ),
    )
  }

  @Test
  fun `no speaker available forces nothing`() {
    assertNull(CommRoutePolicy.forcedCommunicationDeviceType(listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)))
  }
}
