package dev.volskaya.realtime_audio

/**
 * One communication route controller per process-global audio session.
 *
 * FlutterEngine instances own separate plugin objects, while Android's
 * communication device is process-global. A shared controller prevents their
 * independent automatic policies from repeatedly overriding each other.
 */
class SharedOutputRouteController {
  class Lease internal constructor(internal val id: Long)
  data class Acquisition(
    val lease: Lease,
    val isFirst: Boolean,
    val state: OutputRouteState,
  )
  data class Release(
    val isLast: Boolean,
    val state: OutputRouteState,
  )

  private var nextLeaseId = 0L
  private var controller: OutputRouteController? = null
  private val observers = linkedMapOf<Long, (OutputRouteState) -> Unit>()

  @Synchronized
  fun acquire(
    system: CommunicationAudioSystem,
    observer: (OutputRouteState) -> Unit,
  ): Acquisition {
    val lease = Lease(++nextLeaseId)
    observers[lease.id] = observer
    val existing = controller
    if (existing != null) {
      val state = existing.snapshot()
      observer(state)
      return Acquisition(lease, isFirst = false, state)
    }

    val created = OutputRouteController(system, ::notifyObservers)
    controller = created
    return try {
      Acquisition(lease, isFirst = true, created.start())
    } catch (error: Throwable) {
      observers.remove(lease.id)
      runCatching { created.stop() }
      controller = null
      throw error
    }
  }

  @Synchronized
  fun release(lease: Lease): Release {
    observers.remove(lease.id)
    val current = controller ?: return Release(isLast = true, inactiveState())
    if (observers.isNotEmpty()) {
      return Release(isLast = false, current.snapshot())
    }
    current.stop()
    val state = current.snapshot()
    controller = null
    return Release(isLast = true, state)
  }

  @Synchronized
  fun snapshot(): OutputRouteState = controller?.snapshot() ?: inactiveState()

  @Synchronized
  fun select(route: OutputRoute?): OutputRouteState =
    controller?.select(route) ?: inactiveState(requested = route)

  @Synchronized
  fun ensureMinimumVolume(minimum: Double): OutputRouteState =
    controller?.ensureMinimumVolume(minimum) ?: inactiveState()

  @Synchronized
  private fun notifyObservers(state: OutputRouteState) {
    observers.values.toList().forEach { it(state) }
  }

  private fun inactiveState(requested: OutputRoute? = null): OutputRouteState = OutputRouteState(
    active = null,
    available = emptyList(),
    requested = requested,
    selectionResult = OutputRouteSelectionResult.UNAVAILABLE,
    volume = null,
  )
}
