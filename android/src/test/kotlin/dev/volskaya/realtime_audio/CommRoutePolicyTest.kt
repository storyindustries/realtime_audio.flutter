package dev.volskaya.realtime_audio

import android.media.AudioDeviceInfo
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * MODE_IN_COMMUNICATION defaults the route to the EARPIECE on phones, while
 * Ouna is a speakerphone-style call. Automatic policy explicitly selects a
 * connected external route, otherwise the built-in speaker. Explicit user
 * selection takes precedence over that policy.
 */
class CommRoutePolicyTest {

  @Test
  fun `no external devices forces the built-in speaker`() {
    assertEquals(
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER),
      ),
    )
  }

  @Test
  fun `bluetooth present is selected explicitly`() {
    assertEquals(
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        ),
      ),
    )
  }

  @Test
  fun `wired headset present is selected explicitly`() {
    assertEquals(
      AudioDeviceInfo.TYPE_WIRED_HEADSET,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_WIRED_HEADSET,
        ),
      ),
    )
  }

  @Test
  fun `usb and ble devices map to coarse external routes`() {
    assertEquals(
      AudioDeviceInfo.TYPE_USB_HEADSET,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_USB_HEADSET),
      ),
    )
    assertEquals(
      AudioDeviceInfo.TYPE_BLE_HEADSET,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, AudioDeviceInfo.TYPE_BLE_HEADSET),
      ),
    )
  }

  @Test
  fun `no speaker available forces nothing`() {
    assertEquals(
      null,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE),
      ),
    )
  }
}
