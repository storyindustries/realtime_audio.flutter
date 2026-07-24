package dev.volskaya.realtime_audio

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The APM teardown race (codex review of biograph PR #674): the AudioTrack
 * writer thread feeds the far-end reference via `processRender` while
 * `release()` may run concurrently on the main thread from recorder recovery
 * (`setRecorderEnabled(false)`) or `dispose()`. Without one monitor over every
 * native-pointer use, `nativeDestroy` can free the APM while
 * `ProcessReverseStream` is executing — a native use-after-free crash in a
 * live call. Capture is exposed the same way: `processCapture` runs on a
 * `Dispatchers.IO` coroutine, not the main thread.
 *
 * These tests drive [WebRtcApm] through a latching [ApmNativeBridge] fake so
 * the overlap is deterministic, and assert the contract: destruction WAITS for
 * an in-flight native call, and any post-release call is a no-op.
 */
class WebRtcApmConcurrencyTest {

  private class LatchingBridge : ApmNativeBridge {
    val renderEntered = CountDownLatch(1)
    val renderRelease = CountDownLatch(1)
    val captureEntered = CountDownLatch(1)
    val captureRelease = CountDownLatch(1)
    val destroyCount = AtomicInteger(0)
    val destroyedPtr = AtomicLong(0)
    val callsAfterDestroy = AtomicInteger(0)

    private fun recordIfDestroyed() {
      if (destroyCount.get() > 0) callsAfterDestroy.incrementAndGet()
    }

    override fun create(
      captureSampleRate: Int,
      renderSampleRate: Int,
      aecEnabled: Boolean,
      nsEnabled: Boolean,
      agcEnabled: Boolean,
      mobileAec: Boolean,
    ): Long = 42L

    override fun destroy(ptr: Long) {
      destroyCount.incrementAndGet()
      destroyedPtr.set(ptr)
    }

    override fun setStreamDelay(ptr: Long, delayMs: Int) = recordIfDestroyed()

    override fun processCapture(ptr: Long, audioData: ByteArray): ByteArray {
      recordIfDestroyed()
      captureEntered.countDown()
      captureRelease.await(5, TimeUnit.SECONDS)
      return audioData
    }

    override fun processRender(ptr: Long, audioData: ByteArray) {
      recordIfDestroyed()
      renderEntered.countDown()
      renderRelease.await(5, TimeUnit.SECONDS)
    }

    override fun echoReturnLossEnhancementDb(ptr: Long): Double? {
      recordIfDestroyed()
      return null
    }
  }

  private fun apm(bridge: ApmNativeBridge) =
    WebRtcApm(
      captureSampleRate = 48000,
      renderSampleRate = 24000,
      bridge = bridge,
    )

  @Test
  fun `release waits for an in-flight processRender`() {
    val bridge = LatchingBridge()
    val apm = apm(bridge)

    val render = thread { apm.processRender(ByteArray(480)) }
    assertTrue(bridge.renderEntered.await(5, TimeUnit.SECONDS), "render never reached the bridge")

    val releaseDone = CountDownLatch(1)
    val release = thread {
      apm.release()
      releaseDone.countDown()
    }

    // While the render call is inside the native bridge, release must block.
    assertFalse(
      releaseDone.await(300, TimeUnit.MILLISECONDS),
      "release() completed while processRender was in-flight — native use-after-free window",
    )
    assertEquals(0, bridge.destroyCount.get())

    bridge.renderRelease.countDown()
    render.join(5000)
    assertTrue(releaseDone.await(5, TimeUnit.SECONDS), "release never completed after render finished")
    release.join(5000)

    assertEquals(1, bridge.destroyCount.get())
    assertEquals(42L, bridge.destroyedPtr.get())
    assertEquals(0, bridge.callsAfterDestroy.get(), "bridge saw a call after destroy")
  }

  @Test
  fun `release waits for an in-flight processCapture`() {
    val bridge = LatchingBridge()
    val apm = apm(bridge)

    val capture = thread { apm.processCapture(ByteArray(1920)) }
    assertTrue(bridge.captureEntered.await(5, TimeUnit.SECONDS), "capture never reached the bridge")

    val releaseDone = CountDownLatch(1)
    val release = thread {
      apm.release()
      releaseDone.countDown()
    }

    assertFalse(
      releaseDone.await(300, TimeUnit.MILLISECONDS),
      "release() completed while processCapture was in-flight",
    )

    bridge.captureRelease.countDown()
    capture.join(5000)
    assertTrue(releaseDone.await(5, TimeUnit.SECONDS))
    release.join(5000)
    assertEquals(1, bridge.destroyCount.get())
    assertEquals(0, bridge.callsAfterDestroy.get(), "bridge saw a call after destroy")
  }

  @Test
  fun `post-release calls are no-ops`() {
    val bridge = LatchingBridge()
    // Unlatch up-front — this test has no in-flight overlap.
    bridge.renderRelease.countDown()
    bridge.captureRelease.countDown()
    val apm = apm(bridge)

    apm.release()
    assertEquals(1, bridge.destroyCount.get())
    assertFalse(apm.isAvailable)

    val input = ByteArray(1920) { it.toByte() }
    val out = apm.processCapture(input)
    apm.processRender(ByteArray(480))
    apm.setStreamDelay(120)
    apm.release()

    assertTrue(out === input, "post-release processCapture must pass audio through untouched")
    assertEquals(0, bridge.callsAfterDestroy.get(), "released APM must never re-enter the native bridge")
    assertEquals(1, bridge.destroyCount.get(), "double release must not double-destroy")
  }

  @Test
  fun `unavailable bridge yields inert apm`() {
    val apm =
      WebRtcApm(
        captureSampleRate = 48000,
        renderSampleRate = 24000,
        bridge = null,
      )
    assertFalse(apm.isAvailable)
    val input = ByteArray(4)
    assertTrue(apm.processCapture(input) === input)
    apm.processRender(input)
    apm.release()
  }
}
