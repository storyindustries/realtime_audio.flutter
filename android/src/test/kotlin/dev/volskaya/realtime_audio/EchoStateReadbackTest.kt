package dev.volskaya.realtime_audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * The read-back contract every consumer's duplex trust rides on
 * (rev-contract D3): `platform_aec` may be claimed ONLY for an actually
 * attached hardware canceller — the pre-0.0.16 read-back claimed it for the
 * bare VOICE_COMMUNICATION source, the exact unverifiable ghost the 2026-07-24
 * RCA removed — and `webrtc_apm` only for a live APM, with ERLE/mode riding
 * along for evidence-based trust.
 */
class EchoStateReadbackTest {

  @Test
  fun `hardware attach claims platform_aec and wins over a live apm`() {
    val map = EchoStateReadback.build(
      requested = true,
      captureProvenLive = true,
      hardwareAecAttached = true,
      apmLive = true,
      apmMobileAec = false,
      erleDb = null,
    )
    assertEquals("platform_aec", map["mechanism"])
    assertEquals(true, map["nativeEnabled"])
    assertEquals(true, map["captureProvenLive"])
  }

  @Test
  fun `live apm without hardware claims webrtc_apm with mode and erle`() {
    val map = EchoStateReadback.build(
      requested = true,
      captureProvenLive = true,
      hardwareAecAttached = false,
      apmLive = true,
      apmMobileAec = false,
      erleDb = 7.5,
    )
    assertEquals("webrtc_apm", map["mechanism"])
    assertEquals(true, map["nativeEnabled"])
    assertEquals("aec3", map["apmMode"])
    assertEquals(7.5, map["erleDb"])
  }

  @Test
  fun `aecm mode is reported honestly`() {
    val map = EchoStateReadback.build(
      requested = true,
      captureProvenLive = false,
      hardwareAecAttached = false,
      apmLive = true,
      apmMobileAec = true,
      erleDb = null,
    )
    assertEquals("aecm", map["apmMode"])
  }

  @Test
  fun `no attached mechanism is an honest none — never the bare capture source`() {
    // requested=true models the pre-0.0.16 ghost: voiceProcessing requested,
    // VOICE_COMMUNICATION source in use, but nothing verifiably attached.
    val map = EchoStateReadback.build(
      requested = true,
      captureProvenLive = true,
      hardwareAecAttached = false,
      apmLive = false,
      apmMobileAec = false,
      erleDb = null,
    )
    assertEquals("none", map["mechanism"])
    assertEquals(false, map["nativeEnabled"])
    assertNull(map["apmMode"])
    assertNull(map["erleDb"])
  }
}
