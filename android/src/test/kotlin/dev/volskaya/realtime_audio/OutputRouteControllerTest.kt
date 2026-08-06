package dev.volskaya.realtime_audio

import android.media.AudioDeviceInfo
import android.media.AudioManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OutputRouteControllerTest {
  @Test
  fun `voice communication attributes control call volume not media volume`() {
    assertEquals(
      AudioManager.STREAM_VOICE_CALL,
      PlaybackVolumePolicy.fallbackStreamForUsage(android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION),
    )
    assertEquals(
      AudioManager.STREAM_MUSIC,
      PlaybackVolumePolicy.fallbackStreamForUsage(android.media.AudioAttributes.USAGE_MEDIA),
    )
    assertEquals(
      AudioManager.STREAM_VOICE_CALL,
      PlaybackVolumePolicy.resolveStream(
        usage = android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION,
        derivedStream = AudioManager.STREAM_VOICE_CALL,
      ),
    )
    assertEquals(
      AudioManager.STREAM_VOICE_CALL,
      PlaybackVolumePolicy.resolveStream(
        usage = android.media.AudioAttributes.USAGE_VOICE_COMMUNICATION,
        derivedStream = AudioManager.USE_DEFAULT_STREAM_TYPE,
      ),
    )
  }

  @Test
  fun `minimum volume rounds upward and never lowers user volume`() {
    assertEquals(6, PlaybackVolumePolicy.levelWithFloor(current = 2, maximum = 9, minimum = 0.6))
    assertEquals(8, PlaybackVolumePolicy.levelWithFloor(current = 8, maximum = 9, minimum = 0.6))
  }

  @Test
  fun `api 31 route set must pass boolean and readback`() {
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker()),
      active = receiver(),
    )
    val controller = OutputRouteController(system)
    controller.start()
    assertEquals(OutputRoute.SPEAKER, controller.snapshot().active)

    system.selectionStatus = DeviceSelectionStatus.FAILED
    val rejected = controller.select(OutputRoute.RECEIVER)
    assertEquals(OutputRouteSelectionResult.FAILED, rejected.selectionResult)
    assertEquals(OutputRoute.SPEAKER, rejected.active)
    assertEquals(OutputRoute.RECEIVER, rejected.requested)

    system.selectionStatus = DeviceSelectionStatus.APPLIED
    system.applySelectionToReadback = false
    val mismatched = controller.select(OutputRoute.RECEIVER)
    assertEquals(OutputRouteSelectionResult.FAILED, mismatched.selectionResult)
    assertEquals(OutputRoute.SPEAKER, mismatched.active)
  }

  @Test
  fun `requested route survives removal and reapplies when route returns`() {
    val bluetooth = bluetooth()
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker(), bluetooth),
      active = speaker(),
    )
    val controller = OutputRouteController(system)
    controller.start()
    assertEquals(OutputRoute.BLUETOOTH, controller.select(OutputRoute.BLUETOOTH).active)

    system.available.remove(bluetooth)
    system.active = receiver()
    system.emitDevicesChanged()
    assertEquals(OutputRoute.BLUETOOTH, controller.snapshot().requested)
    assertEquals(OutputRouteSelectionResult.UNAVAILABLE, controller.snapshot().selectionResult)
    assertEquals(OutputRoute.SPEAKER, controller.snapshot().active)

    system.available.add(bluetooth)
    system.emitDevicesChanged()
    assertEquals(OutputRoute.BLUETOOTH, controller.snapshot().active)
    assertEquals(OutputRouteSelectionResult.APPLIED, controller.snapshot().selectionResult)
  }

  @Test
  fun `returning requested route supersedes a pending automatic fallback`() {
    val bluetooth = bluetooth()
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker(), bluetooth),
      active = bluetooth,
    )
    val controller = OutputRouteController(system)
    controller.start()
    controller.select(OutputRoute.BLUETOOTH)

    system.selectionStatus = DeviceSelectionStatus.PENDING
    system.available.remove(bluetooth)
    system.active = receiver()
    system.emitDevicesChanged()
    assertEquals(OutputRouteSelectionResult.UNAVAILABLE, controller.snapshot().selectionResult)

    system.available.add(bluetooth)
    system.emitDevicesChanged()
    assertEquals(OutputRouteSelectionResult.PENDING, controller.snapshot().selectionResult)
    assertEquals(OutputRoute.BLUETOOTH, controller.snapshot().requested)
  }

  @Test
  fun `route listeners reapply automatic policy and are removed on stop`() {
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker()),
      active = receiver(),
    )
    val controller = OutputRouteController(system)
    controller.start()
    assertEquals(OutputRoute.SPEAKER, controller.snapshot().active)
    assertTrue(system.listenerRegistered)

    val bluetooth = bluetooth()
    system.available.add(bluetooth)
    system.emitDevicesChanged()
    assertEquals(OutputRoute.BLUETOOTH, controller.snapshot().active)

    controller.stop()
    assertFalse(system.listenerRegistered)
  }

  @Test
  fun `explicit speaker selection wins while bluetooth is available`() {
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker(), bluetooth()),
      active = bluetooth(),
    )
    val controller = OutputRouteController(system)
    controller.start()

    val selected = controller.select(OutputRoute.SPEAKER)
    assertEquals(OutputRoute.SPEAKER, selected.active)
    assertEquals(OutputRoute.SPEAKER, selected.requested)

    system.emitDevicesChanged()
    assertEquals(OutputRoute.SPEAKER, controller.snapshot().active)
  }

  @Test
  fun `inactive route API retains request but never mutates communication routing`() {
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker()),
      active = receiver(),
    )
    val controller = OutputRouteController(system)

    assertEquals(OutputRouteSelectionResult.UNAVAILABLE, controller.snapshot().selectionResult)
    assertNull(controller.snapshot().active)

    val inactive = controller.select(OutputRoute.SPEAKER)
    assertEquals(OutputRouteSelectionResult.UNAVAILABLE, inactive.selectionResult)
    assertEquals(OutputRoute.SPEAKER, inactive.requested)
    assertEquals(emptyList(), inactive.available)
    assertEquals(0, system.setCalls)
  }

  @Test
  fun `automatic mode with no selectable target clears stale result`() {
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver()),
      active = receiver(),
    )
    val controller = OutputRouteController(system)
    controller.start()
    assertEquals(OutputRouteSelectionResult.AUTOMATIC, controller.snapshot().selectionResult)

    assertEquals(
      OutputRouteSelectionResult.UNAVAILABLE,
      controller.select(OutputRoute.SPEAKER).selectionResult,
    )
    assertEquals(OutputRouteSelectionResult.AUTOMATIC, controller.select(null).selectionResult)
  }

  @Test
  fun `playback-only and non-voice-processing engines cannot activate route control`() {
    assertFalse(
      OutputRouteActivationPolicy.shouldActivate(
        recorderEnabled = false,
        voiceProcessingRequested = true,
        communicationMode = true,
      ),
    )
    assertFalse(
      OutputRouteActivationPolicy.shouldActivate(
        recorderEnabled = true,
        voiceProcessingRequested = false,
        communicationMode = false,
      ),
    )
    assertTrue(
      OutputRouteActivationPolicy.shouldActivate(
        recorderEnabled = true,
        voiceProcessingRequested = true,
        communicationMode = true,
      ),
    )
  }

  @Test
  fun `accepted asynchronous selection stays pending until route callback readback`() {
    val bluetooth = bluetooth()
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker(), bluetooth),
      active = speaker(),
    ).apply {
      selectionStatus = DeviceSelectionStatus.PENDING
    }
    val controller = OutputRouteController(system)
    controller.start()

    val pending = controller.select(OutputRoute.BLUETOOTH)
    assertEquals(OutputRouteSelectionResult.PENDING, pending.selectionResult)
    assertEquals(OutputRoute.SPEAKER, pending.active)
    assertTrue(system.timeoutScheduled)

    system.active = bluetooth
    system.emitDevicesChanged()
    assertEquals(OutputRouteSelectionResult.APPLIED, controller.snapshot().selectionResult)
    assertEquals(OutputRoute.BLUETOOTH, controller.snapshot().active)
    assertFalse(system.timeoutScheduled)
  }

  @Test
  fun `asynchronous disconnect and timeout fail pending selection`() {
    val bluetooth = bluetooth()
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker(), bluetooth),
      active = speaker(),
    ).apply {
      selectionStatus = DeviceSelectionStatus.PENDING
    }
    val controller = OutputRouteController(system)
    controller.start()
    controller.select(OutputRoute.BLUETOOTH)

    system.emitSelectionFailed()
    assertEquals(OutputRouteSelectionResult.FAILED, controller.snapshot().selectionResult)

    controller.select(OutputRoute.BLUETOOTH)
    system.fireTimeout()
    assertEquals(OutputRouteSelectionResult.FAILED, controller.snapshot().selectionResult)
  }

  @Test
  fun `stop unregisters route and sco callbacks and cancels pending timeout`() {
    val system = FakeCommunicationAudioSystem(
      available = mutableListOf(receiver(), speaker(), bluetooth()),
      active = speaker(),
    ).apply {
      selectionStatus = DeviceSelectionStatus.PENDING
    }
    val controller = OutputRouteController(system)
    controller.start()
    controller.select(OutputRoute.BLUETOOTH)

    controller.stop()

    assertFalse(system.listenerRegistered)
    assertFalse(system.timeoutScheduled)
    assertEquals(1, system.unregisterCalls)
  }

  @Test
  fun `sco broadcasts distinguish connected and failed states`() {
    assertEquals(
      RouteEvent.CHANGED,
      LegacyScoRouteEvent.fromState(AudioManager.SCO_AUDIO_STATE_CONNECTED),
    )
    assertEquals(
      RouteEvent.SELECTION_FAILED,
      LegacyScoRouteEvent.fromState(AudioManager.SCO_AUDIO_STATE_DISCONNECTED),
    )
    assertNull(LegacyScoRouteEvent.fromState(AudioManager.SCO_AUDIO_STATE_CONNECTING))
  }

  @Test
  fun `automatic selection preserves external route and otherwise chooses speaker`() {
    assertEquals(
      AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        availableTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        ),
      ),
    )
    assertEquals(
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        ),
      ),
    )
    assertNull(
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = OutputRoute.BLUETOOTH,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        availableTypes = listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER),
      ),
    )
  }

  @Test
  fun `pre 31 sco capability alone does not advertise bluetooth`() {
    assertEquals(
      listOf(
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      ),
      LegacyRouteInventory.availableTypes(
        connectedOutputTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        ),
      ),
    )
    assertEquals(
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      CommRoutePolicy.desiredCommunicationDeviceType(
        requested = null,
        activeType = AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        availableTypes = LegacyRouteInventory.availableTypes(
          connectedOutputTypes = listOf(
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          ),
        ),
      ),
    )
  }

  @Test
  fun `pre 31 a2dp-only output is not advertised as communication bluetooth`() {
    assertEquals(
      listOf(
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
      ),
      LegacyRouteInventory.availableTypes(
        connectedOutputTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        ),
      ),
    )
  }

  @Test
  fun `pre 31 wired connection does not advertise an inapplicable receiver`() {
    assertEquals(
      listOf(
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
      ),
      LegacyRouteInventory.availableTypes(
        connectedOutputTypes = listOf(
          AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
          AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
          AudioDeviceInfo.TYPE_WIRED_HEADSET,
        ),
      ),
    )
  }
}

private class FakeCommunicationAudioSystem(
  val available: MutableList<CommunicationDevice>,
  var active: CommunicationDevice?,
) : CommunicationAudioSystem {
  var selectionStatus = DeviceSelectionStatus.APPLIED
  var applySelectionToReadback = true
  var listenerRegistered = false
  var setCalls = 0
  var unregisterCalls = 0
  var timeoutScheduled = false
  private var listener: ((RouteEvent) -> Unit)? = null
  private var timeout: (() -> Unit)? = null

  override fun availableDevices(): List<CommunicationDevice> = available.toList()
  override fun activeDevice(): CommunicationDevice? = active
  override fun setDevice(device: CommunicationDevice): DeviceSelectionStatus {
    setCalls++
    if (selectionStatus == DeviceSelectionStatus.APPLIED && applySelectionToReadback) active = device
    return selectionStatus
  }
  override fun clearDevice(): Boolean = true
  override fun registerRouteListener(listener: (RouteEvent) -> Unit) {
    listenerRegistered = true
    this.listener = listener
  }
  override fun unregisterRouteListener() {
    unregisterCalls++
    listenerRegistered = false
    listener = null
  }
  override fun applicableVolume(): ApplicableVolume? = null
  override fun ensureMinimumVolume(minimum: Double): ApplicableVolume? = null
  override fun scheduleSelectionTimeout(action: () -> Unit): () -> Unit {
    timeoutScheduled = true
    timeout = action
    return {
      timeoutScheduled = false
      timeout = null
    }
  }
  fun emitDevicesChanged() = listener?.invoke(RouteEvent.CHANGED)
  fun emitSelectionFailed() = listener?.invoke(RouteEvent.SELECTION_FAILED)
  fun fireTimeout() {
    val action = timeout
    timeoutScheduled = false
    timeout = null
    action?.invoke()
  }
}

private fun receiver() = CommunicationDevice(1, AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
private fun speaker() = CommunicationDevice(2, AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
private fun bluetooth() = CommunicationDevice(3, AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
