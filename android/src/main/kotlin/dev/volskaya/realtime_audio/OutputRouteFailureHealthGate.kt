package dev.volskaya.realtime_audio

/** Emits route-failure health once per failed-state transition. */
class OutputRouteFailureHealthGate {
  private var failed = false

  fun shouldEmit(result: OutputRouteSelectionResult): Boolean {
    if (result != OutputRouteSelectionResult.FAILED) {
      failed = false
      return false
    }
    if (failed) return false
    failed = true
    return true
  }
}

object OutputRouteFailureHealthPayload {
  fun build(
    engineWasRunning: Boolean,
    queuedChunkCount: Int,
    activeRoute: String?,
    outputSampleRate: Int,
  ): Map<String, Any?> = mapOf(
    "type" to "output_route_selection_failed",
    "engineWasRunning" to engineWasRunning,
    "queuedChunkCount" to queuedChunkCount,
    "message" to "Requested output route was not applied.",
    "outputRoute" to activeRoute,
    "outputSampleRate" to outputSampleRate,
  )
}
