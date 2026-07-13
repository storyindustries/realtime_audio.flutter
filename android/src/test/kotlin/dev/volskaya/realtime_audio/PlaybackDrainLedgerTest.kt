package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class PlaybackDrainLedgerTest {
  @Test
  fun writeCompletionDoesNotMeanDevicePlaybackOrDrain() {
    val ledger = PlaybackDrainLedger()
    ledger.enqueue("chunk-1", frameCount = 2_400)

    val marker = ledger.markWritten("chunk-1")

    assertEquals(2_400L, marker)
    assertEquals(emptyList(), ledger.advancePlaybackHead(2_399).playedChunkIds)
    assertFalse(ledger.isEmpty)
  }

  @Test
  fun exactPlaybackHeadMarkerRetiresChunkAndDrains() {
    val ledger = PlaybackDrainLedger()
    ledger.enqueue("chunk-1", frameCount = 2_400)
    ledger.markWritten("chunk-1")

    val advance = ledger.advancePlaybackHead(2_400)

    assertEquals(listOf("chunk-1"), advance.playedChunkIds)
    assertTrue(advance.drained)
    assertEquals(null, advance.nextMarkerFrame)
  }

  @Test
  fun oneLateMarkerRetiresEveryFullyRenderedWrittenChunk() {
    val ledger = PlaybackDrainLedger()
    ledger.enqueue("chunk-1", frameCount = 1_200)
    ledger.enqueue("chunk-2", frameCount = 1_200)
    ledger.markWritten("chunk-1")
    ledger.markWritten("chunk-2")

    val advance = ledger.advancePlaybackHead(2_400)

    assertEquals(listOf("chunk-1", "chunk-2"), advance.playedChunkIds)
    assertTrue(advance.drained)
  }

  @Test
  fun unwrittenChunkCannotBeRetiredEvenIfHeadValueIsAhead() {
    val ledger = PlaybackDrainLedger()
    ledger.enqueue("chunk-1", frameCount = 1_200)

    val advance = ledger.advancePlaybackHead(1_200)

    assertEquals(emptyList(), advance.playedChunkIds)
    assertFalse(advance.drained)
    assertEquals(null, advance.nextMarkerFrame)
  }

  @Test
  fun resetInvalidatesOldTimelineAndNextChunkStartsAtZero() {
    val ledger = PlaybackDrainLedger()
    ledger.enqueue("old", frameCount = 1_200)
    ledger.markWritten("old")

    ledger.reset()
    ledger.enqueue("new", frameCount = 800)

    assertEquals(800L, ledger.markWritten("new"))
    assertEquals(emptyList(), ledger.advancePlaybackHead(799).playedChunkIds)
  }

  @Test
  fun markerPassedBetweenReadAndArmSchedulesAsyncReconciliation() {
    assertEquals(
      PlaybackDrainSignalAction.RECONCILE_ASYNC,
      PlaybackDrainSignal.decide(markerArmed = true, headAfterArm = 2_400, markerFrame = 2_400),
    )
  }

  @Test
  fun markerFailureFallsBackToExactHeadPolling() {
    assertEquals(
      PlaybackDrainSignalAction.POLL_EXACT_HEAD,
      PlaybackDrainSignal.decide(markerArmed = false, headAfterArm = 2_399, markerFrame = 2_400),
    )
  }

  @Test
  fun markerFailureAfterHeadCrossedStillReconcilesAsynchronously() {
    assertEquals(
      PlaybackDrainSignalAction.RECONCILE_ASYNC,
      PlaybackDrainSignal.decide(markerArmed = false, headAfterArm = 2_400, markerFrame = 2_400),
    )
  }

  @Test
  fun armedFutureMarkerWaitsForPlatformCallbackWithoutPolling() {
    assertEquals(
      PlaybackDrainSignalAction.WAIT_FOR_MARKER,
      PlaybackDrainSignal.decide(markerArmed = true, headAfterArm = 2_399, markerFrame = 2_400),
    )
  }

  @Test
  fun fallbackPollIsBoundedAndGenerationSafe() {
    val poll = PlaybackHeadFallbackPoll(generation = 7, markerFrame = 2_400, maxAttempts = 2)

    assertEquals(PlaybackHeadPollAction.POLL_AGAIN, poll.observe(generation = 7, renderedFrame = 2_399))
    assertEquals(PlaybackHeadPollAction.EXHAUSTED, poll.observe(generation = 7, renderedFrame = 2_399))
    assertEquals(PlaybackHeadPollAction.CANCELLED, poll.observe(generation = 8, renderedFrame = 2_400))
  }

  @Test
  fun fallbackPollReconcilesOnlyFromExactHeadEvidence() {
    val poll = PlaybackHeadFallbackPoll(generation = 7, markerFrame = 2_400, maxAttempts = 2)

    assertEquals(PlaybackHeadPollAction.RECONCILE, poll.observe(generation = 7, renderedFrame = 2_400))
  }
}
