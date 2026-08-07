package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OutputRouteFailureHealthGateTest {
  @Test
  fun `emits once per transition into failure and rearms after recovery`() {
    val gate = OutputRouteFailureHealthGate()

    assertFalse(gate.shouldEmit(OutputRouteSelectionResult.AUTOMATIC))
    assertTrue(gate.shouldEmit(OutputRouteSelectionResult.FAILED))
    assertFalse(gate.shouldEmit(OutputRouteSelectionResult.FAILED))
    assertFalse(gate.shouldEmit(OutputRouteSelectionResult.APPLIED))
    assertTrue(gate.shouldEmit(OutputRouteSelectionResult.FAILED))
  }

  @Test
  fun `every nonfailure result rearms the next failure`() {
    for (recovered in OutputRouteSelectionResult.entries.filterNot {
      it == OutputRouteSelectionResult.FAILED
    }) {
      val gate = OutputRouteFailureHealthGate()

      assertTrue(gate.shouldEmit(OutputRouteSelectionResult.FAILED))
      assertFalse(gate.shouldEmit(recovered))
      assertTrue(gate.shouldEmit(OutputRouteSelectionResult.FAILED))
    }
  }

  @Test
  fun `health payload preserves the live player queue size`() {
    val payload = OutputRouteFailureHealthPayload.build(
      engineWasRunning = true,
      queuedChunkCount = 7,
      activeRoute = "receiver",
      outputSampleRate = 24_000,
    )

    assertEquals(7, payload["queuedChunkCount"])
    assertEquals("output_route_selection_failed", payload["type"])
  }
}
