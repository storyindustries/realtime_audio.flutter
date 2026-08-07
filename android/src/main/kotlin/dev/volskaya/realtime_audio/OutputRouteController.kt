package dev.volskaya.realtime_audio

enum class OutputRoute(val wire: String) {
  SPEAKER("speaker"),
  RECEIVER("receiver"),
  WIRED("wired"),
  BLUETOOTH("bluetooth"),
  OTHER("other");

  companion object {
    fun fromWire(value: String?): OutputRoute? = entries.firstOrNull { it.wire == value }
  }
}

enum class OutputRouteSelectionResult(val wire: String) {
  AUTOMATIC("automatic"),
  APPLIED("applied"),
  PENDING("pending"),
  FAILED("failed"),
  UNAVAILABLE("unavailable"),
}

enum class DeviceSelectionStatus { APPLIED, PENDING, FAILED }
enum class RouteEvent { CHANGED, SELECTION_FAILED }

data class CommunicationDevice(val id: Int, val type: Int)
data class ApplicableVolume(val stream: String, val normalized: Double)

data class OutputRouteState(
  val active: OutputRoute?,
  val available: List<OutputRoute>,
  val requested: OutputRoute?,
  val selectionResult: OutputRouteSelectionResult,
  val volume: ApplicableVolume?,
) {
  fun toMap(): Map<String, Any?> = mapOf(
    "active" to active?.wire,
    "available" to available.map { it.wire },
    "requested" to requested?.wire,
    "selectionResult" to selectionResult.wire,
    "volumeControlStream" to volume?.stream,
    "volume" to volume?.normalized,
  )
}

interface CommunicationAudioSystem {
  fun availableDevices(): List<CommunicationDevice>
  fun activeDevice(): CommunicationDevice?
  fun setDevice(device: CommunicationDevice): DeviceSelectionStatus
  fun clearDevice(): Boolean
  fun registerRouteListener(listener: (RouteEvent) -> Unit)
  fun unregisterRouteListener()
  fun scheduleSelectionTimeout(action: () -> Unit): () -> Unit
  fun applicableVolume(): ApplicableVolume?
  fun ensureMinimumVolume(minimum: Double): ApplicableVolume?
}

object OutputRouteActivationPolicy {
  fun shouldActivate(
    recorderEnabled: Boolean,
    voiceProcessingRequested: Boolean,
    communicationMode: Boolean,
  ): Boolean = recorderEnabled && voiceProcessingRequested && communicationMode
}

/** Route policy and read-back contract, independent from Android callbacks. */
class OutputRouteController(
  private val system: CommunicationAudioSystem,
  private val onStateChanged: (OutputRouteState) -> Unit = {},
) {
  private var started = false
  private var requested: OutputRoute? = null
  private var selectionResult = OutputRouteSelectionResult.AUTOMATIC
  private var pendingSelection: PendingSelection? = null
  private var cancelPendingTimeout: (() -> Unit)? = null

  private data class PendingSelection(
    val device: CommunicationDevice,
    val completedResult: OutputRouteSelectionResult,
  )

  fun start(): OutputRouteState {
    if (!started) {
      started = true
      system.registerRouteListener(::onRouteEvent)
    }
    return applyPolicy()
  }

  fun stop() {
    if (!started) return
    started = false
    clearPendingSelection()
    system.unregisterRouteListener()
    emitSnapshot()
  }

  fun select(route: OutputRoute?): OutputRouteState {
    requested = route
    clearPendingSelection()
    if (!started) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      return emitSnapshot()
    }
    if (route == OutputRoute.OTHER) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      return emitSnapshot()
    }
    return applyPolicy()
  }

  fun ensureMinimumVolume(minimum: Double): OutputRouteState {
    system.ensureMinimumVolume(minimum)
    return emitSnapshot()
  }

  fun snapshot(): OutputRouteState = buildSnapshot()

  private fun onRouteEvent(event: RouteEvent) {
    if (!started) return
    val pending = pendingSelection
    if (event == RouteEvent.SELECTION_FAILED) {
      if (pending != null) {
        clearPendingSelection()
        selectionResult = OutputRouteSelectionResult.FAILED
        emitSnapshot()
      }
      return
    }
    if (pending != null) {
      if (pending.completedResult == OutputRouteSelectionResult.UNAVAILABLE &&
        requestedRouteIsAvailable()
      ) {
        clearPendingSelection()
        applyPolicy()
        return
      }
      val current = system.activeDevice()
      if (devicesMatch(current, pending.device)) {
        clearPendingSelection()
        selectionResult = pending.completedResult
        emitSnapshot()
        return
      }
      val stillAvailable = system.availableDevices().any { devicesMatch(it, pending.device) }
      if (stillAvailable) {
        emitSnapshot()
        return
      }
      clearPendingSelection()
    }
    applyPolicy()
  }

  private fun requestedRouteIsAvailable(): Boolean {
    val route = requested ?: return false
    return system.availableDevices().any { CommRoutePolicy.routeForType(it.type) == route }
  }

  private fun applyPolicy(): OutputRouteState {
    if (!started) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      return emitSnapshot()
    }
    pendingSelection?.let { return emitSnapshot() }
    val available = system.availableDevices()
    val current = system.activeDevice()
    val types = available.map { it.type }
    val requestedType = CommRoutePolicy.desiredCommunicationDeviceType(requested, current?.type, types)
    val requestedDevice = requestedType?.let { type -> available.firstOrNull { it.type == type } }

    if (requested != null && requestedDevice == null) {
      selectionResult = OutputRouteSelectionResult.UNAVAILABLE
      val fallbackType = CommRoutePolicy.desiredCommunicationDeviceType(null, current?.type, types)
      val fallback = fallbackType?.let { type -> available.firstOrNull { it.type == type } }
      return if (fallback == null || devicesMatch(current, fallback)) {
        emitSnapshot()
      } else {
        beginSelection(fallback, OutputRouteSelectionResult.UNAVAILABLE)
      }
    }

    val desired = requestedDevice ?: run {
      selectionResult = OutputRouteSelectionResult.AUTOMATIC
      return emitSnapshot()
    }
    val completedResult = if (requested == null) {
      OutputRouteSelectionResult.AUTOMATIC
    } else {
      OutputRouteSelectionResult.APPLIED
    }
    if (devicesMatch(current, desired)) {
      selectionResult = completedResult
      return emitSnapshot()
    }
    return beginSelection(desired, completedResult)
  }

  private fun beginSelection(
    desired: CommunicationDevice,
    completedResult: OutputRouteSelectionResult,
  ): OutputRouteState {
    return when (system.setDevice(desired)) {
      DeviceSelectionStatus.FAILED -> {
        selectionResult = OutputRouteSelectionResult.FAILED
        emitSnapshot()
      }
      DeviceSelectionStatus.APPLIED -> {
        selectionResult = if (devicesMatch(system.activeDevice(), desired)) {
          completedResult
        } else {
          OutputRouteSelectionResult.FAILED
        }
        emitSnapshot()
      }
      DeviceSelectionStatus.PENDING -> {
        pendingSelection = PendingSelection(desired, completedResult)
        selectionResult = if (completedResult == OutputRouteSelectionResult.UNAVAILABLE) {
          OutputRouteSelectionResult.UNAVAILABLE
        } else {
          OutputRouteSelectionResult.PENDING
        }
        cancelPendingTimeout = system.scheduleSelectionTimeout(::onSelectionTimeout)
        emitSnapshot()
      }
    }
  }

  private fun onSelectionTimeout() {
    if (!started || pendingSelection == null) return
    clearPendingSelection()
    selectionResult = OutputRouteSelectionResult.FAILED
    emitSnapshot()
  }

  private fun clearPendingSelection() {
    pendingSelection = null
    cancelPendingTimeout?.invoke()
    cancelPendingTimeout = null
  }

  private fun devicesMatch(left: CommunicationDevice?, right: CommunicationDevice): Boolean =
    left?.let { it.id == right.id && it.type == right.type } == true

  private fun emitSnapshot(): OutputRouteState = buildSnapshot().also(onStateChanged)

  private fun buildSnapshot(): OutputRouteState {
    val available = (if (started) system.availableDevices() else emptyList())
      .map { CommRoutePolicy.routeForType(it.type) }
      .filterNot { it == OutputRoute.OTHER }
      .distinct()
    return OutputRouteState(
      active = if (started) {
        system.activeDevice()?.let { CommRoutePolicy.routeForType(it.type) }
      } else {
        null
      },
      available = available,
      requested = requested,
      selectionResult = if (started) selectionResult else OutputRouteSelectionResult.UNAVAILABLE,
      volume = system.applicableVolume(),
    )
  }
}
